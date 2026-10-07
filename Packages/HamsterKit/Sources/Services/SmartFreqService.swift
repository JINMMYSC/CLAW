import Foundation
import OSLog

/// 智能调频服务 - 静默分析 ClawTalk 记录，自动优化候选词排序并添加新词
public class SmartFreqService {
  public static let shared = SmartFreqService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let configKey = "smart_freq_config"
  private let resultsKey = "smart_freq_results"
  private let validationReportKey = "smart_freq_validation_report"
  private let logger = Logger(subsystem: "com.hamster", category: "SmartFreq")

  private let maxResults = 50

  // MARK: - Prompt

  public static let defaultPrompt = """
你是中文输入法词频优化专家。根据用户输入记录，分析高频词汇和用语习惯，输出词频调整规则。

## 输出格式（严格遵守，每行一条，用 Tab 分隔）

频率调整：
FREQ\tboost|demote\t全拼编码\t词语

新词添加（用户反复输入但标准词库可能没有的词/短语）：
NEW\t全拼编码\t词语

## 规则

1. boost = 该词在用户输入中高频出现，应提升到候选前列
2. demote = 该编码下有更常用的词被排挤，降低干扰词优先级
3. 全拼编码 = 声母韵母连写无空格（如"你好"→"nihao"，"世界"→"shijie"）
4. 只输出有明确依据的调整，不猜测
5. 新词仅限用户多次输入的非标准词汇/缩写/网络用语
6. 单次最多 50 条规则
7. 不要输出任何其他文本，只输出规则行

## 用户输入记录

{data}
"""

  // MARK: - Config

  public var config: SmartFreqConfig {
    get {
      guard let data = defaults?.data(forKey: configKey),
            let c = try? JSONDecoder().decode(SmartFreqConfig.self, from: data)
      else { return SmartFreqConfig() }
      return c
    }
    set {
      defaults?.set(try? JSONEncoder().encode(newValue), forKey: configKey)
    }
  }

  // MARK: - Results

  public var results: [SmartFreqResult] {
    get {
      guard let data = defaults?.data(forKey: resultsKey),
            let r = try? JSONDecoder().decode([SmartFreqResult].self, from: data)
      else { return [] }
      return r.sorted { $0.date > $1.date }
    }
    set {
      let trimmed = newValue.sorted { $0.date > $1.date }.prefix(maxResults)
      defaults?.set(try? JSONEncoder().encode(Array(trimmed)), forKey: resultsKey)
    }
  }

  /// Most recent validation outcome. Pending and rejected model output never reaches RIME.
  public var validationReport: SmartFreqValidationReport {
    get {
      guard let data = defaults?.data(forKey: validationReportKey),
            let report = try? JSONDecoder().decode(SmartFreqValidationReport.self, from: data)
      else { return SmartFreqValidationReport() }
      return report
    }
    set {
      defaults?.set(try? JSONEncoder().encode(newValue), forKey: validationReportKey)
    }
  }

  // MARK: - Aggregate Stats

  /// 累计调频次数（boost + demote）
  public var totalFreqAdjustments: Int {
    results.reduce(0) { $0 + $1.boostCount + $1.demoteCount }
  }

  /// 累计新增词数
  public var totalNewPhrases: Int {
    results.reduce(0) { $0 + $1.newPhraseCount }
  }

  /// 当月 Token 消耗
  public var currentMonthTokens: Int {
    let cfg = config
    let currentMonth = Self.monthString(for: Date())
    return cfg.budgetMonth == currentMonth ? cfg.monthlyTokensUsed : 0
  }

  public func deleteResult(_ id: UUID) {
    results = results.filter { $0.id != id }
  }

  /// 清空所有规则文件
  public func resetAllRules() {
    let rulesURL = Self.rulesFileURL
    let phrasesURL = Self.phrasesFileURL
    try? "".write(to: rulesURL, atomically: true, encoding: .utf8)
    try? "".write(to: phrasesURL, atomically: true, encoding: .utf8)
    results = []
    validationReport = SmartFreqValidationReport()
    var cfg = config
    cfg.monthlyTokensUsed = 0
    config = cfg
    logger.info("SmartFreq: all rules reset")
  }

  // MARK: - File Paths

  /// 调频规则文件路径（App Group 内 RIME userData 目录）
  public static var rulesFileURL: URL {
    FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("smart_freq_rules.txt")
  }

  /// 新词规则文件路径
  public static var phrasesFileURL: URL {
    FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("claw_smart_freq.txt")
  }

  // MARK: - Trigger Check

  public var shouldRun: Bool {
    let cfg = config
    guard cfg.isEnabled else { return false }
    let provider = AIService.shared.selectedProvider
    guard !AIService.shared.apiKey(for: provider).isEmpty else { return false }
    // Token 预算检查
    if cfg.monthlyTokenBudget > 0 {
      let currentMonth = Self.monthString(for: Date())
      if cfg.budgetMonth == currentMonth && cfg.monthlyTokensUsed >= cfg.monthlyTokenBudget {
        return false
      }
    }
    guard let lastRun = cfg.lastRunDate else { return true }
    let minInterval = TimeInterval(cfg.intervalMinutes * 60)
    return Date().timeIntervalSince(lastRun) >= minInterval
  }

