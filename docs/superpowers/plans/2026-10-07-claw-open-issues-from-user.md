# CLAW 待修问题清单（用户反馈汇总）

> 记录时间：2026-10-07
> 用法：这是用户口头反馈的待修项汇总，后续继续补充。每条都带代码定位和当前状态，接手时不必重新排查。

## 当前仓库状态

- 已推送且 CI 全绿的基线：`f3a52bc84e223053c68f85ae5f79f29938e47158`
- 已提交但**尚未推送**（当时 github.com 不通）：
  - `a620bc3` diag: surface the real reason when the keyboard cannot open the host app
  - `107f3e4` fix: run CLAW voice input inside the keyboard instead of jumping to the host app
- 工作区未提交（用户要求暂缓）：`Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift` 的候选栏图标精简半成品

## 一、候选栏右侧图标（规格已确认）

用户要的最终规则：

1. 「显示应用图标」（键盘设置 → 候选栏设置）控制整组 CLAW 入口：人物（全局）／帮你回／超会说／AI／眼睛／表情／`⋯`。
2. 「显示键盘收起图标」控制 `⌄`，**默认必须开启**。
3. 候选栏里 `⌄` 单独贴最右侧，不和眼睛／表情／`⋯` 挤在一起。
4. 输入文字时应用图标那一组**不显示**（用户已确认）。即：输入为空显示应用组 + `⌄`；打字时只剩候选词 + `⌄`。

必须连带处理的两件事：

- `Resources/SharedSupport/hamster.yaml` 里 `displayAppIconButton` 和 `displayKeyboardDismissButton` 默认都是 `false`，接线后要改成 `true`，否则升级后那排按钮会默认消失。
- 功能行现在是一长串手写约束（`contactButton → helpReplyButton → … → moreButton → dismissKeyboardButton`），隐藏其中几个会在前面留空白，需要改成横向 stack 才能正确收起。

状态：**未完成**。工作区里只有一版过时的半成品（只留 `⋯`、宽度 112→40），要按上面规则重做。

## 二、候选栏下拉（展开）只剩一行

- 现象：点候选栏展开，键盘变高但候选词仍只有一行，多出来的位置是空白。
- 根因：`KeyboardToolbarView.swift` 里 `candidateBarView.topAnchor = commonFunctionBar.topAnchor`、`.bottomAnchor = commonFunctionBar.bottomAnchor`，而 `commonFunctionBar` 高度被写死为 `keyboardContext.heightOfToolbar`（默认 50）。候选栏被永久夹在 50pt 内。
- 出处：这两条约束是 **6152632** 加入的。之前是 `addSubview(candidateBarView)` + `candidateBarView.fillSuperview()`，即铺满整条工具栏，展开时能拿到全部高度。
- 展开机制本身仍在 `KeyboardRootView.swift`（展开时移除按键视图，把工具栏高度设为键区高度 + 50）。
- 修法方向：候选栏上下约束按 `keyboardContext.candidatesViewState` 切换两组——收起时保持现状，展开时改为从工具栏顶部延伸到功能行上沿。

状态：**已定位，未改**。

## 三、中文九宫格左侧符号初次显示是浅灰色

- 现象：刚进入中文九宫格，左侧那一列滑动符号是浅灰、看不清；滑动列表后才变黑。
- 根因：`SymbolCell` 自己缓存 style，颜色在 `updateConfiguration` 里取 `style?.foregroundColor`；而 `setStyle` 最终只是重新 apply 一份**内容完全相同**的 diffable snapshot，不会重新配置已存在的 cell，所以屏幕上已有格子保留旧颜色，只有滑动后新建/复用的格子才拿到新样式。另外初始 style 用的是 `ChineseNineGridKeyboard.init` 当时的 `colorScheme`。
- 涉及文件：`SymbolCell.swift`、`SymbolsVerticalView.swift`、`ChineseNineGridKeyboard.swift`。
- 修法方向：`setStyle` 时强制重建单元格（如 `applySnapshotUsingReloadData`）；或让 cell 不再缓存 style；并保证首次构建使用最终配色。

状态：**已定位，未改**。

## 四、键盘语音：要在键盘里直接录，不跳转

- 用户明确要求：语音输入就在输入法界面完成，**不要跳主程序**。
- 已做的改动（提交 `107f3e4`，未推送）：
  - `ClawVoiceInputService.start()` / `startStreaming()` 去掉 `isKeyboardExtensionRuntime` 拦截。
  - `ClawPanelOverlayView` 去掉话筒／电话的 `handOffToHostVoiceInput()` 跳转分支，恢复键盘内录音与连续通话链路。
