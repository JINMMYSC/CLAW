//
//  ClawKeyboardSimulatorViewController.swift
//
//  ClawTalk 键盘模拟演示页（UIKit 容器，承载 SwiftUI 模拟键盘）
//

import HamsterUIKit
import SwiftUI
import UIKit

class ClawKeyboardSimulatorViewController: NibLessViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "键盘模拟演示"

    let hostingController = UIHostingController(rootView: ClawKeyboardSimulatorView())
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
}
