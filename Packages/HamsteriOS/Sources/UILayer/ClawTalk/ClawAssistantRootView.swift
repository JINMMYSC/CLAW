import CryptoKit
import HamsterKeyboardKit
import HamsterKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// CLAW 主 App：助手是首页，数据采集只是其中一个能力面板。
struct ClawAssistantRootView: View {
  @ObservedObject var viewModel: ClawTalkViewModel
  @State private var selectedTab: ClawAssistantTab = .assistant

  var body: some View {
    TabView(selection: $selectedTab) {
      ClawAssistantChatView()
        .tabItem { Label("助手", systemImage: "sparkles") }
        .tag(ClawAssistantTab.assistant)

      ClawSecretaryTodayView()
        .tabItem { Label("今日", systemImage: "checklist") }
        .tag(ClawAssistantTab.today)

      ClawPeopleView(onUseProfile: { selectedTab = .assistant })
        .tabItem { Label("人物", systemImage: "person.2.fill") }
        .tag(ClawAssistantTab.people)

      ClawMemoryCenterView()
        .tabItem { Label("记忆", systemImage: "brain.head.profile") }
        .tag(ClawAssistantTab.memory)

      ClawSettingsHubView(viewModel: viewModel)
        .tabItem { Label("设置", systemImage: "gearshape.fill") }
        .tag(ClawAssistantTab.settings)
    }
    .navigationTitle("CLAW")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      _ = ClawKeyboardDeferredEventService.shared.drainIntoHostServices()
      let openTasks = (try? ClawMemoryStore.shared.tasks(status: .open, limit: 100)) ?? []
      ClawWidgetSnapshotStore.save(.init(
        summary: openTasks.first?.title ?? "打开 CLAW 查看今日",
        openTaskCount: openTasks.count
      ))
      // Never expose personal memory text to system Spotlight by default.
      ClawSpotlightIndexer.indexSafeMemoryShortcut()
      // Heavy maintenance belongs in the host app, never in Keyboard Extension.
      Task(priority: .utility) {
        await AutoInsightService.shared.runIfNeeded()
        await SmartFreqService.shared.runIfNeeded()
        if let skills = try? ClawMemoryStore.shared.skills() {
          for skill in skills {
            _ = ClawEvolutionEngine.shared.evolveIfNeeded(skillID: skill.id)
          }
        }
      }
      for profile in HeartTargetService.shared.profiles {
        ClawContactProfileLearner.shared.refreshIfNeeded(profileID: profile.id)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .clawVoiceCallRequested)) { _ in
      selectedTab = .assistant
    }
    .onReceive(NotificationCenter.default.publisher(for: .clawVoiceInputRequested)) { _ in
      selectedTab = .assistant
    }
  }
}

private enum ClawAssistantTab: Hashable {
  case assistant, today, people, memory, settings
}

/// A single in-app settings destination; raw input records live below Privacy
/// rather than competing with Assistant/Today/People/Memory for a tab.
private struct ClawSettingsHubView: View {
  @ObservedObject var viewModel: ClawTalkViewModel
  @State private var cannotOpenKeyboardSettings = false

  var body: some View {
    NavigationView {
      List {
        Section("键盘与输入") {
          Button {
            guard let url = URL(string: HamsterConstants.appURLForKeyboardSettings) else {
              cannotOpenKeyboardSettings = true
              return
            }
            UIApplication.shared.open(url, options: [:]) { success in
              if !success {
                DispatchQueue.main.async { cannotOpenKeyboardSettings = true }
              }
            }
          } label: {
            Label("键盘、输入方案与外观", systemImage: "keyboard")
          }
        }

        Section("数据与隐私") {
          NavigationLink {
            ClawTalkRootView(viewModel: viewModel)
          } label: {
            Label("输入记录、剪贴板与隐私设置", systemImage: "lock.doc")
          }
          Text("长期记忆、人物档案与技能分别在「记忆」和「人物」页管理。")
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        Section("同步、备份与高级设置") {
          Button {
            guard let url = URL(string: HamsterConstants.appURLForMain) else {
              cannotOpenKeyboardSettings = true
              return
            }
            UIApplication.shared.open(url, options: [:]) { success in
              if !success {
                DispatchQueue.main.async { cannotOpenKeyboardSettings = true }
              }
            }
          } label: {
            Label("查看原有完整设置", systemImage: "slider.horizontal.3")
          }
          Text("iCloud、词库、RIME 部署、外观与诊断功能保留在原有设置中，迁移期间不会丢失入口。")
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        Section("使用说明") {
          Text("语音识别由 CLAW 主程序完成，第三方键盘不直接录音。")
            .font(.footnote)
            .foregroundColor(.secondary)
        }
      }
      .navigationTitle("设置")
      .alert("无法打开键盘设置", isPresented: $cannotOpenKeyboardSettings) {
        Button("知道了", role: .cancel) {}
      } message: {
        Text("请返回 CLAW 主程序的设置页面，检查键盘入口是否可用。")
      }
    }
  }
}

enum ClawComposerTrailingAction: Equatable {
  case more, send
}

enum ClawComposerPresentation {
  static func trailingAction(for text: String) -> ClawComposerTrailingAction {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .more : .send
  }

  /// One-shot dictation is a draft, not an instruction to send a message.
  /// Preserve unsent text and keep a user review step before submission.
  static func appendDictation(_ recognized: String, to currentDraft: String) -> String {
    let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return currentDraft }
    guard !currentDraft.isEmpty else { return text }
    return currentDraft + "\n" + text
  }
}


/// Ephemeral, per-conversation draft isolation. Never store unsent messages
/// in cross-process UserDefaults or mix them between the global and person tabs.
enum ClawDraftContext {
  static func key(_ personID: UUID?) -> String {
    personID?.uuidString ?? "global"
  }

  static func switching(
    currentText: String,
    from previousPerson: UUID?,
    to nextPerson: UUID?,
    cache: inout [String: String]
  ) -> String {
    let oldKey = key(previousPerson)
    let newKey = key(nextPerson)
    guard oldKey != newKey else { return currentText }
    cache[oldKey] = currentText
    return cache[newKey] ?? ""
  }
}

private struct ClawScreenshotReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  let preview: ClawScreenshotIngestionResult
  let profiles: [HeartTargetProfile]
  let onConfirm: (UUID, [ClawConversationMessage]) throws -> Int
  let onUseText: (String) -> Void
  @State private var selectedProfileID: UUID?
  @State private var reviewedMessages: [ClawConversationMessage]
  @State private var errorText: String?

  init(
    preview: ClawScreenshotIngestionResult,
    profiles: [HeartTargetProfile],
    onConfirm: @escaping (UUID, [ClawConversationMessage]) throws -> Int,
    onUseText: @escaping (String) -> Void
  ) {
    self.preview = preview
    self.profiles = profiles
    self.onConfirm = onConfirm
    self.onUseText = onUseText
    _selectedProfileID = State(initialValue: preview.profile?.id)
    _reviewedMessages = State(initialValue: preview.messages)
  }

  private var canConfirm: Bool {
    selectedProfileID != nil && !reviewedMessages.isEmpty &&
      reviewedMessages.allSatisfy {
        $0.speaker != .unknown &&
        !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  var body: some View {
    NavigationView {
      Form {
        Section {
          Menu {
            ForEach(profiles) { profile in
              Button(profile.displayName) { selectedProfileID = profile.id }
            }
          } label: {
            HStack {
              Text("聊天对象")
              Spacer()
              Text(profiles.first(where: { $0.id == selectedProfileID })?.displayName ?? "请手动选择")
                .foregroundColor(.secondary)
            }
          }
          if profiles.isEmpty {
            Text("还没有人物档案。请先在「人物」页新建，再导入截图。")
              .font(.caption).foregroundColor(.secondary)
          }
        } header: {
          Text("确认归属")
        } footer: {
          Text("不会依据截图标题自动创建人物；内容只归档到你确认的对象。")
        }

        Section("逐条校对") {
          if reviewedMessages.isEmpty {
            Text("未识别出独立聊天气泡，可先将 OCR 原文加入草稿。")
              .font(.footnote).foregroundColor(.secondary)
          }
          ForEach($reviewedMessages) { $message in
            VStack(alignment: .leading, spacing: 8) {
              Picker("发言者", selection: $message.speaker) {
                Text("请确认").tag(ClawConversationSpeaker.unknown)
                Text("我").tag(ClawConversationSpeaker.me)
                Text("对方").tag(ClawConversationSpeaker.other)
              }
              .pickerStyle(.segmented)
              TextEditor(text: $message.content)
                .frame(minHeight: 56, maxHeight: 108)
                .accessibilityLabel("校对消息文字")
            }
            .padding(.vertical, 4)
          }
        }

        Section {
          Button("仅把 OCR 原文加入聊天草稿") {
            onUseText(preview.rawText)
            dismiss()
          }
          .disabled(preview.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
          Text("此操作不会创建联系人、任务或长期记忆，也不会保存截图原图。")
        }
      }
      .navigationTitle("核对聊天截图")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("确认归档") {
            guard let id = selectedProfileID else { return }
            do {
              _ = try onConfirm(id, reviewedMessages)
              dismiss()
            } catch {
              errorText = error.localizedDescription
            }
          }
          .disabled(!canConfirm)
        }
      }
      .alert("无法归档", isPresented: Binding(
        get: { errorText != nil },
        set: { if !$0 { errorText = nil } }
      )) {
        Button("知道了", role: .cancel) { errorText = nil }
      } message: {
        Text(errorText ?? "")
      }
    }
  }
}

private struct ClawAssistantChatView: View {
  @ObservedObject private var chat = ClawChatService.shared
  @State private var input = ""
  @State private var draftsByPerson: [String: String] = [:]
  @State private var draftPersonID = HeartTargetService.shared.selectedProfile?.id
  @State private var recording = false
  @State private var callActive = false
  @State private var callListening = false
  @State private var voiceHint = ""
  @State private var voiceMode = ClawVoiceInputService.shared.languageMode
  @State private var selectedProfileName = HeartTargetService.shared.selectedProfile?.displayName
  @State private var searchText = ""
  @State private var showingSearch = false
  @State private var showingNewConversationConfirmation = false
  @State private var showingPhotoAttachment = false
  @State private var showingFileAttachment = false
  @State private var attachmentStatus = ""
  @State private var pendingScreenshotReview: ClawScreenshotIngestionResult?
  @State private var showingScreenshotReview = false
  @State private var quickPrompts = ClawQuickPromptStore(
    defaults: UserDefaults(suiteName: HamsterConstants.appGroupName) ?? .standard
  ).prompts
  @State private var voiceGesture = ClawVoiceGestureState()
  @State private var discardVoiceResult = false
  @State private var composerHeight: CGFloat = 56
  @State private var showingVoiceLanguages = false
  @State private var holdVoiceRequestID = UUID()
  @State private var activeHoldRecognitionID: UUID?
  @State private var oneShotRequestID = UUID()
  @State private var oneShotFinalizing = false
  @State private var voiceAuthorizationRequestID = UUID()
  @State private var keyboardDictationID: UUID?
  @State private var keyboardDictationFinalizing = false
  @State private var completedKeyboardDictationText: String?