- 前提条件：键盘开启「允许完全访问」，且麦克风与语音识别权限已在主程序授权过（扩展不能弹权限框）。键盘 Info.plist 已有 `NSMicrophoneUsageDescription` 与 `NSSpeechRecognitionUsageDescription`。
- 待验证：真机上按住话筒／点电话能否直接出字。若系统仍拒绝扩展录音，会返回错误而不是静默失败。

状态：**代码已改，待打包 + 真机验证**。

## 五、键盘所有"打开主程序"入口失败

- 现象：键盘里点语音（旧逻辑）、`⋯ → 打开 CLAW 助手`、`⋯ → 键盘设置`，全部弹「未找到输入法主程序」。
- 已排除：
  - 协议未注册 —— 手机 Safari 打开 `hamster://app.lgm.7517/clawTalk` 可以正常跳转。
  - 完全访问未开 —— 用户已开启。
  - 多个 App 抢同一 scheme —— 用户已删掉其他 CLAW／Hamster／GuruIM／ClawBase，仍然失败。
  - bundle id / 签名不一致 —— 仓库侧 `app.lgm.7517`（主程序）与 `app.lgm.7517.123`（键盘）成对，签名脚本不改写 bundle id，全仓库只有 `Hamster/Info.plist` 注册该协议。
- 失败点：`KeyboardInputViewController.openUrl` 调用 `extensionContext.open(url)`，回调返回 `success == false`，于是走 `showOpenUrlFailureHint()`。
- 已加的诊断（提交 `a620bc3`，未推送）：失败提示改成显示「完全访问状态 + 真实 URL」，不再统一显示"未找到输入法主程序"。
- 备注：语音已按第四条改为不跳转，但 `⋯` 菜单里另外两个入口仍然依赖这条通道，所以这个 bug 依然要解决。

状态：**原因未定，已加诊断，待用新包复现取证**。

## 六、其他已记录但未动手的项

- 键盘设置里两个死开关：`displayAppIconButton`、`displayKeyboardDismissButton` 目前只有配置读写 + `KeyboardContext` 访问器，没有任何视图消费，属于空转（见第一条的接线工作）。
- 面板重复订阅与强制布局精简（`KeyboardToolbarView` / `ClawPanelOverlayView` 多处 `layoutIfNeeded()`）。
- 语音状态机加固：防连点、音频中断、路由变化、后台处理。
- 主程序「键盘设置 → 候选栏设置」里，`显示候选项序号`、`显示候选 Comment` 只在关闭「iOS 原生布局」时生效；`编码区高度` 在 iOS 原生布局下被固定为 20。

## 七、Memory OS 交接稿落地差距

对照《CLAW TALK 记忆系统最终方向交接稿》逐条核实（2026-10-07）。结论：**主体未落地，已落的是地基。**

### 已经落地

- SQLite 作为唯一真相：`ClawMemoryStore`，现有 `memory_items` / `conversation_messages` / `secretary_tasks` / `skills` / `evolution_feedback` 五张表。
- Context Builder：`ClawContextBuilder` 已被帮你回、超会说、助手会话、Skill Runtime 共用；6000 字符预算，分区拼装。
- 本地语义检索：`ClawContextBuilder` 用 `NLEmbedding.sentenceEmbedding` 在设备本地算语义相似度，与关键词重叠、置信度、时间衰减、精确 key 一起加权排序。**但没有向量索引**，每条候选都要现场算一次向量。
- 键盘扩展瘦身：键盘只写 App Group 队列（`ClawKeyboardDeferredEventService`），主程序启动时 drain。
- 隐私基础：来源暂停、临时模式、隐私保险箱（`LAContext`，Face ID / 设备密码解锁）。
- 导入导出：`.clawmemory` / Markdown / JSON（`ClawMemoryExchangeService`）。
- 人物身份解析基础：`ClawContactIdentityResolver`。
- 任务提取：`ClawSecretaryExtractor`。

### 只建了结构、还没有落地

- Memory V2 模型与五张表：`raw_events` / `memory_v2` / `memory_evidence` / `memory_versions` / `memory_lineage`，对应 Scope / State / Type / Trust / Provenance / Evidence / Lineage。
  **关键：`saveMemoryV2` 的调用方为零，这几张表现在是空的。**
- `StandingIntent` 结构体已定义，无存储、无使用。

### 完全没有

- FTS5 全文索引（全仓库搜不到 `fts5` 或 `MATCH`）。
- Memory Router。
- Memory SDK 统一接口（各功能现在直接调 `ClawMemoryStore`）。
- Provenance Trust 的实际落地（旧表只有 sourceType / sourceRef / confidence）。
- Evidence 写入与 Lineage Forget。
- Memory Promotion（Candidate → Confirmed 生命周期）。
- 冲突处理、陈旧降权、TTL / 过期。
- CLAW Dream（Light / REM / Deep / Audit）。
- Memory Flush。
- Episode / Project / Knowledge / Relationship Graph / Communication Memory 这几类记忆。
- 向量索引、图索引、MMR 去重。
- 数据库加密（SQLCipher 或等效）、附件 AES-256-GCM。
- 多设备同步。

