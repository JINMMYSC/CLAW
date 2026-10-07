import Foundation

/// 支持的 AI 提供商
public enum AIProvider: String, Codable, CaseIterable, Equatable {
  case openai      = "OpenAI"
  case openrouter  = "OpenRouter"
  case claude      = "Claude"
  case kimi        = "Kimi"
  case minimax     = "MiniMax"
  case glm         = "GLM"
  case deepseek    = "DeepSeek"

  public var baseURL: String {
    switch self {
    case .openai:     return "https://api.openai.com/v1"
    case .openrouter: return "https://openrouter.ai/api/v1"
    case .claude:     return "https://api.anthropic.com/v1"
    case .kimi:       return "https://api.moonshot.cn/v1"
    case .minimax:    return "https://api.minimax.chat/v1"
    case .glm:        return "https://open.bigmodel.cn/api/paas/v4"
    case .deepseek:   return "https://api.deepseek.com/v1"
    }
  }

  public var defaultModel: String {
    switch self {
    case .openai:     return "gpt-4o"
    case .openrouter: return "openai/gpt-4o"
    case .claude:     return "claude-opus-4-6"
    case .kimi:       return "moonshot-v1-8k"
    case .minimax:    return "abab6.5s-chat"
    case .glm:        return "glm-4-flash"
    case .deepseek:   return "deepseek-chat"
    }
  }

  /// 使用 OpenAI 兼容协议的提供商
  public var isOpenAICompat: Bool { self != .claude }
}

/// AI Prompt 模板
public struct AIPrompt: Codable, Identifiable {
  public let id: UUID
  public var name: String
  public var content: String

  public init(id: UUID = UUID(), name: String, content: String) {
    self.id = id
    self.name = name
    self.content = content
  }
}

/// AI 对话消息
public struct AIMessage: Codable {
  public let role: String   // "user" | "assistant" | "system"
  public let content: String

  public init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

/// AI Token 用量
public struct AIUsage: Codable {
  public let inputTokens: Int
  public let outputTokens: Int
  public var totalTokens: Int { inputTokens + outputTokens }

  public init(inputTokens: Int, outputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}

/// Immutable routing parameters for one AI request. Capturing this value before
/// starting async work prevents one feature's settings change from affecting
/// another request already in flight.
public struct AIRequestConfiguration: Equatable {
  public let provider: AIProvider
  public let model: String
  public let maxTokens: Int

  public init(provider: AIProvider, model: String? = nil, maxTokens: Int = 4096) {
    self.provider = provider
    self.model = model ?? provider.defaultModel
    self.maxTokens = max(256, maxTokens)
  }
}

/// AI 服务 - 统一封装 OpenAI / OpenRouter / Claude API
public class AIService {
  public static let shared = AIService()

  private let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
  private let secureStore = ClawSecureStore.shared

  // MARK: - Config Storage

  public var selectedProvider: AIProvider {
    get {
      let raw = defaults?.string(forKey: "ai_provider") ?? AIProvider.claude.rawValue
      return AIProvider(rawValue: raw) ?? .claude
    }
    set { defaults?.set(newValue.rawValue, forKey: "ai_provider") }
  }

  public var selectedModel: String {
    get { defaults?.string(forKey: "ai_model") ?? selectedProvider.defaultModel }
    set { defaults?.set(newValue, forKey: "ai_model") }
  }

  public var currentRequestConfiguration: AIRequestConfiguration {
    let provider = selectedProvider
    return AIRequestConfiguration(provider: provider, model: selectedModel)
  }