  private var displayedMessages: [ClawChatMessage] {
    ClawConversationPresentation.search(chat.messages, query: searchText)
  }

  var body: some View {
    VStack(spacing: 0) {
      contextHeader
      if showingSearch {
        TextField("搜索当前对话", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
      }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            if chat.messages.isEmpty {
              emptyAssistant
            }
            ForEach(ClawConversationPresentation.group(displayedMessages)) { section in
              Text(section.day.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .id(section.day)
              ForEach(section.messages) { message in
                assistantBubble(message)
                  .id(message.id)
              }
            }
            if chat.isSending {
              HStack {
                ProgressView()
                Text("CLAW 正在思考…").font(.subheadline).foregroundColor(.secondary)
                Spacer()
              }
              .padding(.horizontal)
            }
          }
          .padding(.vertical, 12)
        }
        .onChange(of: chat.messages.count) { _ in
          if let id = chat.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
        }
        .overlay(alignment: .bottomTrailing) {
          if chat.messages.count > 5, let latest = chat.messages.last?.id {
            Button { withAnimation { proxy.scrollTo(latest, anchor: .bottom) } } label: {
              Image(systemName: "arrow.down.circle.fill").font(.title2)
            }
            .padding(10)
          }
        }
        .overlay(alignment: .bottom) {
          if !voiceHint.isEmpty || !attachmentStatus.isEmpty {
            Text(!voiceHint.isEmpty ? voiceHint : attachmentStatus)
              .font(.caption)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(.ultraThinMaterial, in: Capsule())
              .padding(.bottom, 10)
              .allowsHitTesting(false)
          }
        }
      }
      Divider()
      if let id = keyboardDictationID {
        HStack(spacing: 12) {
          Image(systemName: recording ? "waveform" : "mic")
            .foregroundColor(.accentColor)
          Text(keyboardDictationFinalizing ? "正在完成语音转文字…" : "键盘语音输入：请说话")
            .font(.subheadline)
          Spacer()
          Button("完成录音") { finishKeyboardDictation(id: id) }
            .disabled(!recording || keyboardDictationFinalizing)
          Button("取消") { cancelKeyboardDictation() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
      } else if let result = completedKeyboardDictationText {
        VStack(alignment: .leading, spacing: 6) {
          Text("识别完成，请返回原聊天 App，打开 CLAW 键盘，点话筒插入：")
            .font(.subheadline.weight(.medium))
          Text(result).font(.subheadline).lineLimit(3)
          HStack {
            Button("复制文字") { UIPasteboard.general.string = result }
            Spacer()
            Button("关闭提示") { completedKeyboardDictationText = nil }
          }
          .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
      }
      composer
    }
    .background(Color(.systemGroupedBackground))
    .onAppear {
      let profile = HeartTargetService.shared.selectedProfile
      switchDraft(to: profile?.id)
      selectedProfileName = profile?.displayName
      chat.switchContext(contactID: profile?.id)
#if DEBUG
      if let screenshotState = ClawComposerScreenshotFixture.state {
        switch screenshotState {
        case "text": input = "你好，CLAW"
        case "multiline": input = "第一行输入内容\n第二行文本\n第三行内容\n第四行内容"
        case "dark": input = "深色模式输入测试"
        default: input = ""
        }
        // Allow the actual composer, system input view, and launch overlay to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
          print("[clawComposer] screenshot ready: \(screenshotState)")
        }
      }
#endif
      let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
      // Fallback when iOS declines to open the containing app from the keyboard.
      if defaults?.bool(forKey: HamsterConstants.clawVoiceInputLaunchKey) == true ||
          ClawVoiceDictationHandoff.shared.snapshot.state == .pending {
        defaults?.set(false, forKey: HamsterConstants.clawVoiceInputLaunchKey)
        startOneShotVoiceInput()
      }
      if defaults?.bool(forKey: HamsterConstants.clawVoiceCallLaunchKey) == true {
        defaults?.set(false, forKey: HamsterConstants.clawVoiceCallLaunchKey)
        startHandsFreeCall()
      }
    }
    .onDisappear {
      cancelPendingVoice()
      stopHandsFreeCall()
    }
    .confirmationDialog("语音识别语言", isPresented: $showingVoiceLanguages, titleVisibility: .visible) {
      ForEach(ClawVoiceLanguageMode.allCases, id: \.rawValue) { mode in
        Button(mode.displayName) {
          voiceMode = mode
          ClawVoiceInputService.shared.languageMode = mode
        }
      }
    }
    .sheet(isPresented: $showingPhotoAttachment) {
      ClawAvatarPicker { image in
        showingPhotoAttachment = false
        ingestScreenshot(image)
      }
    }
    .sheet(isPresented: $showingScreenshotReview, onDismiss: {
      pendingScreenshotReview = nil
    }) {
      if let preview = pendingScreenshotReview {
        ClawScreenshotReviewSheet(
          preview: preview,
          profiles: HeartTargetService.shared.profiles,
          onConfirm: { id, reviewed in
            guard let profile = HeartTargetService.shared.profile(id: id) else {
              throw ClawScreenshotReviewError.missingPerson
            }
            let count = try ClawScreenshotIngestionService().confirmReviewed(
              messages: reviewed, for: profile
            )
            attachmentStatus = count == 0
              ? "截图消息已经归档，无需重复导入"
              : "已审核并归档 \(count) 条截图消息到 \(profile.displayName)"
            if count > 0 {
              input = [input, "已确认归档 \(count) 条截图消息，请结合这些内容回答。"]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            }
            return count
          },
          onUseText: { text in
            input = [input, text].filter { !$0.isEmpty }.joined(separator: "\n")
            attachmentStatus = "截图文字已加入草稿，未写入长期记忆"
          }
        )
      }
    }
    .fileImporter(isPresented: $showingFileAttachment, allowedContentTypes: [.plainText, .text, .pdf], allowsMultipleSelection: false) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if let text = try? String(contentsOf: url), !text.isEmpty {
        input = [input, "文件：\(url.lastPathComponent)\n\(String(text.prefix(8_000)))"].filter { !$0.isEmpty }.joined(separator: "\n")
      } else {
        attachmentStatus = "无法读取这个文件"
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .clawVoiceCallRequested)) { _ in
      startHandsFreeCall()
    }
    .onReceive(NotificationCenter.default.publisher(for: .clawVoiceInputRequested)) { _ in
      UserDefaults(suiteName: HamsterConstants.appGroupName)?
        .set(false, forKey: HamsterConstants.clawVoiceInputLaunchKey)
      startOneShotVoiceInput()
    }
    .onReceive(NotificationCenter.default.publisher(for: .heartTargetProfilesDidChange)) { _ in
      let profile = HeartTargetService.shared.selectedProfile
      switchDraft(to: profile?.id)
      selectedProfileName = profile?.displayName
      chat.switchContext(contactID: profile?.id)
    }
    .onChange(of: chat.isSending) { sending in
      if !sending { scheduleHandsFreeResume() }
    }
    .onChange(of: chat.isSpeaking) { speaking in
      if speaking {
        // Never let STT listen to CLAW's own TTS output.
        if callListening {
          ClawVoiceInputService.shared.stop()
          callListening = false
        }
      } else {
        resumeHandsFreeIfIdle()
      }
    }
  }

  private var contextHeader: some View {
    HStack(spacing: 8) {
      Image(systemName: "brain.head.profile").foregroundColor(.accentColor)
      VStack(alignment: .leading, spacing: 1) {
        Text("CLAW 私人助手").font(.headline)
        Menu {
          Button {
            HeartTargetService.shared.clearSelection()
          } label: {
            if HeartTargetService.shared.selectedProfile == nil {
              Label("全局模式", systemImage: "checkmark")
            } else {
              Text("全局模式")
            }
          }
          ForEach(HeartTargetService.shared.profiles) { profile in
            Button {
              HeartTargetService.shared.select(id: profile.id)
            } label: {
              if HeartTargetService.shared.selectedProfile?.id == profile.id {
                Label(profile.displayName, systemImage: "checkmark")
              } else {
                Text(profile.displayName)
              }
            }
          }
        } label: {
          HStack(spacing: 3) {
            Text(selectedProfileName.map { "当前对象：\($0)" } ?? "全局记忆")
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .semibold))
          }
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
        }
      }
      Spacer()
      Button { showingSearch.toggle(); if !showingSearch { searchText = "" } } label: {
        Image(systemName: showingSearch ? "xmark.circle.fill" : "magnifyingglass")
      }
      .accessibilityLabel(showingSearch ? "关闭对话搜索" : "搜索当前对话")
      if chat.isSending {
        Button("停止") { chat.stopGenerating() }.font(.caption.weight(.semibold)).foregroundColor(.red)
      }
      Menu {
        if !chat.isSending && chat.messages.contains(where: { $0.role == "assistant" && !$0.excludeFromContext }) {
          Button { chat.regenerateLastResponse() } label: {
            Label("重新生成回复", systemImage: "arrow.clockwise")
          }
        }
        Button {
          if chat.messages.isEmpty { chat.clearHistory() }
          else { showingNewConversationConfirmation = true }
        } label: {
          Label("新对话", systemImage: "square.and.pencil")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .frame(minWidth: 40, minHeight: 40)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("对话选项")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color(.secondarySystemGroupedBackground))
    .confirmationDialog("开启新对话？", isPresented: $showingNewConversationConfirmation, titleVisibility: .visible) {
      Button("清空当前对话", role: .destructive) { chat.clearHistory() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("当前会话的聊天历史会被清空，人物档案和长期记忆不会删除。")
    }
  }

  private var emptyAssistant: some View {
    VStack(spacing: 12) {
      Image(systemName: "sparkles").font(.system(size: 34)).foregroundColor(.accentColor)
      Text("我是 CLAW").font(.title3.weight(.semibold))
      Text("可以直接问我人物、最近聊过的事情、未完成事项，或者让我帮你规划下一步。")
        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(quickPrompts, id: \.self) { quickAsk($0) }
        }
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 36)
  }