### 建议排期

1. 先让 V2 表真正被写入：把记忆写入路径收敛到 `saveMemoryV2`，让 Provenance / Evidence / Lineage 开始积累。
2. 建 Memory SDK 门面，禁止各功能直接访问底层表。
3. 加 FTS5，与现有语义排序合并成混合检索。
4. 记忆生命周期：Promotion、冲突处理、陈旧降权、TTL。
5. Memory Flush 与 Standing Intent。
6. CLAW Dream：先做 Light，再做 REM / Deep / Audit。
7. 加密、导出、多设备同步。

## 八、聊天对象档案合并（方向已定）

用户决定：**只保留「助手 → 人物」，删除「设置 → 聊天对象档案」整页。**

### 现状：两套并存

- 「设置 → 聊天对象档案」：`HeartTargetSettingsViewController`（列表）+ `HeartTargetEditViewController`（编辑：头像、姓名、关系、别名、备注）。**有头像选择，没有群聊开关。**
- 「助手 → 人物」：`ClawPeopleView` + `ClawContactEditorView`（姓名/群名、关系、别名、群聊开关、备注）+ `ClawContactDetailView`（设为当前、确认档案、画像、长期记忆、聊天时间线）。**有群聊开关，没有头像编辑。**

### 合并前必须先做的一步

把头像选择搬进「助手 → 人物」的编辑页。否则删掉设置页之后，头像就彻底改不了了。
可参照 `HeartTargetEditViewController` 里现成的 `PHPickerViewController` 实现。

### 需要改动的确切位置

1. 删除整文件：`Packages/HamsteriOS/Sources/UILayer/Settings/HeartTargetSettingsViewController.swift`（列表页 + 编辑页都在里面）。
2. `Packages/HamsteriOS/Sources/ViewModel/Settings/SettingsViewModel.swift` 约 175-182 行：删掉「聊天对象档案」这一项。
3. `Packages/HamsteriOS/Sources/Model/SettingsSubView.swift` 第 64-65 行：删掉 `case heartTargets`。
4. `Packages/HamsteriOS/Sources/UILayer/Main/MainViewController.swift`：协议里的 `makeHeartTargetSettingsViewController()`（约 30 行）、lazy 属性（84-85 行）、`.heartTargets` 分支（201-202 行）、`presentHeartTargetSettingsViewController()`（277-279 行）。
5. `Packages/HamsteriOS/Sources/HamsterAppDependencyContainer.swift` 第 381-383 行：删掉工厂方法。
6. `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift` 第 710 行：删掉"头像更换仍可在设置 → 聊天对象档案中完成"，改成就地选头像。

### 确认过不受影响的地方

- 深链 `hamster://keyboardSettings` 指向键盘设置页，不是这一页，两者无关。
- 删页面不删数据：档案仍存在 App Group 里，`HeartTargetService` 不动。

### 后续可做的档案增强（尚未确认，仅备选）

- 补字段：身份层（电话、微信号、公司职位、邮箱、生日）；关系层（关系类型改为可选项、亲疏、认识来源、共同项目）；沟通层（称呼偏好、语言、语气、回复长度、禁忌话题）；状态层（最近互动摘要、未完成事项）。
- 交互：行内三枚小按钮（设为当前/编辑/删除）收进长按或左滑；删除加二次确认；详情页支持就地编辑；搜索支持拼音与首字母；列表按客户/朋友/家人/群聊分组筛选；详情页增加「未完成事项」区块。
- 身份：支持把两份档案「合并到某人」，把别名、头像、记忆、时间线一并迁移。
- 注意：`HeartTargetService.delete(id:)` 只从列表移除，挂在原 contact ID 下的记忆、聊天时间线、任务会变成孤儿数据，删除流程需要一并处理。

## 九、助手页输入区与图片归档

### 用户明确要求

1. 助手页要有上传文件、截图的选择（现在完全没有）。
2. 输入框改成微信那种样式，语音发送也照微信改。
3. 全局记忆里上传的照片，要自动识别属于哪个联系人；不确定的可以再问用户。
4. **如果已经明确选择了对象再添加截图，就直接针对该对象写入记忆，不再询问、不再自动识别联系人。**

### 现状（已核实）

