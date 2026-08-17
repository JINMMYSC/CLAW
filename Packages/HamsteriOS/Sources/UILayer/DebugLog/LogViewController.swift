import HamsterKit
import SwiftUI
import UIKit

public class LogViewController: UIViewController {
  public override func viewDidLoad() {
    super.viewDidLoad()
    title = "调试日志"
    let hosting = UIHostingController(rootView: LogRootView())
    addChild(hosting)
    view.addSubview(hosting.view)
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
      hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    hosting.didMove(toParent: self)

    // FIX-HMSTR-031b：SwiftUI .toolbar 嵌在 UIKit 容器子 VC 时不会桥接到导航栏（030 的「复制全部」看不到就是此因），
    // 分享/清除按钮直接放 UIKit navigationItem，与 RIME 日志页一致
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        barButtonSystemItem: .action,
        target: self,
        action: #selector(shareLogs(_:))
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "trash"),
        style: .plain,
        target: self,
        action: #selector(clearLogs(_:))
      ),
    ]
  }

  /// 分享日志为 .txt 文件（微信等 App 只能接收文件），文件名带时间戳避免同名缓存
  @objc private func shareLogs(_ sender: UIBarButtonItem) {
    let text = LogService.shared.exportText()
    guard !text.isEmpty else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: Date())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClawTalk-调试日志-\(stamp).txt")
    try? text.data(using: .utf8)?.write(to: url)
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.barButtonItem = sender
    }
    present(activity, animated: true)
  }

  /// 清除日志（带确认弹窗），完成后通知 SwiftUI 列表刷新
  @objc private func clearLogs(_ sender: UIBarButtonItem) {
    let alert = UIAlertController(title: "清除日志", message: "确定删除全部调试日志？", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
      LogService.shared.clear()
      NotificationCenter.default.post(name: .clawDebugLogCleared, object: nil)
    })
    present(alert, animated: true)
  }
}

extension Notification.Name {
  static let clawDebugLogCleared = Notification.Name("clawDebugLogCleared")
}

// MARK: - SwiftUI View

struct LogRootView: View {
  @State private var entries: [String] = []

  var body: some View {
    Group {
      if entries.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "text.magnifyingglass")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("暂无日志")
            .font(.title3)
            .foregroundColor(.secondary)
          Text("AI 请求发出后，日志将显示在这里。")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(entries, id: \.self) { line in
          Text(line)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(lineColor(line))
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .textSelection(.enabled)
        }
        .listStyle(.plain)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onReceive(NotificationCenter.default.publisher(for: .clawDebugLogCleared)) { _ in
      reload()
    }
    .onAppear { reload() }
  }

  private func reload() {
    entries = LogService.shared.entries()
  }

  private func lineColor(_ line: String) -> Color {
    if line.contains("[ERROR]") { return .red }
    if line.contains("[WARN]")  { return .orange }
    return .primary
  }
}