  private func quickAsk(_ text: String) -> some View {
    Button(text) { send(text) }
      .buttonStyle(.bordered)
      .font(.caption)
  }

  private func assistantBubble(_ message: ClawChatMessage) -> some View {
    HStack {
      if message.role == "user" { Spacer(minLength: 44) }
      VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 3) {
        Text(message.content)
          .font(.body)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(message.role == "user" ? Color.accentColor : Color(.secondarySystemGroupedBackground))
          .foregroundColor(message.role == "user" ? .white : .primary)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .contextMenu {
            Button("复制") { UIPasteboard.general.string = message.content }
            if message.role == "assistant" {
              Button("朗读") { chat.speak(message.content) }
            }
          }
        if let trace = message.trace {
          Text("\(trace.provider) · \(trace.model)\(trace.regenerated ? " · 重生成" : "")")
            .font(.system(size: 9)).foregroundColor(.secondary)
        }
      }
      if message.role != "user" { Spacer(minLength: 44) }
    }
    .padding(.horizontal, 12)
  }

  private var composer: some View {
    ClawChatComposer(
      text: $input,
      isSending: chat.isSending,
      voiceActive: recording,
      voiceWillCancel: voiceGesture.willCancel,
      onSend: { send($0) },
      onAction: { action in
        switch action {
        case .photo: showingPhotoAttachment = true
        case .file: showingFileAttachment = true
        case .clipboard: attachClipboard()
        case .call:
          if callActive { stopHandsFreeCall() } else { startHandsFreeCall() }
        case .language: showingVoiceLanguages = true
        }
      },
      onVoiceBegin: { beginHoldVoice() },
      onVoiceMove: { vertical in
        voiceGesture.update(verticalTranslation: vertical)
      },
      onVoiceEnd: { systemCancelled in finishHoldVoice(systemCancelled: systemCancelled) },
      onHeightChange: { height in
        if abs(composerHeight - height) > 0.5 { composerHeight = height }
      }
    )
    .frame(height: composerHeight)
  }

  private func switchDraft(to personID: UUID?) {
    input = ClawDraftContext.switching(
      currentText: input, from: draftPersonID, to: personID, cache: &draftsByPerson
    )
    draftPersonID = personID
  }

  private func send(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    input = ""
    // A sent draft must not be restored when switching back to this person.
    draftsByPerson[ClawDraftContext.key(draftPersonID)] = ""
    chat.send(trimmed)
  }

  private func toggleVoice() {
    if callActive { stopHandsFreeCall() }
    guard !oneShotFinalizing else { return }
    if recording {
      if let id = keyboardDictationID {
        finishKeyboardDictation(id: id)
        return
      }
      // Do not invalidate the request here: Speech delivers the transcript
      // asynchronously *after* stop/endAudio, not while the mic is running.
      oneShotFinalizing = true
      let requestID = oneShotRequestID
      ClawVoiceInputService.shared.stop()
      recording = false
      endLiveActivity("语音识别完成")
      voiceHint = "正在完成识别…"
      DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
        guard oneShotRequestID == requestID, oneShotFinalizing else { return }
        oneShotRequestID = UUID()
        oneShotFinalizing = false
        voiceHint = "语音识别超时，请重试"
      }
      return
    }
    let requestID = UUID()
    oneShotRequestID = requestID
    withVoiceAuthorization {
      guard oneShotRequestID == requestID else { return }
      recording = true
      startLiveActivity(kind: "recording", detail: "正在语音输入")
      voiceHint = "正在听…点停止结束"
      ClawVoiceInputService.shared.start { result in
        DispatchQueue.main.async {
          guard oneShotRequestID == requestID else { return }
          oneShotRequestID = UUID()
          oneShotFinalizing = false
          recording = false
          endLiveActivity("语音识别完成")
          if let keyboardID = keyboardDictationID {
            keyboardDictationID = nil
            keyboardDictationFinalizing = false
            switch result {
            case .success(let text):
              if ClawVoiceDictationHandoff.shared.complete(id: keyboardID, text: text) {
                completedKeyboardDictationText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                voiceHint = "已保存语音文字，请返回聊天点击 CLAW 键盘话筒插入"
              } else {
                _ = ClawVoiceDictationHandoff.shared.fail(id: keyboardID, reason: "没有识别到文字")
                voiceHint = "没有识别到文字，请重试"
              }
            case .failure(let error):
              _ = ClawVoiceDictationHandoff.shared.fail(id: keyboardID, reason: error.localizedDescription)
              voiceHint = "语音识别失败：\(error.localizedDescription)"
            }
            return
          }
          switch result {
          case .success(let text):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
              voiceHint = "没有识别到文字，请重试"
            } else {
              input = ClawComposerPresentation.appendDictation(cleaned, to: input)
              voiceHint = "已转成文字，可检查或编辑后发送"
            }
          case .failure(let error):
            voiceHint = "语音识别失败：\(error.localizedDescription)"
          }
        }
      }
    }
  }

  private func beginHoldVoice() {
    if callActive { stopHandsFreeCall() }
    guard !voiceGesture.isRecording, !recording else { return }
    voiceGesture.begin()
    discardVoiceResult = false
    voiceHint = ""
    let requestID = UUID()
    holdVoiceRequestID = requestID
    withVoiceAuthorization {
      // Authorization can complete after the user has released the gesture.
      guard holdVoiceRequestID == requestID, voiceGesture.isRecording else { return }
      let recognitionID = UUID()
      activeHoldRecognitionID = recognitionID
      recording = true
      startLiveActivity(kind: "recording", detail: "按住说话")
      ClawVoiceInputService.shared.start { result in
        DispatchQueue.main.async {
          guard activeHoldRecognitionID == recognitionID else { return }
          activeHoldRecognitionID = nil
          recording = false
          endLiveActivity("语音识别完成")
          guard !discardVoiceResult else { discardVoiceResult = false; voiceHint = ""; return }
          switch result {
          case .success(let text): voiceHint = ""; send(text)
          case .failure(let error): voiceHint = "语音识别失败：\(error.localizedDescription)"
          }
        }
      }
    }
  }

  private func finishHoldVoice(systemCancelled: Bool = false) {
    guard voiceGesture.isRecording else { return }
    let outcome = voiceGesture.finish()
    holdVoiceRequestID = UUID()
    discardVoiceResult = systemCancelled || outcome == .cancel
    if discardVoiceResult { activeHoldRecognitionID = nil }
    if recording { ClawVoiceInputService.shared.stop() }
    recording = false
    endLiveActivity(discardVoiceResult ? "录音已取消" : "语音识别完成")
    voiceHint = discardVoiceResult ? "已取消" : "正在完成识别…"
  }

  private func cancelPendingVoice() {
    if let keyboardID = keyboardDictationID {
      ClawVoiceDictationHandoff.shared.cancel(id: keyboardID)
      keyboardDictationID = nil
    }
    keyboardDictationFinalizing = false
    oneShotFinalizing = false
    voiceAuthorizationRequestID = UUID()
    holdVoiceRequestID = UUID()
    oneShotRequestID = UUID()
    activeHoldRecognitionID = nil
    discardVoiceResult = true
    if voiceGesture.isRecording { _ = voiceGesture.finish() }
    if recording { ClawVoiceInputService.shared.stop() }
    recording = false
    voiceHint = ""
    endLiveActivity("录音已结束")
  }

  private func attachClipboard() {
    if let image = UIPasteboard.general.image { ingestScreenshot(image); return }
    if let text = UIPasteboard.general.string, !text.isEmpty {
      input = [input, text].filter { !$0.isEmpty }.joined(separator: "\n")
      attachmentStatus = "已附加剪贴板文字"
    } else {
      attachmentStatus = "剪贴板里没有可附加的文字或图片"
    }
  }

  private func ingestScreenshot(_ image: UIImage) {
    attachmentStatus = "正在本地识别截图…"
    // A stable, local-only digest permits idempotent re-import without
    // persisting the underlying screenshot (or paying for a new framework).
    let digestSource = image.jpegData(compressionQuality: 0.8).map { data -> String in
      "screenshot-digest:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    VisionOCRService.shared.recognizeLines(in: image) { result in
      DispatchQueue.main.async {
        switch result {
        case .failure(let error):
          attachmentStatus = "截图识别失败：\(error.localizedDescription)"
        case .success(let lines):
          do {
            // OCR is a preview only. No new person, conversation, task, memory
            // or evidence file is created until the user explicitly confirms.
            let preview = try ClawScreenshotIngestionService().ingest(
              lines: lines,
              selectedProfile: HeartTargetService.shared.selectedProfile,
              sourceRef: digestSource,
              requireUserReview: true
            )
            pendingScreenshotReview = preview
            showingScreenshotReview = true
            attachmentStatus = "请核对人物、发言者与文字，再决定是否归档"
          } catch {
            attachmentStatus = "截图识别失败：\(error.localizedDescription)"
          }
        }
      }
    }
  }

  /// 从键盘话筒按钮跳转进来时只做一次听写，不进入连续通话。
  private func startOneShotVoiceInput() {
    if callActive { stopHandsFreeCall() }
    guard !recording, !oneShotFinalizing else { return }
    let handoff = ClawVoiceDictationHandoff.shared
    if handoff.snapshot.state == .pending {
      keyboardDictationID = handoff.snapshot.id
      completedKeyboardDictationText = nil
      keyboardDictationFinalizing = false
    }
    toggleVoice()
  }

  private func finishKeyboardDictation(id: UUID) {
    guard keyboardDictationID == id, recording, !keyboardDictationFinalizing else { return }
    keyboardDictationFinalizing = true
    oneShotFinalizing = true
    ClawVoiceInputService.shared.stop()
    recording = false
    voiceHint = "正在完成语音识别…"
    // Speech usually returns an isFinal callback after endAudio. Avoid a stuck pending result.
    DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
      guard keyboardDictationID == id, keyboardDictationFinalizing else { return }
      oneShotRequestID = UUID()
      oneShotFinalizing = false
      _ = ClawVoiceDictationHandoff.shared.fail(id: id, reason: "语音识别未返回结果，请重试")
      keyboardDictationID = nil
      keyboardDictationFinalizing = false
      voiceHint = "语音识别未返回结果，请重试"
    }
  }

  private func cancelKeyboardDictation() {
    guard let id = keyboardDictationID else { return }
    oneShotRequestID = UUID()
    voiceAuthorizationRequestID = UUID()
    ClawVoiceDictationHandoff.shared.cancel(id: id)
    keyboardDictationID = nil
    keyboardDictationFinalizing = false
    oneShotFinalizing = false
    if recording { ClawVoiceInputService.shared.stop() }
    recording = false
    voiceHint = "已取消键盘语音输入"
  }

  private func startHandsFreeCall() {
    guard !callActive else { return }
    withVoiceAuthorization {
      callActive = true
      startLiveActivity(kind: "call", detail: "CLAW 通话中")
      recording = false
      chat.stopSpeaking()
      voiceHint = "通话模式 · 正在听…"
      beginHandsFreeListening()
    }
  }

  private func stopHandsFreeCall() {
    guard callActive || callListening else { return }
    callActive = false
    callListening = false
    ClawVoiceInputService.shared.stop()
    chat.stopSpeaking()
    voiceHint = ""
    endLiveActivity("通话已结束")
  }

  private func startLiveActivity(kind: String, detail: String) {
    if #available(iOS 16.1, *) { Task { await ClawLiveActivityManager.shared.start(kind: kind, detail: detail) } }
  }

  private func endLiveActivity(_ detail: String) {
    if #available(iOS 16.1, *) { Task { await ClawLiveActivityManager.shared.end(detail: detail) } }
  }

  private func beginHandsFreeListening() {
    guard callActive, !callListening, !chat.isSending, !chat.isSpeaking else { return }
    callListening = true
    voiceHint = "通话模式 · 正在听…"
    ClawVoiceInputService.shared.startStreaming(
      onPartial: { text in
        DispatchQueue.main.async {
          guard callActive else { return }
          voiceHint = text.isEmpty ? "通话模式 · 正在听…" : "你：\(text)"
        }
      },
      onSegment: { text in
        DispatchQueue.main.async {
          guard callActive else { return }
          callListening = false
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            resumeHandsFreeIfIdle()
            return
          }
          voiceHint = "CLAW 正在回答…"
          chat.send(trimmed, forceSpeak: true)
        }
      },
      onError: { error in
        DispatchQueue.main.async {
          callListening = false
          if callActive {
            voiceHint = "通话中断：\(error.localizedDescription)"
            callActive = false
          }
        }
      }
    )
  }

  private func resumeHandsFreeIfIdle() {
    guard callActive, !callListening, !chat.isSending, !chat.isSpeaking else { return }
    beginHandsFreeListening()
  }

  private func scheduleHandsFreeResume() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      resumeHandsFreeIfIdle()
    }
  }

  private func withVoiceAuthorization(_ action: @escaping () -> Void) {
    let requestID = UUID()
    voiceAuthorizationRequestID = requestID
    switch ClawVoiceInputService.shared.authorizationStatus {
    case .authorized:
      if voiceAuthorizationRequestID == requestID { action() }
    case .denied:
      voiceHint = "请在系统设置中允许 CLAW 使用麦克风和语音识别"
      failKeyboardDictationAuthorization()
    case .undetermined:
      voiceHint = "正在请求语音权限…"
      ClawVoiceInputService.shared.requestAuthorization { granted in
        DispatchQueue.main.async {
          guard voiceAuthorizationRequestID == requestID else { return }
          if granted {
            action()
          } else {
            voiceHint = "未获得麦克风/语音识别权限"
            failKeyboardDictationAuthorization()
          }
        }
      }
    }
  }

  private func failKeyboardDictationAuthorization() {
    guard let id = keyboardDictationID else { return }
    _ = ClawVoiceDictationHandoff.shared.fail(id: id, reason: "请在设置中允许 CLAW 使用麦克风和语音识别")
    keyboardDictationID = nil
    keyboardDictationFinalizing = false
  }
}