- 助手页输入行 = 语言菜单（普通话／粤语／English）+ 话筒 + 电话 + `.roundedBorder` 输入框 + 发送箭头，**没有任何附件入口**。
- 主程序里唯一的 `PHPicker` 是人物头像选择；记忆页文件导入只接受 `.plainText / .json / .data / .archive / .folder`，**不认图片**。
- 截图识别管线只在键盘的帮你回面板里：`ClawPanelOverlayView.processScreenshotResults`（私有方法），主程序无法复用。
- 归属判定是"宁可新建也不问"：`ClawScreenshotChatParser.parse` 拿到标题后交给 `ClawContactIdentityResolver.resolve(displayTitle:allowCreate: true)`，`allowCreate: true` 表示匹配不到就直接新建档案。标题识别错一个字、群聊标题、改了昵称，都会多出一个陌生档案。
- 另外键盘面板归档后还会调 `HeartTargetService.select(id:)`，把用户当前选的对象悄悄换掉。

### 要做的改动

附件入口：输入框右侧加 `+`，面板里至少三项——照片／截图、文件、剪贴板。文件项复用 `ClawMemoryDocumentPicker`，但要补 `UTType.image`；照片项复用截图管线。

前置依赖：把截图解析从 `ClawPanelOverlayView` 抽成共享服务（例如 `ClawScreenshotIngestionService`），键盘面板与主程序都调用它。`ClawContactIdentityResolver.resolve` 需要改成返回「候选列表 + 置信度」，现在只返回单个 profile，拿不到候选集，"不确定就问"没有数据基础。

归属规则按两种入口分开：

- **已明确选择对象**（`HeartTargetService` 有选中项且不是全局模式）→ 直接归到该对象，跳过自动识别，不弹选择，界面上给一句"已写入 小王 的记忆"。
- **全局模式**（无选中对象）→ 走高置信直接归档、低置信弹选择器、无法判断保持全局的三档规则；低置信的选项为「归到某人 / 新建人物 / 不归档」。归档后不改变用户当前的对象选择。

输入框改版（可与上面的服务抽取并行）：左侧「语音／键盘」切换圆钮，中间圆角灰底胶囊输入框（多行时最高 4-5 行后内部滚动），右侧 `+`，最右发送；有文字时发送高亮。语音改成微信式「按住 说话」，按住录、松开发送、上滑取消。电话（连续通话）从输入行移出，放进顶部上下文栏或 `+` 面板；语言选择不再占输入行最左位置，改为语音模式下的小标签或长按语音键弹出。

### 顺序

1. 抽截图入库服务 + 身份解析返回候选（这两件是前置）。
2. 助手页 `+` 附件入口（照片／文件）。
3. 归属三档 + 已选对象的定向写入。
4. 输入框微信式改版。

## 十、全局模式的记忆与任务范围不一致

### 现状（已核实）

界面侧：

- 记忆页（记忆中心）用 `ClawMemoryStore.shared.memories(limit: 1_000)` 加载，**不按 scope 过滤**，因此会列出全部记忆，包含各联系人的。
- 人物详情里的"长期记忆"用 `memories(scope: "contact", subjectID: profile.id, limit: 100)`，只看得到该联系人的。

AI 侧（`ClawContextBuilder.build`）：

- 始终取 `scope: "global"` 的记忆（80 条粗筛、40 条排序、渲染 12 条）。
- 只有当前选中对象时才取该对象的 `scope: "contact"` 记忆与最近 32 条聊天时间线；**全局模式下这两项为空**。
- 隐私保险箱内的记忆在 AI 侧再过滤一次，不进入上下文。
- 任务走的是另一套规则：`relevantTasks = contactID == nil ? allTasks : ...`，即**全局模式下会把所有联系人的未完成任务都带进上下文**。

造成的实际割裂：全局模式下问"我还有什么没做完"，它能说出小王、老张的事；问"我答应过小王什么"，它答不上来，因为那条承诺存在小王的记忆里。

### 用户已确认要改，方向如下

不要把全局模式改成"塞入所有人的记忆"，那样会重新引入张冠李戴。改为**定向检索**：从问题里解析人名或关键词，只把命中的那一个联系人的少量相关记忆带进来。

例如问"我答应过小王什么"，只带小王的记忆；问"最近还有什么事要跟进"，按任务与最近互动排序，每人给一条摘要。

### 待用户确认的三点（我的倾向）

1. 全局模式下是否允许携带联系人记忆 → 倾向允许，但只带命中的那一个。
2. 保险箱内被保护的联系人记忆是否仍然一律不带 → 倾向不带。
3. 回答里是否标注来源（例如"以下内容来自 小王的档案"）→ 倾向标注，便于用户判断信息出处。

## 十一、iCloud 同步页两个按钮闪退

现象：设置 → iCloud同步，点「拷贝应用文件至iCloud」和「从 iCloud 恢复」都闪退。