  public func runIfNeeded() async {
    guard shouldRun else { return }
    var cfg = config
    cfg.lastRunDate = Date()
    config = cfg

    await run()
  }

  // MARK: - Core Analysis

  private func run() async {
    let cfg = config
    let clawTalkText = loadClawTalkText(sinceMinutes: cfg.intervalMinutes)
    guard !clawTalkText.isEmpty else {
      logger.info("SmartFreq: no ClawTalk data in the past \(cfg.intervalMinutes)min, skipping")
      return
    }

    let privacyInstruction = cfg.includePersonalSuggestions == true
      ? "可以建议输入记录中明确重复出现的人名或上下文短语，但仍须满足观察次数规则。"
      : "不要建议人名、联系方式、地址或只在特定上下文中有意义的私密短语。"
    let prompt = (Self.defaultPrompt + "\n\n## 隐私范围\n" + privacyInstruction)
      .replacingOccurrences(of: "{data}", with: clawTalkText)

    let requestConfiguration = AIService.shared.currentRequestConfiguration
    let result = await callAIWithUsage(prompt: prompt, configuration: requestConfiguration)

    guard case .success(let (response, usage)) = result else {
      if case .failure(let error) = result {
        logger.error("SmartFreq: AI call failed: \(error.localizedDescription)")
        LogService.shared.log(.smartFreqRequestFailed)
      }
      return
    }

    let (freqRules, newPhrases) = parseRules(response)
    let drafts = freqRules.map {
      SmartFreqDraft(
        kind: .frequency,
        action: $0.action,
        code: $0.code,
        word: $0.word,
        observedCount: Self.occurrenceCount(of: $0.word, in: clawTalkText)
      )
    } + newPhrases.map {
      SmartFreqDraft(
        kind: .newPhrase,
        code: $0.code,
        word: $0.word,
        observedCount: Self.occurrenceCount(of: $0.word, in: clawTalkText)
      )
    }
    let existing = loadAcceptedPhrases(from: Self.phrasesFileURL)
    let report = SmartFreqValidator().validate(
      drafts,
      existing: existing,
      acceptanceBudget: min(maxResults, max(0, config.phraseBudget ?? 500))
    )
    validationReport = report
    mergeAcceptedPhrases(report.accepted)

    let acceptedKeys = Set(report.accepted.map { "\($0.code)\u{1f}\($0.word)" })
    let acceptedFreqRules = freqRules.filter { acceptedKeys.contains("\($0.code)\u{1f}\($0.word)") }
    let acceptedNewPhrases = newPhrases.filter { acceptedKeys.contains("\($0.code)\u{1f}\($0.word)") }

    // Mirror durable lexical learning into the shared Memory Core so rewrite/reply Skills
    // can benefit from the same phrases instead of SmartFreq owning a private silo.
    for rule in acceptedFreqRules.filter({ $0.action == "boost" }).prefix(30) {
      try? ClawMemoryStore.shared.upsertMemory(ClawMemoryItem(
        kind: .reusablePhrase,
        content: "用户常用词：\(rule.word)",
        normalizedKey: "smartfreq:boost:\(rule.word.lowercased())",
        sourceType: "smart-freq",
        sourceRef: rule.code,
        confidence: 0.82
      ))
    }
    for phrase in acceptedNewPhrases.prefix(30) {
      try? ClawMemoryStore.shared.upsertMemory(ClawMemoryItem(
        kind: .reusablePhrase,
        content: "用户常用短语：\(phrase.word)",
        normalizedKey: "smartfreq:phrase:\(phrase.word.lowercased())",
        sourceType: "smart-freq",
        sourceRef: phrase.code,
        confidence: 0.78
      ))
    }

    let entryCount = clawTalkText.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    let tokensUsed = usage?.totalTokens ?? 0

    // 保存分析结果
    let analysisResult = SmartFreqResult(
      entriesCount: entryCount,
      boostCount: acceptedFreqRules.filter { $0.action == "boost" }.count,
      demoteCount: acceptedFreqRules.filter { $0.action == "demote" }.count,
      newPhraseCount: acceptedNewPhrases.count,
      tokensUsed: tokensUsed
    )
    var allResults = results
    allResults.insert(analysisResult, at: 0)
    results = allResults

    // 更新 Token 用量
    updateTokenUsage(tokensUsed)

    logger.info("SmartFreq: done. boost=\(analysisResult.boostCount) demote=\(analysisResult.demoteCount) new=\(analysisResult.newPhraseCount) tokens=\(tokensUsed)")
  }

  // MARK: - Data Loading