private struct ClawSecretaryTodayView: View {
  @State private var tasks: [ClawSecretaryTask] = []
  @State private var memories: [ClawMemoryItem] = []
  @State private var suggestions: [ClawSecretarySuggestion] = []
  @State private var briefing = ""
  @State private var showingNewTask = false
  @AppStorage(
    "claw.secretary.reminder-strategy",
    store: UserDefaults(suiteName: HamsterConstants.appGroupName)
  ) private var reminderStrategyRaw = ClawReminderStrategy.proactive.rawValue

  private var groupedTasks: [ClawTodayTaskGroup: [ClawSecretaryTask]] {
    ClawTodayTaskGrouping.group(tasks)
  }

  var body: some View {
    NavigationView {
      List {
        Section {
          HStack {
            Label("\(tasks.count) 个未完成事项", systemImage: "checklist")
            Spacer()
            Text("Memory \(memories.count)").font(.caption).foregroundColor(.secondary)
          }
          if tasks.isEmpty {
            Text("暂时没有结构化待办。CLAW 会逐步从明确的承诺、截止时间和等待回复中提取事项。")
              .font(.subheadline).foregroundColor(.secondary)
          }
        } header: {
          Text("秘书摘要")
        }
        Section {
          Text(briefing)
            .font(.subheadline)
            .textSelection(.enabled)
        } header: {
          Text("今日 Briefing")
        } footer: {
          Text("由本机任务/承诺/等待状态生成；即使未配置云端模型也可用。")
        }
        Section("提醒策略") {
          Picker("提醒方式", selection: $reminderStrategyRaw) {
            ForEach(ClawReminderStrategy.allCases) { strategy in
              Text(strategy.title).tag(strategy.rawValue)
            }
          }
        }
        if !suggestions.isEmpty {
          Section {
            ForEach(suggestions.prefix(12)) { suggestion in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Image(systemName: suggestion.urgency >= .high ? "exclamationmark.circle.fill" : "clock.badge.exclamationmark")
                    .foregroundColor(suggestion.urgency >= .high ? .orange : .accentColor)
                  Text(suggestion.title).font(.body)
                  Spacer()
                }
                Text(suggestion.detail).font(.caption).foregroundColor(.secondary)
                HStack {
                  Button("完成") {
                    _ = ClawProactiveSecretaryService.shared.complete(taskID: suggestion.taskID)
                    reload()
                  }
                  .buttonStyle(.borderedProminent)
                  Button("明天再提醒") {
                    _ = ClawProactiveSecretaryService.shared.snooze(taskID: suggestion.taskID, hours: 24)
                    reload()
                  }
                  .buttonStyle(.bordered)
                }
                .font(.caption)
              }
              .padding(.vertical, 2)
            }
          } header: {
            Text("CLAW 主动提醒")
          } footer: {
            Text("只有临近截止、已逾期或长时间等待的事项会主动提醒；低优先级内容留在今日列表，不频繁打扰。")
          }
        }
        ForEach(ClawTodayTaskGroup.allCases) { group in
          if let grouped = groupedTasks[group], !grouped.isEmpty {
            Section(group.title) {
              ForEach(grouped) { task in
                NavigationLink {
                  ClawTaskDetailView(task: task, onChange: reload)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    HStack {
                      Text(task.title).font(.body)
                      Spacer()
                      Text(task.kind.rawValue).font(.caption2).foregroundColor(.secondary)
                    }
                    if let due = task.dueAt {
                      Text(due, style: .relative).font(.caption).foregroundColor(group == .overdue ? .red : .orange)
                    }
                    if let details = task.details, !details.isEmpty {
                      Text(details).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                  }
                }
                .swipeActions(edge: .trailing) {
                  Button("完成") {
                    _ = ClawProactiveSecretaryService.shared.complete(taskID: task.id)
                    reload()
                  }
                  .tint(.green)
                }
              }
            }
          }
        }
      }
      .navigationTitle("今日秘书")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showingNewTask = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("新建待办")
        }
      }
      .sheet(isPresented: $showingNewTask) {
        NavigationView {
          ClawTaskEditorView {
            showingNewTask = false
            reload()
          }
        }
      }
      .onAppear(perform: reload)
      .refreshable { reload() }
    }
  }

  private func reload() {
    tasks = (try? ClawMemoryStore.shared.tasks(status: .open, limit: 100)) ?? []
    memories = (try? ClawMemoryStore.shared.memories(limit: 500)) ?? []
    suggestions = ClawProactiveSecretaryService.shared.suggestions()
    briefing = ClawProactiveSecretaryService.shared.briefing()
    ClawProactiveSecretaryService.shared.refreshLocalNotifications()
  }
}

private struct ClawTaskEditorView: View {
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var details = ""
  @State private var kind = ClawTaskKind.task
  @State private var hasDueDate = false
  @State private var dueAt = Date().addingTimeInterval(3600)

  private let kinds: [ClawTaskKind] = [.task, .commitment, .waitingFor, .deadline, .nextAction]

  var body: some View {
    Form {
      Section("待办") {
        TextField("要做什么？", text: $title)
        TextEditor(text: $details).frame(minHeight: 90)
        Picker("类型", selection: $kind) {
          ForEach(kinds, id: \.rawValue) { Text($0.rawValue).tag($0) }
        }
      }
      Section("时间") {
        Toggle("设置截止时间", isOn: $hasDueDate)
        if hasDueDate { DatePicker("截止", selection: $dueAt) }
      }
    }
    .clawKeyboardDismissal()
    .navigationTitle("新建待办")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          let task = ClawSecretaryTask(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            dueAt: hasDueDate ? dueAt : nil,
            sourceType: "manual"
          )
          try? DefaultMemorySDK.shared.createTask(task)
          onSaved()
          dismiss()
        }
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

private struct ClawTaskDetailView: View {
  let task: ClawSecretaryTask
  let onChange: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showingCustomSnooze = false
  @State private var customDate = Date().addingTimeInterval(3600)