### 根因（已定位）

`Packages/HamsterKit/Sources/Extensions/URL+.swift`：

- `iCloudDocumentURL` 本身是可选，值为 `FileManager.default.url(forUbiquityContainerIdentifier: nil)` 加上 `Documents`；拿不到容器时返回 nil。
- 但下游 `iCloudRimeURL` 用的是**强制解包**：`iCloudDocumentURL!.appendingPathComponent("RIME")`（第 69-71 行）；`iCloudBackupsURL` 同样（第 89-91 行）。
- `iCloudSharedSupportURL` 与 `iCloudUserDataURL` 都建在 `iCloudRimeURL` 上，所以两条路径最终都会踩到这行强制解包。

调用链：`AppleCloudViewModel.copyFileToiCloud()` → `FileManager.copySandboxSharedSupportDirectoryToAppleCloud` → `URL.iCloudSharedSupportURL` → `iCloudRimeURL` → `iCloudDocumentURL!` → 崩溃。`restoreFromiCloud()` 走的是同一条链。

`AppleCloudViewModel` 两个方法都**没有先判断 iCloud 是否可用**。`restoreFromiCloud` 里那句 `_ = URL.iCloudDocumentURL` 只是求值后丢弃，等于没判断。

触发条件：设备未登录 iCloud，或系统里关闭了 iCloud Drive / 该 App 的 iCloud 开关时，`url(forUbiquityContainerIdentifier:)` 返回 nil。

### 两个附带问题

1. `iCloudDocumentURL` 是静态缓存（`static var iCloudDocumentURL: URL? = { ... }()`）。如果首次访问时 iCloud 尚未就绪，nil 会被永久缓存，之后即使登录了 iCloud 也不会恢复，除非重启 App。
2. 拷贝／恢复按钮不检查设置页那个 iCloud 总开关（`settingsViewModel.enableAppleCloud`）。

### 建议修法

1. 去掉强制解包：`iCloudRimeURL` 与 `iCloudBackupsURL` 改为可选或抛错，交由调用方处理。
2. 两个按钮动作前先判断 `URL.iCloudDocumentURL != nil`；为 nil 时给出可读提示——「iCloud 不可用，请先在系统设置登录 iCloud 并打开 iCloud Drive」，而不是崩。
3. `iCloudDocumentURL` 不要永久缓存 nil：改为每次求值，或仅在拿到值时才缓存。
4. 顺带把 `enableAppleCloud` 总开关的判断补上。

## 十二、主程序增加「外观」选项（系统／浅色／深色）

用户要求：主程序设置页增加「外观」，可选 系统 / 浅色 / 深色，位置在「键盘配色」**上面一行**。

### 现状

- 「键盘配色」在 `Packages/HamsteriOS/Sources/ViewModel/Settings/SettingsViewModel.swift` 第 150-158 行，位于 `SettingSectionModel(title: "键盘相关")` 分组内。
- 主程序**目前没有任何外观开关**：全仓库搜不到 `overrideUserInterfaceStyle`；界面颜色走动态色（`UIColor { trait in trait.userInterfaceStyle == .dark ? ... }`），完全跟随系统。

### 实现要点

1. 新项插入到第 150 行之前，复用现成的 `.pullDown` 类型。参考写法见 `Packages/HamsteriOS/Sources/ViewModel/Keyboard/KeyboardSettingsViewModel.swift` 第 1471-1498 行：`type: .pullDown` + `textValue` 显示当前值 + `pullDownMenuActionsBuilder` 返回 `[UIAction]`。图标可用 `circle.lefthalf.filled`。
2. 三个 `UIAction` 分别对应 系统 / 浅色 / 深色，用 `state: .on` 标出当前选中项。
3. 持久化用 `UserDefaults.standard` 即可，这是主程序自己的显示偏好，不必进 App Group。
4. 应用方式是 `window.overrideUserInterfaceStyle = .unspecified / .light / .dark`。主程序是 Scene 架构，窗口在 `SceneDelegate`；切换后要立即生效，可以遍历 `UIApplication.shared.connectedScenes` 取窗口重设，或发通知让 SceneDelegate 统一处理。
5. 启动时必须在 `window.makeKeyAndVisible()` **之前**读取并赋值，否则会先闪一下系统配色再切换过去。

### 键盘也跟随（用户已确认）

决定：选项写进 App Group，键盘扩展启动时自己读取并套用。选「系统」时扩展读到的就是跟随系统，两条进程读同一个键，行为一致。

扩展侧的机制已查清：