  public func apiKey(for provider: AIProvider) -> String {
    let account = secureAccount(for: provider)
    let marker = migrationMarkerKey(for: provider, role: processRole)
    let legacyKey = legacyDefaultsKey(for: provider)
    let roleIsCurrent = defaults?.bool(forKey: marker) ?? false

    if !roleIsCurrent,
       let handoff = defaults?.string(forKey: legacyKey),
       !handoff.isEmpty {
      do {
        try secureStore.setString(handoff, for: account)
        defaults?.set(true, forKey: marker)
        cleanupLegacyKeyIfMigratedEverywhere(provider)
      } catch {
        LogService.shared.log("Keychain migration unavailable for \(provider.rawValue)", level: .warn, tag: "AI")
      }
      return handoff
    }

    do {
      if let secure = try secureStore.string(for: account), !secure.isEmpty {
        if !roleIsCurrent {
          defaults?.set(true, forKey: marker)
          cleanupLegacyKeyIfMigratedEverywhere(provider)
        }
        return secure
      }
    } catch {
      LogService.shared.log("Keychain read unavailable for \(provider.rawValue)", level: .warn, tag: "AI")
    }

    guard let legacy = defaults?.string(forKey: legacyKey), !legacy.isEmpty else { return "" }
    do {
      try secureStore.setString(legacy, for: account)
      defaults?.set(true, forKey: marker)
      cleanupLegacyKeyIfMigratedEverywhere(provider)
    } catch {
      LogService.shared.log("Keychain migration unavailable for \(provider.rawValue)", level: .warn, tag: "AI")
    }
    return legacy
  }

  public func setApiKey(_ key: String, for provider: AIProvider) {
    let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = secureAccount(for: provider)
    let legacyKey = legacyDefaultsKey(for: provider)
    if cleaned.isEmpty {
      try? secureStore.remove(account)
      defaults?.removeObject(forKey: legacyKey)
      defaults?.removeObject(forKey: migrationMarkerKey(for: provider, role: "host"))
      defaults?.removeObject(forKey: migrationMarkerKey(for: provider, role: "keyboard"))
      return
    }

    defaults?.set(cleaned, forKey: legacyKey)
    defaults?.set(false, forKey: migrationMarkerKey(for: provider, role: otherProcessRole))
    do {
      try secureStore.setString(cleaned, for: account)
      defaults?.set(true, forKey: migrationMarkerKey(for: provider, role: processRole))
      cleanupLegacyKeyIfMigratedEverywhere(provider)
    } catch {
      LogService.shared.log("Keychain write unavailable for \(provider.rawValue); using compatibility storage", level: .warn, tag: "AI")
    }
  }

  private func secureAccount(for provider: AIProvider) -> String {
    "ai-key-\(provider.rawValue.lowercased())"
  }

  private func legacyDefaultsKey(for provider: AIProvider) -> String {
    "ai_key_\(provider.rawValue)"
  }

  private var processRole: String {
    Bundle.main.bundleURL.pathExtension.lowercased() == "appex" ? "keyboard" : "host"
  }

  private var otherProcessRole: String {
    processRole == "host" ? "keyboard" : "host"
  }

  private func migrationMarkerKey(for provider: AIProvider, role: String) -> String {
    "ai_keychain_migrated_\(provider.rawValue)_\(role)_v1"
  }

  private func cleanupLegacyKeyIfMigratedEverywhere(_ provider: AIProvider) {
    let host = defaults?.bool(forKey: migrationMarkerKey(for: provider, role: "host")) ?? false
    let keyboard = defaults?.bool(forKey: migrationMarkerKey(for: provider, role: "keyboard")) ?? false
    if host && keyboard {
      defaults?.removeObject(forKey: legacyDefaultsKey(for: provider))
    }
  }

  // MARK: - Prompt Management

  private let promptsKey = "ai_prompts"

  public var savedPrompts: [AIPrompt] {
    get {
      guard let data = defaults?.data(forKey: promptsKey),
            let prompts = try? JSONDecoder().decode([AIPrompt].self, from: data)
      else { return defaultPrompts }
      return prompts
    }
    set {
      defaults?.set(try? JSONEncoder().encode(newValue), forKey: promptsKey)
    }
  }

  private var defaultPrompts: [AIPrompt] {
    [
      AIPrompt(name: "输入习惯分析", content: "请分析以下我的输入记录，总结我的输入习惯、常用词汇、关注话题，并给出洞察：\n\n"),
      AIPrompt(name: "剪贴板内容整理", content: "以下是我最近的剪贴板内容，请帮我整理、分类，提取关键信息：\n\n"),
      AIPrompt(name: "写作风格分析", content: "请分析以下文本样本，描述我的写作风格特点：\n\n"),
      AIPrompt(name: "自由问答", content: ""),
    ]
  }

