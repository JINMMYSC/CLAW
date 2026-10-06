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
  @State private var voiceMode = ClawVoiceInputService.shared.languageMode

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
        Menu {
          ForEach(ClawVoiceLanguageMode.allCases, id: \.rawValue) { mode in
            Button {
              voiceMode = mode
              ClawVoiceInputService.shared.languageMode = mode
            } label: {
              if voiceMode == mode {
                Label(mode.displayName, systemImage: "checkmark")
              } else {
                Text(mode.displayName)
              }
            }
          }
        } label: {
          VStack(spacing: 0) {
            Image(systemName: "waveform.circle")
              .font(.system(size: 24))
            Text(voiceMode.displayName)
              .font(.system(size: 8))
          }
          .foregroundColor(.accentColor)
        }
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
  @State private var suggestions: [ClawSecretarySuggestion] = []
  @State private var briefing = ""

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
            .swipeActions(edge: .trailing) {
              Button("完成") {
                _ = ClawProactiveSecretaryService.shared.complete(taskID: task.id)
                reload()
              }
              .tint(.green)
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
    suggestions = ClawProactiveSecretaryService.shared.suggestions()
    briefing = ClawProactiveSecretaryService.shared.briefing()
    ClawProactiveSecretaryService.shared.refreshLocalNotifications()
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
  @State private var editingMemory: ClawMemoryItem?
  @State private var showingImporter = false
  @State private var showingSkillImporter = false
  @State private var importPreview: ClawMemoryImportPreview?
  @State private var skillPreview: [ClawSkillDefinition] = []
  @State private var discoveredSkillDrafts: [ClawSkillDraftCandidate] = []
  @State private var temporaryMode = ClawMemoryPolicyService.shared.temporaryMode
  @State private var vaultUnlocked = ClawPrivacyVaultService.shared.isUnlocked
  @State private var status = ""

  var body: some View {
    NavigationView {
      List {
        Section {
          HStack { Label("结构化记忆", systemImage: "brain"); Spacer(); Text("\(memories.count)").foregroundColor(.secondary) }
          HStack { Label("可用 Skills", systemImage: "puzzlepiece.extension"); Spacer(); Text("\(skills.filter(\.enabled).count)").foregroundColor(.secondary) }
          HStack {
            Label("隐私保险箱", systemImage: vaultUnlocked ? "lock.open.fill" : "lock.fill")
            Spacer()
            Text("\(memories.filter { ClawPrivacyVaultService.shared.isProtected($0) }.count)")
              .foregroundColor(.secondary)
          }
          if memories.isEmpty { Text("新的长期记忆会保留来源、范围和置信度。").font(.caption).foregroundColor(.secondary) }
        } header: {
          Text("我的 AI 知道什么")
        }

        Section {
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
              vaultUnlocked = false
            } else {
              ClawPrivacyVaultService.shared.unlock { success, error in
                DispatchQueue.main.async {
                  vaultUnlocked = success
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
              if !ClawPrivacyVaultService.shared.isProtected(item) || vaultUnlocked {
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
          Text("最近记忆")
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
      }
      .navigationTitle("记忆中心")
      .onAppear(perform: reload)
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

  private func reload() {
    memories = (try? ClawMemoryStore.shared.memories(limit: 1_000)) ?? []
    skills = (try? ClawMemoryStore.shared.skills()) ?? []
    discoveredSkillDrafts = ClawSkillDiscoveryService.shared.discover()
    temporaryMode = ClawMemoryPolicyService.shared.temporaryMode
    vaultUnlocked = ClawPrivacyVaultService.shared.isUnlocked
  }

  private var sourceTypes: [String] {
    Array(Set(memories.map(\.sourceType))).sorted()
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
