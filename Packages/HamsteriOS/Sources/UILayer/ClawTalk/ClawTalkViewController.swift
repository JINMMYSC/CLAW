import HamsterKit
import HamsterUIKit
import SwiftUI
import UIKit

public final class ClawTalkViewController: NibLessViewController {
  private let viewModel = ClawTalkViewModel()

  public override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // The five-tab SwiftUI home owns its navigation chrome. Do not stack the
    // old UIKit "Now ClawTalk" bar above the new app's tabs and page headers.
    navigationController?.setNavigationBarHidden(true, animated: false)
    ClawDiagnosticsCore.shared.record(module: "ui", action: "assistant_home_appeared")
  }

  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Legacy settings and RIME routes still use a normal back button.
    navigationController?.setNavigationBarHidden(false, animated: false)
    ClawDiagnosticsCore.shared.record(module: "ui", action: "assistant_home_disappeared")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    title = "Now ClawTalk"

    let hostingController = UIHostingController(rootView: ClawAssistantRootView(viewModel: self.viewModel))
    addChild(hostingController)
    view.addSubview(hostingController.view)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    hostingController.didMove(toParent: self)
  }

#if DEBUG
  private var screenshotReadinessChecks = 0

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard ClawComposerScreenshotFixture.state != nil else { return }
    verifyScreenshotComposerReady()
  }

  private func verifyScreenshotComposerReady() {
    guard let state = ClawComposerScreenshotFixture.state else { return }
    view.layoutIfNeeded()
    if let bar = findComposerBar(in: view), bar.bounds.width > 100, bar.bounds.height >= 50 {
      // Emit readiness from the UIKit view tree after the actual composer is
      // mounted. SwiftUI onAppear alone can be deferred during first deploy.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        FileHandle.standardError.write(Data("[clawComposer] screenshot ready: \(state)\n".utf8))
      }
    } else if screenshotReadinessChecks < 45 {
      screenshotReadinessChecks += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.verifyScreenshotComposerReady()
      }
    }
  }

  private func findComposerBar(in root: UIView) -> ClawChatComposerBar? {
    if let bar = root as? ClawChatComposerBar { return bar }
    for child in root.subviews {
      if let found = findComposerBar(in: child) { return found }
    }
    return nil
  }
#endif
}