- `KeyboardContext.colorScheme` 直接返回 `traitCollection.userInterfaceStyle`（`KeyboardContext.swift` 第 574-576 行），`hasDarkColorScheme` 基于它，键盘上所有配色都从这里派生。
- `KeyboardContext.traitCollection` 是从控制器同步来的：`sync(with:)` 里 `if traitCollection != controller.traitCollection { traitCollection = controller.traitCollection }`（第 787-789 行）。
- 同步入口是 `KeyboardInputViewController.viewWillSyncWithContext()`（第 165-169 行），由 `traitCollectionDidChange` 等触发。

所以扩展侧只需在 `viewDidLoad` / `viewWillAppear` 阶段先读 App Group 的值，给控制器设 `overrideUserInterfaceStyle`（系统 → `.unspecified`，浅色 → `.light`，深色 → `.dark`）。设完会触发 `traitCollectionDidChange`，`viewWillSyncWithContext()` 把新的 traitCollection 同步进 `keyboardContext`，配色随之整体更新。

主程序侧则把选项写进 `UserDefaults(suiteName: HamsterConstants.appGroupName)`，并用自己的窗口设 `overrideUserInterfaceStyle`，两边读同一个键。

建议键名 `claw_appearance_style_v1`，取值 `system` / `light` / `dark`。

### 另外一点

现在这个位置在「键盘相关」分组里，而外观属于整个 App，语义上有点偏。可以顺手把该分组改名，或把外观提到更通用的分组。

## 十三、键盘配色的三个问题

### 1. 设置页显示「启用／禁用」，应该显示选中的配色名

`SettingsViewModel.swift` 第 154 行：

```
navigationLinkLabel: { [unowned self] in self.enableColorSchema ? "启用" : "禁用" }
```

应该改成显示当前配色名（含「系统默认」），例如「红」「黑金」「系统默认」。

### 2. 选「系统默认」不生效，选了还是上一版

根因在于配置是怎么传到键盘扩展的：

- 键盘扩展**不是**从 App Group UserDefaults 读配置，而是从文件读：`KeyboardContext.swift` 第 299-300 行用 `Data(contentsOf: AppGroup/userData/build/hamster.plist)` 解码后赋给 `hamsterConfiguration`。
- 这个赋值**只在 `KeyboardContext` 初始化时发生一次**（第 264 行声明，第 300 行是唯一赋值点）。扩展进程已经在运行时不会重新读。
- 主程序写这份 plist 是异步的：`HamsterConfigurationStore.persistConfiguration` 里用 `Task { saveToUserDefaults + saveToPropertyList }`。

所以选完配色回到键盘时，如果扩展进程还活着，`keyboardContext.hamsterConfiguration` 仍是旧值，键盘和设置页都会显示上一版，直到扩展进程被系统回收重建。

另外还有一个显示层问题：`KeyboardColorViewModel.selectedIndex` 的 getter 在 schema 名解析不出来时返回 0，界面就会显示成「系统默认」，与实际不符。

建议：主程序保存改为同步，或至少等待写入完成；扩展侧在 `viewWillAppear` / `viewDidLayoutSubviews` 里按需重读 plist（带节流）；或者在 App Group 放一个配置版本号，扩展发现版本变化才重载。

### 3. 有的配色没有浅色／深色两种

7 套主题在数据上**都**定义了 light 和 dark 两套 schema（`ClawTalkThemePresets`），但其中两套的浅色变体本身就是深色：

- 黑：浅色变体键盘底 `#1C1C1E`、键帽 `#2C2C2E`
- 黑金：浅色变体键盘底 `#141210`、键帽 `#1F1D1A`

所以这两套在系统浅色模式下依然是黑的，看起来就像"没有浅色版"。

另外 yaml 自带的两套 `solarized_dark`（昼熔月汐）与 `solarized_light`（日光熔金）是**单变体**设计——一套只管深色、一套只管浅色，和 7 套主题的双变体机制不是同一套逻辑，容易混淆。

建议：对确实没有浅色变体的主题在设置页明确标注（例如「黑（仅深色）」），或者补一套真正的浅色变体；同时把 yaml 自带的单变体 schema 与内置主题在 UI 上区分开。

### 3.1 用户已定：补真正的浅色变体（不改用标注方案）

只改「黑」与「黑金」两套的**浅色变体**，深色变体保持原样。色值如下，可直接填入 `ClawTalkThemePresets.preset(for:)` 里对应主题的 `light:` 参数：

黑（`.black`）浅色变体：

- keyboardBackground `#F2F2F7`
- keycapBase `#FFFFFF`
- keycapPressed `#E5E5EA`
- keycapText `#1C1C1E`
- accent `#48484A`
- accentForeground `#FFFFFF`

黑金（`.blackGold`）浅色变体：

