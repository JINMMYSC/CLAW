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