  var body: some View {
    List {
      Section("事项") {
        Text(task.title)
        if let details = task.details, !details.isEmpty { Text(details).foregroundColor(.secondary) }
        HStack { Text("类型"); Spacer(); Text(task.kind.rawValue).foregroundColor(.secondary) }
        if let dueAt = task.dueAt { HStack { Text("截止"); Spacer(); Text(dueAt, style: .date); Text(dueAt, style: .time) } }
      }
      Section("操作") {
        Button("标记完成") {
          _ = ClawProactiveSecretaryService.shared.complete(taskID: task.id)
          onChange()
          dismiss()
        }
        Menu("稍后提醒") {
          Button("1 小时后") { snooze(hours: 1) }
          Button("明天") { snooze(hours: 24) }
          Button("自定义…") { showingCustomSnooze = true }
        }
      }
    }
    .navigationTitle("待办详情")
    .sheet(isPresented: $showingCustomSnooze) {
      NavigationView {
        Form { DatePicker("提醒时间", selection: $customDate, in: Date()...) }
          .navigationTitle("自定义提醒")
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { showingCustomSnooze = false } }
            ToolbarItem(placement: .confirmationAction) {
              Button("确定") {
                _ = try? ClawMemoryStore.shared.snoozeTask(id: task.id, until: customDate)
                showingCustomSnooze = false
                onChange()
              }
            }
          }
      }
    }
  }

  private func snooze(hours: Int) {
    _ = ClawProactiveSecretaryService.shared.snooze(taskID: task.id, hours: hours)
    onChange()
  }
}

private struct ClawPeopleView: View {
  let onUseProfile: () -> Void
  @State private var profiles = HeartTargetService.shared.profiles
  @State private var selectedID = HeartTargetService.shared.selectedProfile?.id
  @State private var searchText = ""
  @State private var editingProfile: HeartTargetProfile?
  @State private var filter = ClawPeopleFilter.all
  @State private var pendingDelete: HeartTargetProfile?
  @State private var mergingProfile: HeartTargetProfile?

  private var filteredProfiles: [HeartTargetProfile] {
    ClawPeoplePresentation.filtered(profiles, query: searchText, filter: filter)
  }

  var body: some View {
    NavigationView {
      List {
        Section {
          Picker("筛选", selection: $filter) {
            ForEach(ClawPeopleFilter.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)
        }

        Section {
          Button {
            HeartTargetService.shared.clearSelection()
            selectedID = nil
          } label: {
            HStack {
              Label("全局模式", systemImage: "person.crop.circle.dashed")
              Spacer()
              if selectedID == nil { Image(systemName: "checkmark") }
            }
          }
        } footer: {
          Text("全局模式只使用你的个人长期记忆，不会把多个联系人混在一起。")
        }

        Section {
          if profiles.isEmpty {
            Text("还没有人物档案。点右上角 + 创建，截图归档和帮你回都会使用这里的对象。")
              .foregroundColor(.secondary)
          }
          ForEach(filteredProfiles) { profile in
            HStack(spacing: 8) {
              NavigationLink {
                ClawContactDetailView(profile: profile)
              } label: {
                HStack(spacing: 10) {
                  Group {
                    if let image = profile.avatarImage { Image(uiImage: image).resizable() }
                    else { Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.secondary) }
                  }
                  .frame(width: 36, height: 36).clipShape(Circle())
                  VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                      Text(profile.displayName)
                      if profile.isGroup {
                        Text("群").font(.caption2).padding(.horizontal, 4).background(Color.blue.opacity(0.12)).clipShape(Capsule())
                      }
                      if profile.autoCreated {
                        Text("自动识别").font(.caption2).padding(.horizontal, 4).background(Color.orange.opacity(0.12)).clipShape(Capsule())
                      }
                    }
                    Text(profile.relationship.isEmpty ? (profile.bio.isEmpty ? "尚未形成画像" : profile.bio) : profile.relationship)
                      .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    if let lastSeenAt = profile.lastSeenAt {
                      Text("最近互动：\(lastSeenAt, style: .relative)")
                        .font(.caption2).foregroundColor(.secondary)
                    }
                  }
                }
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button("编辑") {
                editingProfile = profile
              }
              .tint(.blue)
              Button("删除", role: .destructive) {
                pendingDelete = profile
              }
            }
            .contextMenu {
              Button("设为当前人物") {
                HeartTargetService.shared.select(id: profile.id)
                selectedID = profile.id
                onUseProfile()
              }
              Button("合并到…") { mergingProfile = profile }
              Button("拆分副本") {
                editingProfile = ClawPeopleWorkflowService.shared.splitCopy(of: profile)
              }
            }
          }
        } header: {
          Text("聊天对象")
        }
      }
      .navigationTitle("人物")
      .searchable(text: $searchText, prompt: "搜索姓名、别名或关系")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            editingProfile = HeartTargetProfile()
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("新建人物档案")
        }
      }
      .sheet(item: $editingProfile) { profile in
        NavigationView {
          ClawContactEditorView(profile: profile)
        }
      }
      .alert(item: $pendingDelete) { profile in
        let hasRecords = (try? ClawMemoryStore.shared.hasContactReferences(id: profile.id)) ?? true
        return Alert(
          title: Text(hasRecords ? "无法直接删除 \(profile.displayName)" : "删除 \(profile.displayName)？"),
          message: Text(hasRecords
            ? "该人物关联着私密聊天、记忆或任务。为防止这些资料暴露为全局记忆，暂不删除。可先将人物合并到正确对象，或在数据管理中处理关联资料。"
            : "该人物没有关联记录。删除档案不会影响其他人物。"),
          primaryButton: .default(Text(hasRecords ? "知道了" : "确认删除")) {
            if !hasRecords {
              _ = ClawPeopleWorkflowService.shared.deleteProfilePreservingRecords(profile.id)
            }
          },
          secondaryButton: .cancel()
        )
      }
      .confirmationDialog(
        "将 \(mergingProfile?.displayName ?? "此人物") 合并到",
        isPresented: Binding(
          get: { mergingProfile != nil },
          set: { if !$0 { mergingProfile = nil } }
        ),
        titleVisibility: .visible
      ) {
        if let source = mergingProfile {
          ForEach(profiles.filter { $0.id != source.id }) { destination in
            Button(destination.displayName) {
              ClawPeopleWorkflowService.shared.merge(sourceID: source.id, into: destination.id)
              mergingProfile = nil
            }
          }
        }
        Button("取消", role: .cancel) { mergingProfile = nil }
      }
      .onReceive(NotificationCenter.default.publisher(for: .heartTargetProfilesDidChange)) { _ in
        profiles = HeartTargetService.shared.profiles
        selectedID = HeartTargetService.shared.selectedProfile?.id
      }
    }
  }
}

private struct ClawContactEditorView: View {
  @Environment(\.dismiss) private var dismiss
  private let original: HeartTargetProfile

  @State private var name: String
  @State private var relationship: String
  @State private var aliases: String
  @State private var bio: String
  @State private var isGroup: Bool
  @State private var avatarData: Data?
  @State private var showingAvatarPicker = false

  init(profile: HeartTargetProfile) {
    original = profile
    _name = State(initialValue: profile.name)
    _relationship = State(initialValue: profile.relationship)
    _aliases = State(initialValue: profile.aliases.joined(separator: "、"))
    _bio = State(initialValue: profile.bio)
    _isGroup = State(initialValue: profile.isGroup)
    _avatarData = State(initialValue: profile.avatarData)
  }

  var body: some View {
    Form {
      Section("头像") {
        Button { showingAvatarPicker = true } label: {
          HStack {
            Spacer()
            Group {
              if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image).resizable()
              } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.secondary)
              }
            }
            .scaledToFill()
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            Spacer()
          }
        }
        .buttonStyle(.plain)
      }
      Section("基本信息") {
        TextField("姓名 / 群名", text: $name)
        TextField("关系，例如朋友、客户、家人", text: $relationship)
        TextField("备注名 / 昵称，多个用逗号分隔", text: $aliases)
        Toggle("这是群聊", isOn: $isGroup)
      }
      Section {
        TextEditor(text: $bio)
          .frame(minHeight: 110)
      } header: {
        Text("你的备注")
      } footer: {
        Text("AI 自动形成的互动画像会与这里的手工备注分开保存，不会覆盖你的文字。")
      }
    }
    .clawKeyboardDismissal()
    .sheet(isPresented: $showingAvatarPicker) {
      ClawAvatarPicker { image in
        avatarData = image.jpegData(compressionQuality: 0.8)
        showingAvatarPicker = false
      }
    }
    .navigationTitle(original.name.isEmpty ? "新建人物" : "编辑人物")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("取消") { dismiss() }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("保存") {
          save()
        }
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private func save() {
    var profile = original
    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.aliases = aliases
      .components(separatedBy: CharacterSet(charactersIn: ",，、"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.isGroup = isGroup
    profile.avatarData = avatarData
    profile.autoCreated = false
    _ = HeartTargetService.shared.upsert(profile)
    dismiss()
  }
}

private struct ClawContactDetailView: View {
  let profile: HeartTargetProfile
  @State private var timeline: [ClawConversationMessage] = []
  @State private var memories: [ClawMemoryItem] = []
  @State private var tasks: [ClawSecretaryTask] = []
  @State private var isSelected = false

  var body: some View {
    List {
      Section {
        Button {
          HeartTargetService.shared.select(id: profile.id)
          isSelected = true
        } label: {
          Label(isSelected ? "当前助手人物" : "设为当前助手人物", systemImage: isSelected ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
        }
        .disabled(isSelected)
      }
      Section {
        if profile.autoCreated {
          Button("确认这个人物档案") {
            var updated = profile
            updated.autoCreated = false
            _ = HeartTargetService.shared.upsert(updated)
          }
        }
        if !profile.relationship.isEmpty {
          HStack { Text("关系"); Spacer(); Text(profile.relationship).foregroundColor(.secondary) }
        }
        if !profile.aliases.isEmpty {
          HStack {
            Text("别名")
            Spacer()
            Text(profile.aliases.joined(separator: "、"))
              .foregroundColor(.secondary)
              .multilineTextAlignment(.trailing)
          }
        }
        if !profile.bio.isEmpty { Text(profile.bio) }
        if !profile.learnedSummary.isEmpty { Text(profile.learnedSummary).foregroundColor(.secondary) }
        if profile.bio.isEmpty && profile.learnedSummary.isEmpty { Text("暂无画像").foregroundColor(.secondary) }
        if let lastSeen = profile.lastSeenAt {
          HStack { Text("最近识别"); Spacer(); Text(lastSeen, style: .relative).foregroundColor(.secondary) }
        }
      } header: {
        Text("画像")
      }
      if !memories.isEmpty {
        Section {
          ForEach(memories.prefix(20)) { item in
            VStack(alignment: .leading, spacing: 2) {
              Text(item.content)
              Text("\(item.kind.rawValue) · \(item.sourceType)").font(.caption2).foregroundColor(.secondary)
            }
          }
        } header: {
          Text("长期记忆")
        }
      }
      if !tasks.isEmpty {
        Section("未完成事项") {
          ForEach(tasks) { task in
            NavigationLink {
              ClawTaskDetailView(task: task) { reloadProfileData() }
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                if let dueAt = task.dueAt { Text(dueAt, style: .relative).font(.caption).foregroundColor(.orange) }
              }
            }
          }
        }
      }
      Section {
        if timeline.isEmpty { Text("还没有结构化聊天记录").foregroundColor(.secondary) }
        ForEach(timeline.suffix(80)) { message in
          VStack(alignment: .leading, spacing: 3) {
            Text(message.speaker == .me ? "我" : (message.senderName ?? profile.displayName))
              .font(.caption.weight(.semibold)).foregroundColor(message.speaker == .me ? .accentColor : .secondary)
            Text(message.content)
            Text(message.occurredAt, style: .time).font(.caption2).foregroundColor(.secondary)
          }
        }
      } header: {
        Text("聊天时间线")
      }
    }
    .navigationTitle(profile.displayName)
    .onAppear {
      isSelected = HeartTargetService.shared.selectedProfile?.id == profile.id
      reloadProfileData()
    }
    .onReceive(NotificationCenter.default.publisher(for: .heartTargetProfilesDidChange)) { _ in
      isSelected = HeartTargetService.shared.selectedProfile?.id == profile.id
    }
  }

  private func reloadProfileData() {
    timeline = (try? ClawMemoryStore.shared.conversation(contactID: profile.id, limit: 200)) ?? []
    memories = (try? ClawMemoryStore.shared.memories(scope: "contact", subjectID: profile.id, limit: 100)) ?? []
    tasks = ((try? ClawMemoryStore.shared.tasks(status: .open, limit: 500)) ?? [])
      .filter { $0.contactID == profile.id }
  }
}

private struct ClawAvatarPicker: UIViewControllerRepresentable {
  let onPick: (UIImage) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let onPick: (UIImage) -> Void
    init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      picker.dismiss(animated: true)
      guard let provider = results.first?.itemProvider,
            provider.canLoadObject(ofClass: UIImage.self)
      else { return }
      provider.loadObject(ofClass: UIImage.self) { [onPick] object, _ in
        guard let image = object as? UIImage else { return }
        DispatchQueue.main.async { onPick(image) }
      }
    }
  }
}

