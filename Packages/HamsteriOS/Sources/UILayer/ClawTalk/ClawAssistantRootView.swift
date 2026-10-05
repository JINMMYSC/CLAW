import HamsterKeyboardKit
import HamsterKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// CLAW 主 App：助手是首页，数据采集只是其中一个能力面板。
struct ClawAssistantRootView: View {
  @ObservedObject var viewModel: ClawTalkViewModel

  var body: some View {
    TabView {
      ClawAssistantChatView()
        .tabItem { Label("助手", systemImage: "sparkles") }

      ClawSecretaryTodayView()
        .tabItem { Label("今日", systemImage: "checklist") }

      ClawPeopleView()
        .tabItem { Label("人物", systemImage: "person.2.fill") }

      ClawMemoryCenterView()
        .tabItem { Label("记忆", systemImage: "brain.head.profile") }

      ClawTalkRootView(viewModel: viewModel)
        .tabItem { Label("数据", systemImage: "tray.full.fill") }
    }
    .navigationTitle("CLAW")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct ClawAssistantChatView: View {
  @ObservedObject private var chat = ClawChatService.shared
  @State private var input = ""
  @State private var recording = false
  @State private var voiceHint = ""

  var body: some View {
    VStack(spacing: 0) {
      contextHeader
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            if chat.messages.isEmpty {
              emptyAssistant
            }
            ForEach(chat.messages) { message in
              assistantBubble(message)
                .id(message.id)
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
      }
      Divider()
      composer
    }
    .background(Color(.systemGroupedBackground))
  }

  private var contextHeader: some View {
    HStack(spacing: 8) {
      Image(systemName: "brain.head.profile").foregroundColor(.accentColor)
      VStack(alignment: .leading, spacing: 1) {
        Text("CLAW 私人助手").font(.headline)
        Text(HeartTargetService.shared.selectedProfile.map { "当前对象：\($0.displayName) · 长期记忆已启用" } ?? "全局记忆 · 手机为记忆源")
          .font(.caption).foregroundColor(.secondary).lineLimit(1)
      }
      Spacer()
      Button("新对话") { chat.clearHistory() }
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color(.secondarySystemGroupedBackground))
  }

  private var emptyAssistant: some View {
    VStack(spacing: 12) {
      Image(systemName: "sparkles").font(.system(size: 34)).foregroundColor(.accentColor)
      Text("我是 CLAW").font(.title3.weight(.semibold))
      Text("可以直接问我人物、最近聊过的事情、未完成事项，或者让我帮你规划下一步。")
        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
      HStack {
        quickAsk("我今天还有什么没做？")
        quickAsk("最近和谁有事要跟进？")
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
      if message.role != "user" { Spacer(minLength: 44) }
    }
    .padding(.horizontal, 12)
  }

  private var composer: some View {
    VStack(spacing: 4) {
      if !voiceHint.isEmpty {
        Text(voiceHint).font(.caption).foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 8) {
        Button {
          toggleVoice()
        } label: {
          Image(systemName: recording ? "stop.circle.fill" : "mic.circle.fill")
            .font(.system(size: 30))
            .foregroundColor(recording ? .red : .accentColor)
        }
        TextField("问 CLAW…", text: $input)
          .textFieldStyle(.roundedBorder)
          .onSubmit { send(input) }
        Button {
          send(input)
        } label: {
          Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
        }
        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(.secondarySystemGroupedBackground))
  }

  private func send(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    input = ""
    chat.send(trimmed)
  }

  private func toggleVoice() {
    if recording {
      ClawVoiceInputService.shared.stop()
      recording = false
      voiceHint = "正在完成识别…"
      return
    }
    recording = true
    voiceHint = "正在听…点停止结束"
    ClawVoiceInputService.shared.start { result in
      recording = false
      switch result {
      case .success(let text):
        voiceHint = ""
        send(text)
      case .failure(let error):
        voiceHint = "语音识别失败：\(error.localizedDescription)"
      }
    }
  }
}

private struct ClawSecretaryTodayView: View {
  @State private var tasks: [ClawSecretaryTask] = []
  @State private var memories: [ClawMemoryItem] = []

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
          ForEach(tasks.prefix(20)) { task in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(task.title).font(.body)
                Spacer()
                Text(task.kind.rawValue).font(.caption2).foregroundColor(.secondary)
              }
              if let due = task.dueAt {
                Text(due, style: .relative).font(.caption).foregroundColor(.orange)
              }
              if let details = task.details, !details.isEmpty {
                Text(details).font(.caption).foregroundColor(.secondary).lineLimit(2)
              }
            }
          }
        } header: {
          Text("下一步")
        }
      }
      .navigationTitle("今日秘书")
      .onAppear(perform: reload)
      .refreshable { reload() }
    }
  }

  private func reload() {
    tasks = (try? ClawMemoryStore.shared.tasks(status: .open, limit: 100)) ?? []
    memories = (try? ClawMemoryStore.shared.memories(limit: 500)) ?? []
  }
}

private struct ClawPeopleView: View {
  @State private var profiles = HeartTargetService.shared.profiles
  @State private var selectedID = HeartTargetService.shared.selectedProfile?.id