- keyboardBackground `#FAF6EC`（暖象牙底）
- keycapBase `#FFFFFF`
- keycapPressed `#F0E8D8`
- keycapText `#2A2419`
- accent `#C9A227`（金）
- accentForeground `#2A2419`（深字压在金底上，与深色变体的取法一致）

实现注意：`KeyboardColorViewModel.applyTheme` 注入 schema 时是按 `schemaName` 先删后加（`removeAll { $0.schemaName == ... }` 再 `append`），所以**已经选过这两个主题的用户**，其配置里还留着旧的 schema 记录，需要重新选一次才会被覆盖。可以接受，也可以改成加载配置时用内置预设覆盖同名 schema。

### 3.2 用户要求：每个主题都必须有可区分的浅色与深色两套

按 `ClawTalkThemePresets` 的现有色值逐主题核对（以键盘底色判断）：

| 主题 | 浅色变体底色 | 深色变体底色 | 判定 |
|---|---|---|---|
| 红 | `#F6F7F9` | `#13151C` | 合格 |
| 白 | `#F2F2F7` | `#1C1C1E` | 合格 |
| 黑 | `#1C1C1E` | `#000000` | **缺浅色** |
| 黑金 | `#141210` | `#000000` | **缺浅色** |
| 海盐蓝 | `#EAF2FA` | `#0E1B2A` | 合格 |
| 森林绿 | `#EEF4EE` | `#0F1D15` | 合格 |
| 樱花粉 | `#FDF1F4` | `#2A151C` | 合格 |

结论：只有「黑」与「黑金」需要补，色值见 3.1。

验收规则（避免以后再出现同名不同色的情况）：每套主题的两个变体必须"底色亮度可区分"——浅色变体的底色亮度要明显高于深色变体。按现有色值，浅色变体底色的相对亮度应大于 0.6，深色变体应小于 0.2。这条可以写成一条单测或校验脚本，在 CI 里对 7 套主题跑一遍。

另外「系统默认」不算主题，它直接回落苹果原生外观、自动跟随系统深浅色，不需要两套色值。

## 十四、主题底色与键盘底部「下巴」颜色不一致

用户反馈：键盘主题的底色和底部那条不一样，接缝处像断层。

### 现状：键盘里有三套互相独立的取色来源

1. **主题色**：`StandardKeyboardAppearance.hamsterColor()` 解析出的 `backColor` / `buttonBackColor`，来自 `KeyboardColorSchema`。键盘本体与根视图用它。
2. **`ClawPanelPalette`**：工具栏、功能行、CLAW 面板用它。它有独立的静态 `activeTheme`，靠 `ClawPanelPalette.sync(with:)` 从 `keyboardContext.hamsterConfiguration` 推导，且只在 `KeyboardToolbarView.setupAppearance()` 与 `ClawPanelOverlayView.refresh(for:)` 里被调用。
3. **`IOSNativePalette.board`**：只在「iOS 原生布局」开启时使用。

关键点：`StandardKeyboardAppearance.backgroundStyle` 里有这样一段

```
if keyboardContext.useIOSNativeLayout {
  style.backgroundColor = IOSNativePalette.current(...).board   // 系统灰
  return style
}
```

也就是**开着 iOS 原生布局时，键盘本体与底部一律用系统灰，主题色不参与**；而工具栏与面板按钮仍走 `ClawPanelPalette` 的主题取色。这种"一半主题色、一半系统色"最容易看出一条断层。

### 底部那条是谁画的

- 控制器侧：`KeyboardInputViewController.syncKeyboardBackgroundColor()` 会把 `view.backgroundColor` 与 `inputView?.backgroundColor` 一起设成当前底色（原生布局 → `IOSNativePalette.board`；否则 → `backgroundStyle.backgroundColor`，即主题 `backColor`）。
- 根视图：`KeyboardRootView.setupAppearance()` 按同样规则取色。
- 原生布局下最后一排按键只留 `metrics.bottomKeyInset`（有 Home Indicator 时 4pt）贴底，所以那条细缝显示的是 `IOSNativeKeyboardView.backgroundColor`，也就是 `palette.board`。

### 建议改法：单点取色 + 变化时主动刷新

1. 抽一个单点取色函数，例如 `currentKeyboardBoardColor(context)`，按"是否原生布局 + 是否启用主题 + 深浅色"返回唯一色值。
2. 让 `StandardKeyboardAppearance.backgroundStyle`、`KeyboardRootView.setupAppearance`、`IOSNativeKeyboardView` 的 `backgroundColor`、`syncKeyboardBackgroundColor()` 四处都走这个函数，避免各自取色。
3. 主题切换或深浅色变化时主动调用一次 `syncKeyboardBackgroundColor()`，不要只依赖 `viewWillSyncWithContext()` 的被动触发。
4. 若希望"原生布局也吃主题色"（断层会自然消失），就把原生布局分支里的 `board` 从 `IOSNativePalette.board` 换成主题底色；若想保持系统灰，则要保证工具栏与面板在该路径下也不使用主题色。