private enum MemoryCenterAnchor {
  static let skills = "memory-center-skills"
}

private struct ClawAllMemoriesView: View {
  @State private var memories: [ClawMemoryItem] = []
  @State private var profiles: [HeartTargetProfile] = []
  @State private var query = ""
  @State private var personID: UUID?
  @State private var sourceType: String?
  @State private var kind: ClawMemoryKind?
  @State private var scope: String?
  @State private var editingMemory: ClawMemoryItem?
  @State private var vaultRefreshVersion = 0
  @State private var isLoading = false
  @State private var status = ""

  private var vaultUnlocked: Bool {
    _ = vaultRefreshVersion
    return ClawPrivacyVaultService.shared.isUnlocked
  }

  private var filteredMemories: [ClawMemoryItem] {
    ClawMemoryFilter.apply(
      memories,
      query: query,
      personID: personID,
      sourceType: sourceType,
      kind: kind,
      scope: scope,
      protectedIDs: ClawPrivacyVaultService.shared.protectedMemoryIDs,
      includeProtectedContent: vaultUnlocked
    )
  }

  private var sourceTypes: [String] {
    Array(Set(memories.map(\.sourceType))).sorted()
  }

  private var scopes: [String] {
    Array(Set(memories.map(\.scope))).sorted()
  }

  var body: some View {
    List {
      Section {
        Menu {
          Button("全部人物") { personID = nil }
          ForEach(profiles) { profile in
            Button(profile.displayName) { personID = profile.id }
          }
        } label: {
          filterLabel("人物", value: profiles.first(where: { $0.id == personID })?.displayName)
        }

        Menu {
          Button("全部来源") { sourceType = nil }
          ForEach(sourceTypes, id: \.self) { source in
            Button(source) { sourceType = source }
          }
        } label: {
          filterLabel("来源", value: sourceType)
        }

        Menu {
          Button("全部类型") { kind = nil }
          ForEach(ClawMemoryKind.allCases, id: \.self) { value in
            Button(value.rawValue) { kind = value }
          }
        } label: {
          filterLabel("类型", value: kind?.rawValue)
        }

        Menu {
          Button("全部范围") { scope = nil }
          ForEach(scopes, id: \.self) { value in
            Button(value) { scope = value }
          }
        } label: {
          filterLabel("范围", value: scope)
        }
      } header: {
        Text("筛选")
      }

      Section {
        if isLoading {
          HStack {
            Spacer()
            ProgressView("正在读取全部记忆…")
            Spacer()
          }
        } else if filteredMemories.isEmpty {
          Text("没有符合条件的记忆。")
            .foregroundColor(.secondary)
        } else {
          ForEach(filteredMemories) { item in
            Button {
              open(item)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  if ClawPrivacyVaultService.shared.isProtected(item) {
                    Image(systemName: vaultUnlocked ? "lock.open.fill" : "lock.fill")
                      .font(.caption)
                      .foregroundColor(.orange)
                  }
                  Text(
                    ClawPrivacyVaultService.shared.isProtected(item) && !vaultUnlocked
                      ? "已锁定的私人记忆"
                      : item.content
                  )
                  .foregroundColor(.primary)
                }
                Text(memoryMetadata(item))
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
              Button("删除", role: .destructive) {
                _ = try? ClawMemoryStore.shared.deleteMemory(id: item.id)
                reload()
              }
              Button("归档") {
                _ = try? ClawMemoryStore.shared.setMemoryStatus(id: item.id, status: .archived)
                reload()
              }
              .tint(.orange)
            }
          }
        }
      } header: {
        Text("全部记忆 · \(filteredMemories.count) / \(memories.count)")
      } footer: {
        if !status.isEmpty { Text(status) }
      }
    }
    .navigationTitle("全部记忆")
    .searchable(text: $query, prompt: "搜索内容、来源或类型")
    .onAppear(perform: reload)
    .task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        vaultRefreshVersion &+= 1
        if let editingMemory,
           !ClawMemoryVaultAccess.canOpen(
             editingMemory,
             protectedIDs: ClawPrivacyVaultService.shared.protectedMemoryIDs,
             isUnlocked: ClawPrivacyVaultService.shared.isUnlocked
           ) {
          self.editingMemory = nil
          status = "隐私保险箱已自动锁定。"
        }
      }
    }
    .sheet(item: $editingMemory) { item in
      ClawMemoryEditorView(item: item) {
        editingMemory = nil
        reload()
      }
    }
  }

  private func filterLabel(_ title: String, value: String?) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value ?? "全部")
        .foregroundColor(.secondary)
      Image(systemName: "chevron.up.chevron.down")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }

  private func memoryMetadata(_ item: ClawMemoryItem) -> String {
    let person = profiles.first(where: { $0.id == item.subjectID })?.displayName
    return [person, item.kind.rawValue, item.sourceType, item.scope]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  private func open(_ item: ClawMemoryItem) {
    if ClawMemoryVaultAccess.canOpen(
      item,
      protectedIDs: ClawPrivacyVaultService.shared.protectedMemoryIDs,
      isUnlocked: ClawPrivacyVaultService.shared.isUnlocked
    ) {
      editingMemory = item
    } else {
      status = "这条记忆在隐私保险箱中，请先回到记忆中心解锁。"
    }
  }

  private func reload() {
    profiles = HeartTargetService.shared.profiles
    vaultRefreshVersion &+= 1
    isLoading = true
    DispatchQueue.global(qos: .userInitiated).async {
      let loaded = (try? ClawMemoryStore.shared.allMemories()) ?? []
      DispatchQueue.main.async {
        memories = loaded
        isLoading = false
      }
    }
  }
}

private struct ClawMemoryCenterView: View {
  @State private var memories: [ClawMemoryItem] = []
  @State private var memoryCount = 0
  @State private var protectedMemoryCount = 0
  @State private var availableSourceTypes: [String] = []
  @State private var skills: [ClawSkillDefinition] = []
  @State private var pendingMemories: [MemoryV2Record] = []
  @State private var pendingConflicts: [MemoryConflict] = []
  @State private var editingMemory: ClawMemoryItem?
  @State private var showingImporter = false
  @State private var showingPermissionGuide = false
  @State private var showingSkillImporter = false
  @State private var importPreview: ClawMemoryImportPreview?
  @State private var skillPreview: [ClawSkillDefinition] = []
  @State private var discoveredSkillDrafts: [ClawSkillDraftCandidate] = []
  @State private var temporaryMode = ClawMemoryPolicyService.shared.temporaryMode
  @State private var vaultRefreshVersion = 0
  @State private var status = ""

