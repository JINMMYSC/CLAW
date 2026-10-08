import Combine
import Foundation
import HamsterKit

@MainActor
public class AutoInsightViewModel: ObservableObject {
  private let service = AutoInsightService.shared
  private let aiService = AIService.shared

  // MARK: - Results

  @Published public var results: [AutoInsightResult] = []
  @Published public var unreadCount: Int = 0
  @Published public var isRunning: Bool = false
  /// 手动触发的最后一次结果说明；用于界面提示，不再静默返回。
  @Published public var lastRunMessage: String?

  // MARK: - Config (live editing)

  @Published public var isEnabled: Bool = false
  @Published public var intervalMinutes: Int = 24 * 60
  @Published public var personalBackground: String = ""
  @Published public var spiritualPrompt: String = AutoInsightService.defaultSpiritualPrompt
  @Published public var taskPrompt: String = AutoInsightService.defaultTaskPrompt

  // MARK: - AI Config

  @Published public var aiSelectedProvider: AIProvider = AIService.shared.selectedProvider
  @Published public var aiSelectedModel: String = AIService.shared.selectedModel

  public init() {
    reload()
  }

  // MARK: - Data

  public func reload() {
    results = service.results
    unreadCount = service.unreadCount
    let cfg = service.config
    isEnabled = cfg.isEnabled
    intervalMinutes = cfg.intervalMinutes
    personalBackground = cfg.personalBackground
    spiritualPrompt = cfg.spiritualPrompt.isEmpty ? AutoInsightService.defaultSpiritualPrompt : cfg.spiritualPrompt
    taskPrompt = cfg.taskPrompt.isEmpty ? AutoInsightService.defaultTaskPrompt : cfg.taskPrompt
  }

  public func saveConfig() {
    var cfg = service.config
    cfg.isEnabled = isEnabled
    cfg.intervalMinutes = intervalMinutes
    cfg.personalBackground = personalBackground
    cfg.spiritualPrompt = spiritualPrompt
    cfg.taskPrompt = taskPrompt
    service.config = cfg
    if isEnabled {
      Task { await service.requestNotificationPermissionIfNeeded() }
    }
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

  public func triggerNow() async {
    guard !isRunning else { return }
    isRunning = true
    lastRunMessage = nil
    let outcome = await service.runNow()
    reload()
    isRunning = false
    lastRunMessage = Self.message(for: outcome)
  }

  private static func message(for outcome: AutoInsightService.RunOutcome) -> String {
    switch outcome {
    case .success(let entries):
      return "已生成新的洞察（使用 \(entries) 条记录）"
    case .noAPIKey(let provider):
      return "未配置 \(provider) 的 API Key，请先到「每日洞察设置」里填写"
    case .noData:
      return "最近没有可分析的输入记录，先在键盘上正常输入一些内容再试"
    case .failed(let message):
      return message
    }
  }

  public func deleteResult(_ result: AutoInsightResult) {
    service.deleteResult(result.id)
    reload()
  }

  public func markAsRead(_ result: AutoInsightResult) {
    service.markAsRead(result.id)
    reload()
  }

  // MARK: - Share

  public func shareText(for result: AutoInsightResult) -> String {
    let fmt = DateFormatter()
    fmt.dateStyle = .long
    fmt.timeStyle = .short
    let dateStr = fmt.string(from: result.date)
    return """
    📅 \(dateStr)

    💜 心灵安慰
    \(result.spiritualContent)

    📋 事务指导
    \(result.taskContent)

    — 由 Hamster 每日洞察生成
    """
  }

  public func shareSpiritual(_ result: AutoInsightResult) -> String { result.spiritualContent }
  public func shareTask(_ result: AutoInsightResult) -> String { result.taskContent }
}
