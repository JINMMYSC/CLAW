import Combine
import Foundation
import HamsterKit

@MainActor
public class SmartFreqViewModel: ObservableObject {
  private let service = SmartFreqService.shared
  private let aiService = AIService.shared

  // MARK: - Results

  @Published public var results: [SmartFreqResult] = []

  // MARK: - Stats

  @Published public var totalFreqAdjustments: Int = 0
  @Published public var totalNewPhrases: Int = 0
  @Published public var currentMonthTokens: Int = 0
  @Published public var lastRunDate: Date?
  @Published public var validationReport = SmartFreqValidationReport()
  @Published public var applyStatus: String?
  @Published public var isApplying = false
  @Published public var canRollback = false

  // MARK: - Config

  @Published public var isEnabled: Bool = false
  @Published public var intervalMinutes: Int = 24 * 60
  @Published public var monthlyTokenBudget: Int = 0
  @Published public var includePersonalSuggestions = false
  @Published public var phraseBudget = 500

  // MARK: - AI Config

  @Published public var aiSelectedProvider: AIProvider = AIService.shared.selectedProvider
  @Published public var aiSelectedModel: String = AIService.shared.selectedModel

  public init() {
    reload()
  }

  // MARK: - Data

  public func reload() {
    results = service.results
    totalFreqAdjustments = service.totalFreqAdjustments
    totalNewPhrases = service.totalNewPhrases
    currentMonthTokens = service.currentMonthTokens

    let cfg = service.config
    isEnabled = cfg.isEnabled
    intervalMinutes = cfg.intervalMinutes
    monthlyTokenBudget = cfg.monthlyTokenBudget
    lastRunDate = cfg.lastRunDate
    includePersonalSuggestions = cfg.includePersonalSuggestions ?? false
    phraseBudget = cfg.phraseBudget ?? 500
    validationReport = service.validationReport
    canRollback = SmartFreqApplyService.shared.canRollback
  }

  public func saveConfig() {
    var cfg = service.config
    cfg.isEnabled = isEnabled
    cfg.intervalMinutes = intervalMinutes
    cfg.monthlyTokenBudget = monthlyTokenBudget
    cfg.includePersonalSuggestions = includePersonalSuggestions
    cfg.phraseBudget = max(1, phraseBudget)
    service.config = cfg
  }

  // MARK: - AI Config

  public func setProvider(_ provider: AIProvider) {
    aiService.selectedProvider = provider
    aiSelectedProvider = provider
    aiSelectedModel = provider.defaultModel
    aiService.selectedModel = aiSelectedModel
  }

  public func setModel(_ model: String) {
    aiService.selectedModel = model
    aiSelectedModel = model
  }

  public func setAPIKey(_ key: String, for provider: AIProvider) {
    aiService.setApiKey(key, for: provider)
  }

  public func apiKey(for provider: AIProvider) -> String {
    aiService.apiKey(for: provider)
  }

  // MARK: - Actions

  public func deleteResult(_ result: SmartFreqResult) {
    service.deleteResult(result.id)
    reload()
  }

  public func resetAllRules() {
    service.resetAllRules()
    reload()
  }

  public func applyValidatedPhrases() {
    guard !isApplying else { return }
    isApplying = true
    applyStatus = "正在创建快照并部署…"
    Task { @MainActor in
      defer { isApplying = false }
      do {
        let summary = try SmartFreqApplyService.shared.apply()
        applyStatus = "已向 \(summary.schemaNames.joined(separator: "、")) 部署 \(summary.phraseCount) 个词条"
      } catch {
        applyStatus = "应用失败：\(error.localizedDescription)"
      }
      reload()
    }
  }

  public func rollbackLastApply() {
    guard !isApplying else { return }
    isApplying = true
    applyStatus = "正在恢复上次快照…"
    Task { @MainActor in
      defer { isApplying = false }
      do {
        let summary = try SmartFreqApplyService.shared.rollback()
        applyStatus = "已回滚 \(summary.schemaNames.joined(separator: "、")) 并重新部署"
      } catch {
        applyStatus = "回滚失败：\(error.localizedDescription)"
      }
      reload()
    }
  }

  // MARK: - Formatting Helpers

  public func formatTokens(_ count: Int) -> String {
    if count >= 1000 {
      return String(format: "%.1fK", Double(count) / 1000.0)
    }
    return "\(count)"
  }

  public func relativeTime(from date: Date?) -> String {
    guard let date = date else { return "从未" }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "刚刚" }
    if interval < 3600 { return "\(Int(interval / 60))分钟前" }
    if interval < 86400 { return "\(Int(interval / 3600))小时前" }
    return "\(Int(interval / 86400))天前"
  }
}