  private var vaultUnlocked: Bool {
    _ = vaultRefreshVersion
    return ClawPrivacyVaultService.shared.isUnlocked
  }

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        List {
        Section {
          NavigationLink {
            ClawAllMemoriesView()
          } label: {
            HStack {
              Label("结构化记忆", systemImage: "brain")
              Spacer()
              Text("\(memoryCount)").foregroundColor(.secondary)
            }
          }
          Button {
            withAnimation { proxy.scrollTo(MemoryCenterAnchor.skills, anchor: .top) }
          } label: {
            HStack {
              Label("可用 Skills", systemImage: "puzzlepiece.extension")
              Spacer()
              Text("\(skills.filter(\.enabled).count)").foregroundColor(.secondary)
            }
          }
          .foregroundColor(.primary)
          HStack {
            Label("隐私保险箱", systemImage: vaultUnlocked ? "lock.open.fill" : "lock.fill")
            Spacer()
            Text("\(protectedMemoryCount)")
              .foregroundColor(.secondary)
          }
          if memories.isEmpty { Text("新的长期记忆会保留来源、范围和置信度。").font(.caption).foregroundColor(.secondary) }
        } header: {
          Text("我的 AI 知道什么")
        }

        if !pendingMemories.isEmpty || !pendingConflicts.isEmpty {
          Section {
            ForEach(pendingMemories) { candidate in
              VStack(alignment: .leading, spacing: 6) {
                Text(candidate.content).font(.subheadline)
                Text("\(candidate.provenance.ingestionMethod) · 置信度 \(Int(candidate.confidence * 100))%")
                  .font(.caption2).foregroundColor(.secondary)
                HStack {
                  Button("采用") { approve(candidate) }.buttonStyle(.borderedProminent)
                  Button("忽略", role: .destructive) { reject(candidate) }.buttonStyle(.bordered)
                }
                .font(.caption)
              }
            }
            ForEach(pendingConflicts) { conflict in
              VStack(alignment: .leading, spacing: 5) {
                Label("发现两条互相冲突的记忆", systemImage: "exclamationmark.triangle.fill")
                  .foregroundColor(.orange)
                Text("现有：\(conflict.existingMemoryID.uuidString.prefix(8)) · 新增：\(conflict.incomingMemoryID.uuidString.prefix(8))")
                  .font(.caption2).foregroundColor(.secondary)
                Button("标记已处理") {
                  try? ClawMemoryStore.shared.resolveMemoryConflict(id: conflict.id)
                  reload()
                }
                .buttonStyle(.bordered)
              }
            }
          } header: {
            Text("待确认 · \(pendingMemories.count + pendingConflicts.count)")
          }
        }

        Section {
          Button { showingPermissionGuide = true } label: {
            Label("系统权限向导", systemImage: "checkmark.shield")
          }
          Toggle("临时模式（本次 AI 不读取长期记忆）", isOn: Binding(
            get: { temporaryMode },
            set: { value in
              temporaryMode = value
              ClawMemoryPolicyService.shared.temporaryMode = value
            }
          ))
          Button {
            if vaultUnlocked {
              ClawPrivacyVaultService.shared.lockNow()
              vaultRefreshVersion &+= 1
            } else {
              ClawPrivacyVaultService.shared.unlock { success, error in
                DispatchQueue.main.async {
                  vaultRefreshVersion &+= 1
                  status = success ? "隐私保险箱已临时解锁。" : "解锁失败：\(error?.localizedDescription ?? "未知错误")"
                }
              }
            }
          } label: {
            Label(
              vaultUnlocked ? "立即锁定隐私保险箱" : "Face ID / 设备密码解锁保险箱",
              systemImage: vaultUnlocked ? "lock.fill" : "faceid"
            )
          }
          ForEach(sourceTypes, id: \.self) { source in
            Toggle(source, isOn: Binding(
              get: { ClawMemoryPolicyService.shared.isSourceEnabled(source) },
              set: { ClawMemoryPolicyService.shared.setSource(source, enabled: $0) }
            ))
          }
        } header: {
          Text("记忆使用权限")
        } footer: {
          Text("关闭某个来源后，原数据仍保留，但不会进入 AI 上下文；可随时恢复。")
        }

        Section {
          ForEach(memories.prefix(30)) { item in
            Button {
              if ClawMemoryVaultAccess.canOpen(
                item,
                protectedIDs: ClawPrivacyVaultService.shared.protectedMemoryIDs,
                isUnlocked: ClawPrivacyVaultService.shared.isUnlocked
              ) {
                editingMemory = item
              } else {
                status = "这条记忆在隐私保险箱中，请先解锁。"
              }
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  if ClawPrivacyVaultService.shared.isProtected(item) {
                    Image(systemName: vaultUnlocked ? "lock.open.fill" : "lock.fill")
                      .font(.caption).foregroundColor(.orange)
                  }
                  Text(
                    ClawPrivacyVaultService.shared.isProtected(item) && !vaultUnlocked
                      ? "已锁定的私人记忆"
                      : item.content
                  )
                  .foregroundColor(.primary)
                }
                let provenance = ClawMemoryPolicyService.shared.provenance(for: item)
                Text("\(provenance.displayName) · \(Int(item.confidence * 100))% · \(item.sourceType)")
                  .font(.caption2).foregroundColor(.secondary)
                if let ref = item.sourceRef, !ref.isEmpty {
                  Text("来源：\(ref)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
              }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
              Button("删除", role: .destructive) {
                _ = try? ClawMemoryStore.shared.deleteMemory(id: item.id)
                reload()
              }
              Button("归档") {
                _ = try? ClawMemoryStore.shared.setMemoryStatus(id: item.id, status: .archived)
                reload()
              }
              .tint(.orange)
              Button(ClawPrivacyVaultService.shared.isProtected(item) ? "移出保险箱" : "放入保险箱") {
                ClawPrivacyVaultService.shared.setProtected(
                  item.id,
                  protected: !ClawPrivacyVaultService.shared.isProtected(item)
                )
                reload()
              }
              .tint(.purple)
            }
          }
        } header: {
          Text("最近记忆 · 共 \(memoryCount) 条 · 显示最近 \(memories.count) 条")
        }

        Section {
          Button { showingImporter = true } label: { Label("从电脑 Agent 导入文件 / 文件夹", systemImage: "square.and.arrow.down") }
          Menu {
            ForEach(ClawAgentExportPreset.allCases) { preset in
              Button(preset.displayName) { exportMarkdown(preset: preset, includeContacts: true) }
            }
            Divider()
            Button("只导出我的个人记忆") { exportMarkdown(preset: .generic, includeContacts: false) }
            if let current = HeartTargetService.shared.selectedProfile {
              Button("只导出当前联系人：\(current.displayName)") {
                exportMarkdown(preset: .generic, includeContacts: true, contactIDs: [current.id])
              }
            }
          } label: {
            Label("导出 Markdown 给 Agent", systemImage: "doc.plaintext")
          }
          Button { exportJSON() } label: { Label("导出 JSON", systemImage: "curlybraces") }
          Button { exportPackage() } label: { Label("完整 CLAW 备份（.clawmemory）", systemImage: "shippingbox") }
          if let preview = importPreview {
            VStack(alignment: .leading, spacing: 6) {
              Text("分析结果：新增 \(preview.newCount) · 重复 \(preview.duplicateCount) · 冲突 \(preview.conflictCount)")
                .font(.subheadline)
              if !preview.tasks.isEmpty || !preview.skills.isEmpty {
                Text("附带：任务 \(preview.tasks.count) · Skill \(preview.skills.count)")
                  .font(.caption).foregroundColor(.secondary)
              }
              if !preview.contacts.isEmpty || !preview.conversations.isEmpty {
                Text("人物 \(preview.contacts.count) · 聊天时间线 \(preview.conversations.count)")
                  .font(.caption).foregroundColor(.secondary)
              }
              if preview.conflictCount > 0 {
                Text("冲突项不会自动覆盖手机 CLAW 的现有记忆；本次确认只写入无冲突的新记忆。")
                  .font(.caption).foregroundColor(.orange)
              }
              Text(preview.sourceName).font(.caption2).foregroundColor(.secondary)
              Button("确认写入 Memory Core") { commit(preview) }
                .buttonStyle(.borderedProminent)
                .disabled(
                  preview.candidates.isEmpty && preview.tasks.isEmpty && preview.skills.isEmpty
                    && preview.contacts.isEmpty && preview.conversations.isEmpty
                )
            }
          }
          if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
        } header: {
          Text("记忆导入 / 导出")
        }

        Section {
          if !discoveredSkillDrafts.isEmpty {
            ForEach(discoveredSkillDrafts) { draft in
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Image(systemName: "sparkles")
                  Text(draft.proposedSkill.name).font(.subheadline.weight(.semibold))
                  Spacer()
                  Text("\(draft.sampleCount) 样本").font(.caption2).foregroundColor(.secondary)
                }
                Text(draft.reason).font(.caption).foregroundColor(.secondary)
                Text("只生成草稿，不会自动启用。")
                  .font(.caption2).foregroundColor(.orange)
                Button("保存为待确认 Skill") {
                  do {
                    _ = try ClawSkillDiscoveryService.shared.saveDraft(draft)
                    status = "Skill 草稿已保存，默认停用；你可以检查后再启用。"
                    reload()
                  } catch {
                    status = "保存 Skill 草稿失败：\(error.localizedDescription)"
                  }
                }
                .buttonStyle(.bordered)
                .font(.caption)
              }
            }
          }
          Button { showingSkillImporter = true } label: {
            Label("安装 Skill（.clawskill / JSON）", systemImage: "plus.square.on.square")
          }
          if !skillPreview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("待安装 Skill：\(skillPreview.map(\.name).joined(separator: "、"))")
                .font(.subheadline)
              Button("确认安装") { installSkills() }
                .buttonStyle(.borderedProminent)
            }
          }
          ForEach(skills) { skill in
            VStack(alignment: .leading, spacing: 4) {
              HStack { Text(skill.name); Spacer(); Text("v\(skill.version)").font(.caption).foregroundColor(.secondary) }
              Text(skill.summary).font(.caption).foregroundColor(.secondary)
              let metrics = ClawSkillRuntime.shared.metrics(skillID: skill.id)
              Text("采用 \(metrics.accepted) · 修改 \(metrics.edited) · 重生成 \(metrics.regenerated) · 命中率 \(Int(metrics.adoptionRate * 100))%")
                .font(.caption2).foregroundColor(.secondary)
              if let triggers = skill.triggers, !triggers.isEmpty {
                Text("触发：\(triggers.map(\.rawValue).joined(separator: " · "))")
                  .font(.caption2).foregroundColor(.secondary).lineLimit(2)
              }
              if let tools = skill.toolIDs, !tools.isEmpty {
                Text("工具：\(tools.joined(separator: " · "))")
                  .font(.caption2).foregroundColor(.secondary).lineLimit(2)
              }
              if let inputContract = skill.inputContract, !inputContract.isEmpty {
                Text("输入：\(inputContract)")
                  .font(.caption2).foregroundColor(.secondary).lineLimit(2)
              }
              if let outputContract = skill.outputContract, !outputContract.isEmpty {
                Text("输出：\(outputContract)")
                  .font(.caption2).foregroundColor(.secondary).lineLimit(2)
              }
              if let learned = skill.learnedDirective, !learned.isEmpty {
                Text("已进化：\(learned)")
                  .font(.caption2).foregroundColor(.accentColor).lineLimit(3)
              }
              if let experiment = ClawSkillRuntime.shared.experimentMetrics(skillID: skill.id) {
                let controlRate = Int(experiment.control.successRate * 100)
                let evolvedRate = Int(experiment.evolved.successRate * 100)
                Text("A/B：原版 \(controlRate)%（\(experiment.control.impressions)次） · 进化版 \(evolvedRate)%（\(experiment.evolved.impressions)次）")
                  .font(.caption2).foregroundColor(.secondary)
                if let winner = experiment.winner {
                  Text("当前评测领先：\(winner == "evolved" ? "进化版" : "原版")")
                    .font(.caption2).foregroundColor(.green)
                }
              }
              HStack {
                Button(skill.enabled ? "停用" : "启用") { toggleSkill(skill) }
                  .buttonStyle(.bordered)
                if !ClawSkillRuntime.shared.versions(skillID: skill.id).isEmpty {
                  Button("回滚上一版") { rollbackSkill(skill) }
                    .buttonStyle(.bordered)
                }
              }
              .font(.caption)
            }
          }
        } header: {
          Text("Skill / 自动进化")
        }
        .id(MemoryCenterAnchor.skills)
        }
        .navigationTitle("记忆中心")
        .onAppear(perform: reload)
        .task {
          while !Task.isCancelled {
            do {
              try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
              return
            }
            vaultRefreshVersion &+= 1
            if let editingMemory,
               !ClawMemoryVaultAccess.canOpen(
                 editingMemory,
                 protectedIDs: ClawPrivacyVaultService.shared.protectedMemoryIDs,
                 isUnlocked: ClawPrivacyVaultService.shared.isUnlocked
               ) {
              self.editingMemory = nil
              status = "隐私保险箱已自动锁定。"
            }
          }
        }
        .sheet(item: $editingMemory) { item in
          ClawMemoryEditorView(item: item) {
            editingMemory = nil
            reload()
          }
        }
        .sheet(isPresented: $showingImporter) {
          ClawMemoryDocumentPicker(allowsMultipleSelection: true) { urls in
            showingImporter = false
            analyzeImports(urls)
          }
        }
        .sheet(isPresented: $showingPermissionGuide) { ClawPermissionGuideView() }
        .sheet(isPresented: $showingSkillImporter) {
          ClawMemoryDocumentPicker(allowsMultipleSelection: false) { urls in
            showingSkillImporter = false
            guard let url = urls.first else { return }
            do {
              skillPreview = try ClawSkillImportService.shared.preview(data: Data(contentsOf: url))
              status = "Skill 包已通过声明式校验，请确认安装。"
            } catch {
              status = "Skill 解析失败：\(error.localizedDescription)"
            }
          }
        }
      }
    }
  }

  private func reload() {
    memories = (try? ClawMemoryStore.shared.memories(limit: 30)) ?? []
    memoryCount = (try? ClawMemoryStore.shared.memoryCount()) ?? memories.count
    protectedMemoryCount = (try? ClawMemoryStore.shared.activeMemoryCount(
      ids: ClawPrivacyVaultService.shared.protectedMemoryIDs
    )) ?? 0
    availableSourceTypes = (try? ClawMemoryStore.shared.activeMemorySourceTypes()) ?? []
    skills = (try? ClawMemoryStore.shared.skills()) ?? []
    pendingMemories = (try? ClawMemoryStore.shared.memoryV2(state: .candidate, limit: 100)) ?? []
    pendingConflicts = (try? ClawMemoryStore.shared.memoryConflicts()) ?? []
    discoveredSkillDrafts = ClawSkillDiscoveryService.shared.discover()
    temporaryMode = ClawMemoryPolicyService.shared.temporaryMode
    vaultRefreshVersion &+= 1
  }

  private var sourceTypes: [String] {
    availableSourceTypes
  }

  private func approve(_ candidate: MemoryV2Record) {
    var approved = candidate
    approved.state = .confirmed
    approved.confirmedAt = Date()
    approved.updatedAt = Date()
    approved.version += 1
    try? DefaultMemorySDK.shared.remember(approved, evidence: approved.evidence)
    reload()
  }

  private func reject(_ candidate: MemoryV2Record) {
    try? DefaultMemorySDK.shared.forget(id: candidate.id, mode: .archive)
    reload()
  }

  private func commit(_ preview: ClawMemoryImportPreview) {
    do {
      let count = try ClawMemoryExchangeService.shared.commit(preview)
      importPreview = nil
      status = "已导入 \(count) 条记忆。"
      reload()
    } catch { status = "导入失败：\(error.localizedDescription)" }
  }

  private func installSkills() {
    do {
      let count = try ClawSkillImportService.shared.install(skillPreview)
      skillPreview = []
      status = "已安装 \(count) 个 Skill。Skill 只能调用 CLAW 内置受控能力，不执行任意 Swift/脚本。"
      reload()
    } catch {
      status = "Skill 安装失败：\(error.localizedDescription)"
    }
  }

  private func exportMarkdown(
    preset: ClawAgentExportPreset,
    includeContacts: Bool,
    contactIDs: Set<UUID>? = nil
  ) {
    do {
      let text = try ClawMemoryExchangeService.shared.exportMarkdown(
        preset: preset,
        includeContacts: includeContacts,
        contactIDs: contactIDs
      )
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("CLAW-Memory-\(preset.rawValue).md")
      try text.write(to: url, atomically: true, encoding: .utf8)
      share(url)
    } catch { status = "导出失败：\(error.localizedDescription)" }
  }

  private func exportJSON() {
    do {
      let data = try ClawMemoryExchangeService.shared.exportJSON()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("CLAW-Memory.json")
      try data.write(to: url, options: .atomic)
      share(url)
    } catch { status = "导出失败：\(error.localizedDescription)" }
  }

  private func exportPackage() {
    do {
      let url = try ClawMemoryExchangeService.shared.exportClawMemoryPackage()
      share(url)
    } catch { status = "完整备份失败：\(error.localizedDescription)" }
  }

  private func analyzeImports(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    do {
      let importURLs = expandImportURLs(urls)
      guard !importURLs.isEmpty else {
        status = "没有找到可导入的 .md/.txt/.json/.jsonl/.clawmemory 文件。"
        return
      }
      var previews: [ClawMemoryImportPreview] = []
      for url in importURLs {
        let data = try Data(contentsOf: url)
        previews.append(try ClawMemoryExchangeService.shared.previewImport(data: data, fileName: url.lastPathComponent))
      }
      importPreview = ClawMemoryImportPreview(
        candidates: previews.flatMap(\.candidates),
        tasks: previews.flatMap(\.tasks),
        skills: previews.flatMap(\.skills),
        contacts: previews.flatMap(\.contacts),
        conversations: previews.flatMap(\.conversations),
        duplicateCount: previews.reduce(0) { $0 + $1.duplicateCount },
        conflictCount: previews.reduce(0) { $0 + $1.conflictCount },
        sourceName: importURLs.count == 1 ? importURLs[0].lastPathComponent : "\(importURLs.count) 个文件"
      )
      status = "已分析 \(importURLs.count) 个文件，请确认后写入。"
    } catch {
      status = "导入分析失败：\(error.localizedDescription)"
    }
  }

  private func expandImportURLs(_ urls: [URL]) -> [URL] {
    let allowed = Set(["md", "markdown", "txt", "json", "jsonl", "clawmemory", "zip"])
    var result: [URL] = []
    let fm = FileManager.default
    for url in urls {
      var isDirectory: ObjCBool = false
      if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
        if let enumerator = fm.enumerator(
          at: url,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
          for case let fileURL as URL in enumerator {
            if allowed.contains(fileURL.pathExtension.lowercased()) {
              result.append(fileURL)
            }
          }
        }
      } else if allowed.contains(url.pathExtension.lowercased()) {
        result.append(url)
      }
    }
    return result
  }

  private func toggleSkill(_ skill: ClawSkillDefinition) {
    var updated = skill
    ClawSkillRuntime.shared.captureVersion(skill)
    updated.enabled.toggle()
    updated.version += 1
    try? ClawMemoryStore.shared.saveSkill(updated)
    ClawSkillRuntime.shared.captureVersion(updated)
    reload()
  }

  private func rollbackSkill(_ skill: ClawSkillDefinition) {
    do {
      if let rolled = try ClawSkillRuntime.shared.rollback(skillID: skill.id) {
        status = "已将 \(rolled.name) 回滚为新的 v\(rolled.version)。"
      }
      reload()
    } catch {
      status = "Skill 回滚失败：\(error.localizedDescription)"
    }
  }

  private func share(_ url: URL) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    presenter.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
  }
}