  public func addPrompt(_ prompt: AIPrompt) {
    var prompts = savedPrompts
    prompts.append(prompt)
    savedPrompts = prompts
  }

  public func updatePrompt(_ prompt: AIPrompt) {
    var prompts = savedPrompts
    if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
      prompts[idx] = prompt
    }
    savedPrompts = prompts
  }

  public func deletePrompt(id: UUID) {
    savedPrompts = savedPrompts.filter { $0.id != id }
  }

  // MARK: - Chat

  /// 发送消息到当前选定的 AI 提供商
  @discardableResult
  public func chat(
    messages: [AIMessage],
    completion: @escaping (Result<String, Error>) -> Void
  ) -> URLSessionDataTask? {
    chatWithUsage(messages: messages) { result in
      completion(result.map { $0.0 })
    }
  }

  /// 发送消息并返回 token 用量
  @discardableResult
  public func chatWithUsage(
    messages: [AIMessage],
    completion: @escaping (Result<(String, AIUsage?), Error>) -> Void
  ) -> URLSessionDataTask? {
    chatWithUsage(messages: messages, configuration: currentRequestConfiguration, completion: completion)
  }

  /// Request-scoped routing. This avoids mutating the process-wide selected provider/model when
  /// keyboard, AutoInsight and the assistant are active at the same time.
  @discardableResult
  public func chat(
    messages: [AIMessage],
    provider: AIProvider,
    model: String? = nil,
    completion: @escaping (Result<String, Error>) -> Void
  ) -> URLSessionDataTask? {
    chatWithUsage(messages: messages, configuration: AIRequestConfiguration(provider: provider, model: model)) { result in
      completion(result.map { $0.0 })
    }
  }

  @discardableResult
  public func chatWithUsage(
    messages: [AIMessage],
    provider: AIProvider,
    model: String,
    completion: @escaping (Result<(String, AIUsage?), Error>) -> Void
  ) -> URLSessionDataTask? {
    chatWithUsage(
      messages: messages,
      configuration: AIRequestConfiguration(provider: provider, model: model),
      completion: completion
    )
  }

  @discardableResult
  public func chat(
    messages: [AIMessage],
    configuration: AIRequestConfiguration,
    completion: @escaping (Result<String, Error>) -> Void
  ) -> URLSessionDataTask? {
    chatWithUsage(messages: messages, configuration: configuration) { result in
      completion(result.map { $0.0 })
    }
  }

  @discardableResult
  public func chatWithUsage(
    messages: [AIMessage],
    configuration: AIRequestConfiguration,
    completion: @escaping (Result<(String, AIUsage?), Error>) -> Void
  ) -> URLSessionDataTask? {
    let provider = configuration.provider
    let key = apiKey(for: provider)
    guard !key.isEmpty else {
      completion(.failure(AIError.noAPIKey(provider)))
      return nil
    }
    switch provider {
    case .claude:
      return chatClaudeWithUsage(
        messages: messages,
        apiKey: key,
        model: configuration.model,
        maxTokens: configuration.maxTokens,
        completion: completion
      )
    default:
      return chatOpenAICompatWithUsage(
        messages: messages,
        provider: provider,
        apiKey: key,
        model: configuration.model,
        maxTokens: configuration.maxTokens,
        completion: completion
      )
    }
  }

  // MARK: - OpenAI-compatible (OpenAI + OpenRouter)

