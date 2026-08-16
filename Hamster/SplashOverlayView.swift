//
//  SplashOverlayView.swift
//  ClawTalk brand splash overlay
//
//  与 LaunchScreen.storyboard 视觉一致：主界面首帧后盖一层，
//  波形条呼吸动画，1.5s 后淡出。

import UIKit

final class SplashOverlayView: UIView {
  private let brandRed = UIColor(red: 198 / 255, green: 62 / 255, blue: 56 / 255, alpha: 1)
  private let darkBg = UIColor(red: 11 / 255, green: 12 / 255, blue: 17 / 255, alpha: 1)
  private let grayText = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
  private var bars: [UIView] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = darkBg
    setupViews()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    let logo = UIImageView(image: UIImage(named: "ClawTalkLogo"))
    logo.contentMode = .scaleAspectFit
    logo.translatesAutoresizingMaskIntoConstraints = false
    addSubview(logo)

    let title = UILabel()
    title.text = "ClawTalk"
    title.font = .systemFont(ofSize: 26, weight: .bold)
    title.textColor = .white
    title.textAlignment = .center
    title.translatesAutoresizingMaskIntoConstraints = false
    addSubview(title)

    let barContainer = UIView()
    barContainer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(barContainer)
    let heights: [CGFloat] = [8, 16, 24, 16, 8]
    var lastBar: UIView?
    for h in heights {
      let bar = UIView()
      bar.backgroundColor = brandRed
      bar.layer.cornerRadius = 2
      bar.translatesAutoresizingMaskIntoConstraints = false
      barContainer.addSubview(bar)
      NSLayoutConstraint.activate([
        bar.widthAnchor.constraint(equalToConstant: 4),
        bar.heightAnchor.constraint(equalToConstant: h),
        bar.centerYAnchor.constraint(equalTo: barContainer.centerYAnchor),
      ])
      if let lastBar {
        bar.leadingAnchor.constraint(equalTo: lastBar.trailingAnchor, constant: 4).isActive = true
      } else {
        bar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor).isActive = true
      }
      lastBar = bar
      bars.append(bar)
    }
    if let lastBar {
      NSLayoutConstraint.activate([
        barContainer.trailingAnchor.constraint(equalTo: lastBar.trailingAnchor),
        barContainer.heightAnchor.constraint(equalToConstant: 24),
      ])
    }

    let footer = UILabel()
    footer.text = "ClawTalk — 语音优先的 OpenClaw 移动客户端"
    footer.font = .systemFont(ofSize: 15)
    footer.textColor = grayText
    footer.textAlignment = .center
    footer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(footer)

    NSLayoutConstraint.activate([
      logo.widthAnchor.constraint(equalToConstant: 140),
      logo.centerXAnchor.constraint(equalTo: centerXAnchor),
      logo.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
      title.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 16),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      barContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
      barContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      footer.centerXAnchor.constraint(equalTo: centerXAnchor),
      safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: 28),
    ])
  }

  /// 启动波形条呼吸动画（scaleY，不与 Auto Layout 冲突）
  private func startWaveAnimation() {
    for (index, bar) in bars.enumerated() {
      let scale = CABasicAnimation(keyPath: "transform.scale.y")
      scale.fromValue = 1
      scale.toValue = 1.4 + CGFloat(index % 3) * 0.25
      scale.duration = 0.6 + Double(index) * 0.08
      scale.autoreverses = true
      scale.repeatCount = .infinity
      bar.layer.add(scale, forKey: "wave")
    }
  }

  /// 展示并自动淡出（1.5s）
  func presentAndDismiss(in container: UIView, duration: TimeInterval = 1.5) {
    frame = container.bounds
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(self)
    startWaveAnimation()
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
      UIView.animate(withDuration: 0.3, animations: {
        self?.alpha = 0
        self?.transform = CGAffineTransform(translationX: 0, y: -8)
      }, completion: { _ in
        self?.removeFromSuperview()
      })
    }
  }
}