  private func loadClawTalkText(sinceMinutes minutes: Int) -> String {
    let since = Date().addingTimeInterval(TimeInterval(-minutes * 60))
    let calendar = Calendar.current
    var lines: [String] = []

    var cursor = since
    while cursor <= Date() {
      let entries = ClawTalkDataService.shared.entries(for: cursor)
        .filter { $0.startTime >= since && $0.isMeaningful }
      for e in entries {
        let text = String(e.text.prefix(300))
        lines.append(text)
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - AI Call

  private func callAIWithUsage(
    prompt: String,
    configuration: AIRequestConfiguration
  ) async -> Result<(String, AIUsage?), Error> {
    await withCheckedContinuation { continuation in
      let messages = [AIMessage(role: "user", content: prompt)]
      AIService.shared.chatWithUsage(messages: messages, configuration: configuration) { result in
        continuation.resume(returning: result)
      }
    }
  }

  // MARK: - Parse Rules

  struct FreqRule {
    let action: String  // "boost" or "demote"
    let code: String
    let word: String
  }

  struct NewPhrase {
    let code: String
    let word: String
  }

  func parseRules(_ response: String) -> ([FreqRule], [NewPhrase]) {
    var freqRules: [FreqRule] = []
    var newPhrases: [NewPhrase] = []

    for line in response.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

      let parts = trimmed.components(separatedBy: "\t")

      if parts.count >= 4 && parts[0] == "FREQ" {
        let action = parts[1].lowercased()
        guard action == "boost" || action == "demote" else { continue }
        let code = parts[2].lowercased().trimmingCharacters(in: .whitespaces)
        let word = parts[3].trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty && !word.isEmpty else { continue }
        freqRules.append(FreqRule(action: action, code: code, word: word))
      } else if parts.count >= 3 && parts[0] == "NEW" {
        let code = parts[1].lowercased().trimmingCharacters(in: .whitespaces)
        let word = parts[2].trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty && !word.isEmpty else { continue }
        newPhrases.append(NewPhrase(code: code, word: word))
      }
    }

    return (freqRules, newPhrases)
  }

  // MARK: - Write Rules

  func mergeFreqRules(_ rules: [FreqRule]) {
    guard !rules.isEmpty else { return }
    let url = Self.rulesFileURL

    // 读取现有规则，合并去重
    var existing = loadExistingLines(from: url)
    var existingSet = Set(existing)

    for rule in rules {
      let line = "\(rule.action)\t\(rule.code)\t\(rule.word)"
      if !existingSet.contains(line) {
        existing.append(line)
        existingSet.insert(line)
      }
    }

    let content = existing.joined(separator: "\n") + "\n"
    try? content.write(to: url, atomically: true, encoding: .utf8)
  }

  func mergeNewPhrases(_ phrases: [NewPhrase]) {
    guard !phrases.isEmpty else { return }
    let url = Self.phrasesFileURL

    var existing = loadExistingLines(from: url)
    var existingSet = Set(existing)

    for phrase in phrases {
      let line = "\(phrase.code)\t\(phrase.word)"
      if !existingSet.contains(line) {
        existing.append(line)
        existingSet.insert(line)
      }
    }

    let content = existing.joined(separator: "\n") + "\n"
    try? content.write(to: url, atomically: true, encoding: .utf8)
  }

  public func mergeAcceptedPhrases(_ phrases: [SmartFreqAcceptedPhrase]) {
    guard !phrases.isEmpty else { return }
    var existing = loadAcceptedPhrases(from: Self.phrasesFileURL)
    var keys = Set(existing.map { "\($0.code)\u{1f}\($0.word)" })
    for phrase in phrases where keys.insert("\(phrase.code)\u{1f}\(phrase.word)").inserted {
      existing.append(phrase)
    }
    let retained = Array(existing.suffix(max(1, config.phraseBudget ?? 500)))
    let content = retained.map(\.rimeLine).joined(separator: "\n") + "\n"
    do {
      try FileManager.default.createDirectory(
        at: Self.phrasesFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: Self.phrasesFileURL, atomically: true, encoding: .utf8)
    } catch {
      logger.error("SmartFreq: accepted phrase write failed")
    }
  }

  public func loadAcceptedPhrases(from url: URL) -> [SmartFreqAcceptedPhrase] {
    loadExistingLines(from: url).compactMap { line in
      let columns = line.components(separatedBy: "\t")
      guard columns.count >= 2 else { return nil }
      if columns.count >= 3, let weight = Int(columns[2]) {
        return SmartFreqAcceptedPhrase(code: columns[1], word: columns[0], weight: weight)
      }
      // Migrate the former code<TAB>word file on the next successful write.
      return SmartFreqAcceptedPhrase(code: columns[0], word: columns[1], weight: 100)
    }
  }

  func loadExistingLines(from url: URL) -> [String] {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return content.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
  }

  // MARK: - Token Tracking

  private func updateTokenUsage(_ tokens: Int) {
    var cfg = config
    let currentMonth = Self.monthString(for: Date())
    if cfg.budgetMonth != currentMonth {
      cfg.budgetMonth = currentMonth
      cfg.monthlyTokensUsed = tokens
    } else {
      cfg.monthlyTokensUsed += tokens
    }
    config = cfg
  }

  static func monthString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: date)
  }

  static func occurrenceCount(of word: String, in text: String) -> Int {
    guard !word.isEmpty else { return 0 }
    return max(0, text.components(separatedBy: word).count - 1)
  }
}
