import Foundation

/// 智能调频配置
public struct SmartFreqConfig: Codable {
  public var isEnabled: Bool
  /// 两次分析之间最小间隔（分钟）
  public var intervalMinutes: Int
  /// 月度 Token 预算上限（0=不限）
  public var monthlyTokenBudget: Int
  /// 当月已消耗 Token 数
  public var monthlyTokensUsed: Int
  /// 预算统计月份（yyyy-MM 格式，用于月度重置）
  public var budgetMonth: String
  /// 上次执行时间
  public var lastRunDate: Date?
  /// Whether names and contextual phrases may be proposed. Off by default for privacy.
  public var includePersonalSuggestions: Bool?
  /// Cap retained custom phrases during each successful merge. Nil uses the default cap.
  public var phraseBudget: Int?

  public init(
    isEnabled: Bool = false,
    intervalMinutes: Int = 24 * 60,
    monthlyTokenBudget: Int = 0,
    monthlyTokensUsed: Int = 0,
    budgetMonth: String = "",
    lastRunDate: Date? = nil,
    includePersonalSuggestions: Bool? = false,
    phraseBudget: Int? = 500
  ) {
    self.isEnabled = isEnabled
    self.intervalMinutes = intervalMinutes
    self.monthlyTokenBudget = monthlyTokenBudget
    self.monthlyTokensUsed = monthlyTokensUsed
    self.budgetMonth = budgetMonth
    self.lastRunDate = lastRunDate
    self.includePersonalSuggestions = includePersonalSuggestions
    self.phraseBudget = phraseBudget
  }
}