### 需要用户确认两点

1. 现在「iOS 原生布局」是开还是关——两条路径的修法不同。
2. 断层位置是候选栏／功能行与键盘之间，还是最后一排按键下面那条细缝。

### 用户已澄清：关掉 iOS 原生布局时，是"按键缝隙的底色"

所以问题是：按键之间的缝隙显示的颜色，和底部那条不一致。

缝隙的颜色来自哪里（已核实）：

- `StanderSystemKeyboard.setupAppearance()` 里是 `backgroundColor = .clear`，键盘本体透明。
- 因此缝隙显示的是它背后的 `KeyboardRootView` 背景，而它取自 `appearance.backgroundStyle.backgroundColor`，也就是主题的 `backColor`。
- 底部那条则由控制器另设：`KeyboardInputViewController.syncKeyboardBackgroundColor()` 会把 `view.backgroundColor` 与 `inputView?.backgroundColor` 设成同一个底色。

两处各设一次，就是断层能出现的原因。最可能的两种情形：

1. **主题切换后没有重新调用 `syncKeyboardBackgroundColor()`**。控制器 `view` / `inputView` 还是旧色，而键盘根视图已经用了新主题色——缝隙是新色、下巴是旧色。
2. **`ClawPanelPalette` 这个静态全局晚一拍**。它的 `activeTheme` 只在 `KeyboardToolbarView.setupAppearance()` 与 `ClawPanelOverlayView.refresh(for:)` 两处被同步（另外 `hamsterColor()` 会顺手更新它），而 `KeyboardToolbarView` 是直接读 `ClawPanelPalette.toolbarBackground` 的。若工具栏先构建、配置后到，工具栏与候选栏就会停在系统色，而键盘本体已是主题色。

补充修法（在第十四节通用方案之外）：主题或深浅色变化时，要同时做三件事——刷新 `ClawPanelPalette.sync(with:)`、重新调用 `syncKeyboardBackgroundColor()`、并让根视图重跑一次 `setupAppearance()`。只做其中一件仍会留下接缝。

### 底部那条能不能改？——先做一次验证

第三方键盘的整个区域（含底部那条）理论上都在扩展的 `inputView` 内，扩展可以自己涂色，这也是搜狗、Gboard 的主题色能一路贯到底部的原因。只有一种情况改不了：扩展的视图没铺满系统分配的键盘区域，剩下的部分由系统用默认底色补。

验证方法（一次即可定性）：在键盘扩展里把 `view.backgroundColor` 临时设成一个刺眼的颜色（例如纯红），重新打开键盘看底部那条是否也变红。

- 变红 → 那块属于扩展，能改，问题只是取色没统一，按本节方案修即可。
- 不变 → 那块不在扩展视图内，只能保证扩展自身铺满，颜色由系统决定。

### 用户已定方案：底部做渐变过渡，不追求改掉下巴

用户判断下巴那块改不了，于是提出：让主题底色在键盘最底部**渐变过渡**到下巴的颜色，这样不会出现一条生硬的分界线。这个方案可行，记录如下。

做法：在键盘最底部叠一层竖直渐变，高度取底部安全区（`view.safeAreaInsets.bottom`，为 0 时用 8-12pt 常量），从上到下：

- 顶部色 = 当前主题的 `backColor`（与缝隙同色）
- 底部色 = 近似系统键盘底色

底层视图用 `CAGradientLayer`，`isUserInteractionEnabled = false`，插在背景层之上、按键之下，避免挡到最后一排按键。

近似系统底色的取值（代码里已有现成常量，不必新调色）：

- 亮色：`#D1D4DA`（`IOSNativePalette.board` 亮色）或 `#D1D4D9`（`ClawPanelThemeColors.system` 亮色）
- 暗色：`#1C1C1E`（`IOSNativePalette.board` 暗色）或 `#17181A`（`ClawPanelThemeColors.system` 暗色）

用哪个变体可以顺着系统走，也可以用 `keyboardContext.keyboardAppearance`（取自宿主 App 的 `textDocumentProxy.keyboardAppearance`）判断，那个更接近系统实际渲染的键盘背景。

注意事项：

1. 渐变层的两个色值必须跟随主题与深浅色变化一起刷新，否则会和第十四节的接缝问题一样留下不同步。
2. 渐变只负责"消除硬边"。如果下巴真实颜色与我们的近似值差得较多，接缝会从"硬线"变成"轻微色差"，不会再突兀，但也不会完全消失。
3. 高度不要太大，8-14pt 足够；过高会让键盘底部看起来发虚。
