# CLAW 待办（第二轮收集，用户口述）

> 记录时间：2026-10-07。与 `2026-10-07-claw-open-issues-from-user.md` 配套；那一份是更早的 21 节清单，这一份是本轮新增与仍未完成的项。
> 用户说明：先记录，晚点一起做。

## 一、候选栏展开后仍然只有一行

- 用户实测：点候选词右侧带竖线的展开箭头后，键盘上方**出现了一大片空白**，但候选词仍是一行。
- 说明高度已经给了（`KeyboardToolbarView` 的展开约束生效），问题在候选视图没有换成多行布局。
- 候选视图本身有横向/纵向两套布局：`CandidateWordsCollectionView` 里 `horizontalLayout`（单行横滑）与 `verticalLayout`（纵向多行），由 `keyboardContext.candidatesViewState` 驱动 `changeLayout(_:)` 切换。
- 已加的兜底（本地提交 `dd472ba`，尚未推送）：在 `layoutSubviews` 里发现自身状态与上下文不一致时强制 `changeLayout`。
- 若兜底仍无效，下一个排查点是纵向布局下的 item 宽度计算（`sizeForItemAt` 中 `isVerticalLayout` 分支）以及候选数量是否太少导致视觉上仍像一行。

## 二、外观那一行点不进去

- 现象：设置里「外观」这一行，点整行没有反应，进不去选择。
- 根因：`PullDownMenuCell` 只把菜单挂在右侧数值按钮上——
  `valueButton.menu = UIMenu(children: actions)` 且 `valueButton.showsMenuAsPrimaryAction = true`，
  点左侧文字区域不触发。
- 影响范围：不只「外观」，`键盘设置 → 按键 → 划动方向 / 划动操作` 同样是这个毛病。
- 建议改法（倾向）：让 `valueButton` 铺满整行（文字仍靠右），这样点哪里都能弹菜单，一次修好所有下拉行。
- 备选：把「外观」改成和「键盘配色」一样的跳转页，里面放三个选项。

## 三、iCloud 提示不可用（根因已定位到签名）

- 现象：点「拷贝应用文件至 iCloud」提示「iCloud 不可用，请在系统设置中登录 iCloud 并打开 iCloud Drive」；但系统设置里 iCloud 早已登录，而且"使用 iCloud 的 App"列表里根本没有 CLAW。
- 证据：从已签名 IPA 里解出的 `Payload/Hamster.app/embedded.mobileprovision` 中，
  `com.apple.developer.icloud-container-identifiers` 与
  `com.apple.developer.icloud-container-development-container-identifiers`
  **都是空数组**；代码里请求的容器 `iCloud.dev.fuxiao.app.hamsterapp` 在配置文件里不存在。
- 结论：重签名用的描述文件没有包含 iCloud 容器权限，所以系统不授予任何容器，`url(forUbiquityContainerIdentifier:)` 返回 nil，App 也就不出现在 iCloud 的 App 列表里。**不是用户设置问题。**
- 修法：换一份带 iCloud 容器的描述文件重新签名（App ID 需勾选 iCloud/CloudKit + iCloud Documents，且容器名要与代码一致），更新 CI 里的 `PROFILE_MAIN_B64`；或在修好前先隐藏这两个按钮并给出准确提示。
- 已有代码改动：iCloud 不可用时不再闪退，改为抛出可读错误（提交 `f3f73b2`）。

## 四、报错不进调试日志

- 现象一：键盘语音报错「语音识别失败，未能完成操作。（com.apple.coreaudio.avfaudio 错误 2003329396）」，日志里没有。
  原因：`ClawVoiceInputService` **完全没有调用任何日志接口**，错误只通过回调交给界面显示。
- 现象二：iCloud 失败提示也不在日志里。
  原因：那条走的是 `Logger.statistics.error(...)`（OSLog），进系统日志而不是 `ClawTalk-调试日志` 文件。
- 现状：`LogService` 写在 **App Group** 容器里，所以理论上主程序与键盘扩展都能写入；问题是绝大多数模块没调用它。
- 待做：统一错误落日志——语音服务、iCloud、以及各模块 catch 分支都改成走 `LogService`，并补一个 error 级别与统一格式，便于用户导出后排查。

## 五、助手页输入框改微信式 + 附件入口（未开始）

- 输入框：左侧「语音／键盘」切换圆钮，中间圆角灰底胶囊输入框（多行时内部滚动），右侧 `+`，最右发送按钮；语音改成微信式「按住说话」：按住录、松开发送、上滑取消。
- 附件入口：照片/截图、文件、剪贴板。
- 前置依赖一：把截图识别从 `ClawPanelOverlayView.processScreenshotResults` 抽成共享服务，否则主程序调不到。
- 前置依赖二：`ClawMemoryDocumentPicker` 目前只接受 `.plainText/.json/.data/.archive/.folder`，要补图片类型。

## 六、设置里增加重置功能（本轮新增，用户已确认规则）

用户要求：设置里要有一个重置按钮，能把 App 重置成"像刚装的一样"。

已确认的三条规则：

1. **API Key 保留**——只重置数据与学习，不要求用户重新填 Key。
2. **需要二次确认**，且确认文案要写清"会删什么、会保留什么"，因为不可撤销。
3. **额外提供轻量选项「只重置输入法学习」**——只清 RIME 的用户词典与调频规则，不动记忆、人物、任务、会话。

完整重置应覆盖：

- CLAW 数据：长期记忆、聊天时间线、任务/承诺、人物档案、Skill 与反馈、键盘输入记录、剪贴板记录、会话历史、语音与外观设置、隐私保险箱内容。
- RIME 学习：用户词典（userdb）、自造词、智能调频写的规则文件，随后重新部署使输入方案回到内置状态。
- 配置：所有设置项回到默认值。

轻量重置只需覆盖上面第二条。

现成可复用的入口：`HamsterConfigurationStore.reset()`、`ClawTalkDataService.deleteAllEntries()`、`SmartFreqService.resetAllRules()`、`RimeContext.restRime()`。

### 位置与形态（用户已定）

放在**「关于」页最底部**，单独一段，标题「数据与重置」，里面两行：

- 「重置输入法学习」——普通文字色
- 「重置 App」——红色文字

两行各自弹一个二次确认，确认文案要写明"会删除什么 / 会保留什么（API Key、输入方案文件）"。

实现注意：执行完成后（完整重置会重置配置并触发重新部署）界面要跳回设置首页或当场刷新，否则用户停在关于页看不到任何变化。执行顺序建议为：停止 RIME → 清数据 → 清学习 → 重置配置 → 重新部署；中途失败要把已完成的部分报告出来，不要静默中断。