private struct ClawMemoryEditorView: View {
  let item: ClawMemoryItem
  let onDone: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var content: String
  @State private var confidence: Double

  init(item: ClawMemoryItem, onDone: @escaping () -> Void) {
    self.item = item
    self.onDone = onDone
    _content = State(initialValue: item.content)
    _confidence = State(initialValue: item.confidence)
  }

  var body: some View {
    NavigationView {
      Form {
        Section("记忆内容") {
          TextEditor(text: $content).frame(minHeight: 120)
        }
        Section("可信度") {
          Slider(value: $confidence, in: 0...1, step: 0.05)
          Text("\(Int(confidence * 100))%").foregroundColor(.secondary)
        }
        Section("来源") {
          HStack {
            Text("类型")
            Spacer()
            Text(ClawMemoryPolicyService.shared.provenance(for: item).displayName).foregroundColor(.secondary)
          }
          HStack {
            Text("来源")
            Spacer()
            Text(item.sourceType).foregroundColor(.secondary)
          }
          if let ref = item.sourceRef { Text(ref).font(.caption).foregroundColor(.secondary) }
        }
        Section {
          Button("删除这条记忆", role: .destructive) {
            _ = try? ClawMemoryStore.shared.deleteMemory(id: item.id)
            onDone()
            dismiss()
          }
        }
      }
      .navigationTitle("编辑记忆")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            _ = try? ClawMemoryStore.shared.updateMemory(id: item.id, content: content, confidence: confidence)
            onDone()
            dismiss()
          }
          .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct ClawMemoryDocumentPicker: UIViewControllerRepresentable {
  var allowsMultipleSelection: Bool
  var onPick: ([URL]) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let types: [UTType] = [.plainText, .json, .data, .archive, .folder]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.allowsMultipleSelection = allowsMultipleSelection
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void
    init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      onPick(urls)
    }
  }
}

