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
  }
}

// MARK: - SwiftUI View

struct LogRootView: View {
  @State private var entries: [String] = []
  @State private var showShareSheet = false

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
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarTrailing) {
        // 分享（TXT）
        Button {
          showShareSheet = true
        } label: {
          Image(systemName: "square.and.arrow.up")
        }

        // 清除
        Button(role: .destructive) {
          LogService.shared.clear()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reload() }
        } label: {
          Image(systemName: "trash")
        }
      }
    }
    .sheet(isPresented: $showShareSheet) {
      LogShareSheet(text: LogService.shared.exportText())
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

// MARK: - ShareSheet

private struct LogShareSheet: UIViewControllerRepresentable {
  let text: String
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let url = Self.writeTemporaryTXT(text: text)
    return UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}

  /// 日志文本写入临时 .txt 文件（微信等 App 只能接收文件），文件名带时间戳避免同名缓存
  private static func writeTemporaryTXT(text: String) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: Date())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClawTalk-调试日志-\(stamp).txt")
    try? text.data(using: .utf8)?.write(to: url)
    return url
  }
}