  private func chatOpenAICompatWithUsage(
    messages: [AIMessage],
    provider: AIProvider,
    apiKey: String,
    model: String,
    maxTokens: Int,
    completion: @escaping (Result<(String, AIUsage?), Error>) -> Void
  ) -> URLSessionDataTask {
    let urlString = "\(provider.baseURL)/chat/completions"
    let url = URL(string: urlString)!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if provider == .openrouter {
      req.setValue("ClawTalk iOS", forHTTPHeaderField: "X-Title")
    }
    let body: [String: Any] = [
      "model": model,
      "messages": messages.map { ["role": $0.role, "content": $0.content] },
      "max_tokens": maxTokens,
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let log = LogService.shared
    log.log("→ \(provider.rawValue) \(model) \(urlString) msgs=\(messages.count)", tag: "AI")

    let task = URLSession.shared.dataTask(with: req) { data, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if let error = error {
        log.log("✗ network error: \(error.localizedDescription)", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(error)) }; return
      }
      guard let data else {
        log.log("✗ empty response (HTTP \(status))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.emptyResponse)) }; return
      }
      let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log.log("✗ parse error (HTTP \(status)) body=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.parseError)) }; return
      }
      if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
        log.log("✗ API error (HTTP \(status)): \(msg) | raw=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.apiError(msg))) }; return
      }
      guard let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
      else {
        log.log("✗ unexpected JSON (HTTP \(status)) body=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.parseError)) }; return
      }
      var usage: AIUsage?
      if let usageObj = json["usage"] as? [String: Any] {
        let input = usageObj["prompt_tokens"] as? Int ?? 0
        let output = usageObj["completion_tokens"] as? Int ?? 0
        usage = AIUsage(inputTokens: input, outputTokens: output)
        log.log("✓ OK HTTP \(status) in=\(input) out=\(output)", tag: "AI")
      } else {
        log.log("✓ OK HTTP \(status) (no usage info)", tag: "AI")
      }
      DispatchQueue.main.async { completion(.success((content, usage))) }
    }
    task.resume()
    return task
  }

  // MARK: - Claude (Anthropic Messages API)

  private func chatClaudeWithUsage(
    messages: [AIMessage],
    apiKey: String,
    model: String,
    maxTokens: Int,
    completion: @escaping (Result<(String, AIUsage?), Error>) -> Void
  ) -> URLSessionDataTask {
    let urlString = "https://api.anthropic.com/v1/messages"
    let url = URL(string: urlString)!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let systemMsg = messages.first(where: { $0.role == "system" })?.content
    let chatMsgs = messages.filter { $0.role != "system" }
    var body: [String: Any] = [
      "model": model,
      "max_tokens": maxTokens,
      "messages": chatMsgs.map { ["role": $0.role, "content": $0.content] },
    ]
    if let sys = systemMsg, !sys.isEmpty { body["system"] = sys }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let log = LogService.shared
    log.log("→ Claude \(model) \(urlString) msgs=\(messages.count)", tag: "AI")

    let task = URLSession.shared.dataTask(with: req) { data, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if let error = error {
        log.log("✗ network error: \(error.localizedDescription)", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(error)) }; return
      }
      guard let data else {
        log.log("✗ empty response (HTTP \(status))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.emptyResponse)) }; return
      }
      let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log.log("✗ parse error (HTTP \(status)) body=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.parseError)) }; return
      }
      if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
        log.log("✗ API error (HTTP \(status)): \(msg) | raw=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.apiError(msg))) }; return
      }
      guard let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
      else {
        log.log("✗ unexpected JSON (HTTP \(status)) body=\(rawBody.prefix(400))", level: .error, tag: "AI")
        DispatchQueue.main.async { completion(.failure(AIError.parseError)) }; return
      }
      var usage: AIUsage?
      if let usageObj = json["usage"] as? [String: Any] {
        let input = usageObj["input_tokens"] as? Int ?? 0
        let output = usageObj["output_tokens"] as? Int ?? 0
        usage = AIUsage(inputTokens: input, outputTokens: output)
        log.log("✓ OK HTTP \(status) in=\(input) out=\(output)", tag: "AI")
      } else {
        log.log("✓ OK HTTP \(status) (no usage info)", tag: "AI")
      }
      DispatchQueue.main.async { completion(.success((text, usage))) }
    }
    task.resume()
    return task
  }

  // MARK: - Errors

  public enum AIError: LocalizedError {
    case noAPIKey(AIProvider)
    case emptyResponse
    case parseError
    case apiError(String)

    public var errorDescription: String? {
      switch self {
      case .noAPIKey(let p): return "请先在设置中填入 \(p.rawValue) API Key"
      case .emptyResponse: return "AI 返回了空响应"
      case .parseError: return "解析 AI 响应失败"
      case .apiError(let msg): return "AI API 错误：\(msg)"
      }
    }
  }
}
