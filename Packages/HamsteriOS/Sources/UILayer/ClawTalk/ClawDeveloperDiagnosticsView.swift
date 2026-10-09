import HamsterKit
import SwiftUI
import UIKit

/// DEBUG-only destination linked from Settings. No new root tab and no
/// keyboard button; diagnostics cannot reintroduce overlapping navigation.
struct ClawDeveloperDiagnosticsView: View {
  @State private var capture: ClawDiagnosticCapture?
  @State private var exportURL: URL?
  @State private var showingShare = false
  @State private var showingExportError = false

  var body: some View {
    List {
      Section("进程状态 · 只读") {
        if let capture {
          Text("主程序记录：\(capture.hostState.rawValue)")
          Text("键盘快照：\(capture.keyboardState.rawValue)")
          Text("事件：\(capture.events.count) 条")
          Text("异常现场：\(capture.incidents.count) 条")
          Text("读取时间：\(capture.capturedAt.formatted())")
            .foregroundColor(.secondary)
        } else {
          Text("尚未检查").foregroundColor(.secondary)
        }
        Button("刷新本地诊断") {
          capture = ClawDiagnosticsCaptureService.captureCurrent()
        }
      }

      Section("最近异常") {
        if let capture, !capture.incidents.isEmpty {
          ForEach(0..<min(capture.incidents.count, 20), id: \.self) { index in
            let item = capture.incidents[capture.incidents.count - min(capture.incidents.count, 20) + index]
            VStack(alignment: .leading, spacing: 4) {
              Text(item.failureModule + " / " + item.failureAction)
                .font(.subheadline.weight(.medium))
              Text("错误域：\(item.errorDomain ?? "未知")；代码：\(item.errorCode.map(String.init) ?? "未知")")
                .font(.caption).foregroundColor(.secondary)
              Text(item.observedAt.formatted())
                .font(.caption2).foregroundColor(.secondary)
            }
          }
        } else {
          Text("当前没有可用异常记录，不代表所有功能正常。")
            .foregroundColor(.secondary)
        }
      }

      Section("诊断包") {
        Button("导出脱敏诊断 ZIP") { export() }
        Text("仅包含可审核的诊断字段，不包含聊天、输入、语音转写、剪贴板正文、联系人或密钥；不会自动上传。")
          .font(.footnote).foregroundColor(.secondary)
        Text("键盘状态表示最后一次保存的事件，不表示扩展现在一定在运行。系统崩溃报告需另行获取。")
          .font(.footnote).foregroundColor(.secondary)
      }
    }
    .navigationTitle("开发者诊断")
    .onAppear {
      capture = ClawDiagnosticsCaptureService.captureCurrent()
    }
    .sheet(isPresented: $showingShare) {
      if let exportURL {
        ClawDiagnosticsShareController(url: exportURL)
      }
    }
    .alert("导出诊断包失败", isPresented: $showingExportError) {
      Button("知道了", role: .cancel) {}
    } message: {
      Text("请检查设备剩余空间，已存储的个人数据未被更改。")
    }
  }

  private func export() {
    do {
      let latest = ClawDiagnosticsCaptureService.captureCurrent()
      capture = latest
      exportURL = try ClawDiagnosticsCaptureService.exportZip(capture: latest)
      showingShare = true
    } catch {
      showingExportError = true
    }
  }
}

private struct ClawDiagnosticsShareController: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