  var body: some View {
    NavigationView {
      List {
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
            Text("请到设置 → 聊天对象档案添加联系人。截图归档和帮你回会使用这里的对象。")
              .foregroundColor(.secondary)
          }
          ForEach(profiles) { profile in
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
                  Text(profile.displayName)
                  Text(profile.relationship.isEmpty ? (profile.bio.isEmpty ? "尚未形成画像" : profile.bio) : profile.relationship)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if selectedID == profile.id { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
              }
              .contentShape(Rectangle())
              .simultaneousGesture(TapGesture().onEnded {
                HeartTargetService.shared.select(id: profile.id)
                selectedID = profile.id
              })
            }
          }
        } header: {
          Text("聊天对象")
        }
      }
      .navigationTitle("人物")
      .onReceive(NotificationCenter.default.publisher(for: .heartTargetProfilesDidChange)) { _ in
        profiles = HeartTargetService.shared.profiles
        selectedID = HeartTargetService.shared.selectedProfile?.id
      }
    }
  }
}

private struct ClawContactDetailView: View {
  let profile: HeartTargetProfile
  @State private var timeline: [ClawConversationMessage] = []
  @State private var memories: [ClawMemoryItem] = []

  var body: some View {
    List {
      Section {
        if !profile.relationship.isEmpty {
          HStack { Text("关系"); Spacer(); Text(profile.relationship).foregroundColor(.secondary) }
        }
        if !profile.bio.isEmpty { Text(profile.bio) }
        if !profile.learnedSummary.isEmpty { Text(profile.learnedSummary).foregroundColor(.secondary) }
        if profile.bio.isEmpty && profile.learnedSummary.isEmpty { Text("暂无画像").foregroundColor(.secondary) }
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
      timeline = (try? ClawMemoryStore.shared.conversation(contactID: profile.id, limit: 200)) ?? []
      memories = (try? ClawMemoryStore.shared.memories(scope: "contact", subjectID: profile.id, limit: 100)) ?? []
    }
  }
}

private struct ClawMemoryCenterView: View {
  @State private var memories: [ClawMemoryItem] = []
  @State private var skills: [ClawSkillDefinition] = []
  @State private var showingImporter = false
  @State private var showingSkillImporter = false
  @State private var importPreview: ClawMemoryImportPreview?
  @State private var skillPreview: [ClawSkillDefinition] = []
  @State private var status = ""

  var body: some View {
    NavigationView {
      List {
        Section {
          HStack { Label("结构化记忆", systemImage: "brain"); Spacer(); Text("\(memories.count)").foregroundColor(.secondary) }
          HStack { Label("可用 Skills", systemImage: "puzzlepiece.extension"); Spacer(); Text("\(skills.filter(\.enabled).count)").foregroundColor(.secondary) }
          if memories.isEmpty { Text("新的长期记忆会保留来源、范围和置信度。").font(.caption).foregroundColor(.secondary) }
        } header: {
          Text("我的 AI 知道什么")
        }

        Section {
          ForEach(memories.prefix(30)) { item in
            VStack(alignment: .leading, spacing: 3) {
              Text(item.content)
              Text("\(item.scope) · \(item.kind.rawValue) · \(item.sourceType)").font(.caption2).foregroundColor(.secondary)
            }
          }
        } header: {
          Text("最近记忆")
        }

        Section {
          Button { showingImporter = true } label: { Label("从电脑 Agent 导入", systemImage: "square.and.arrow.down") }
          Button { exportMarkdown() } label: { Label("导出 Markdown 给 Agent", systemImage: "doc.plaintext") }
          Button { exportJSON() } label: { Label("导出 JSON", systemImage: "curlybraces") }
          Button { exportPackage() } label: { Label("完整 CLAW 备份（.clawmemory）", systemImage: "shippingbox") }
          if let preview = importPreview {
            VStack(alignment: .leading, spacing: 6) {
              Text("待导入：记忆 \(preview.candidates.count) · 任务 \(preview.tasks.count) · Skill \(preview.skills.count)")
                .font(.subheadline)
              Text(preview.sourceName).font(.caption2).foregroundColor(.secondary)
              Button("确认写入 Memory Core") { commit(preview) }.buttonStyle(.borderedProminent)
            }
          }
          if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
        } header: {
          Text("记忆导入 / 导出")
        }

        Section {
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
              Text("采用 \(skill.acceptedCount) · 修改 \(skill.editedCount) · 重生成 \(skill.regeneratedCount)")
                .font(.caption2).foregroundColor(.secondary)
              if let learned = skill.learnedDirective, !learned.isEmpty {
                Text("已进化：\(learned)")
                  .font(.caption2).foregroundColor(.accentColor).lineLimit(3)
              }
            }
          }
        } header: {
          Text("Skill / 自动进化")
        }
      }
      .navigationTitle("记忆中心")
      .onAppear(perform: reload)
      .sheet(isPresented: $showingImporter) {
        ClawMemoryDocumentPicker { url in
          showingImporter = false
          do {
            let data = try Data(contentsOf: url)
            importPreview = try ClawMemoryExchangeService.shared.previewImport(data: data, fileName: url.lastPathComponent)
            status = "已分析文件，请确认后写入。"
          } catch {
            status = "导入分析失败：\(error.localizedDescription)"
          }
        }
      }
      .sheet(isPresented: $showingSkillImporter) {
        ClawMemoryDocumentPicker { url in
          showingSkillImporter = false
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

  private func reload() {
    memories = (try? ClawMemoryStore.shared.memories(limit: 1_000)) ?? []
    skills = (try? ClawMemoryStore.shared.skills()) ?? []
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

  private func exportMarkdown() {
    do {
      let text = try ClawMemoryExchangeService.shared.exportMarkdown()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("CLAW-Memory.md")
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

  private func share(_ url: URL) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    presenter.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
  }
}

private struct ClawMemoryDocumentPicker: UIViewControllerRepresentable {
  var onPick: (URL) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let types: [UTType] = [.plainText, .json, .data, .archive]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      if let url = urls.first { onPick(url) }
    }
  }
}
