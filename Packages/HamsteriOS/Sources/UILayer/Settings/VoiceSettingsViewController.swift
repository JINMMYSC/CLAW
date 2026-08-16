//
//  VoiceSettingsViewController.swift
//  语音设置页（Edge TTS）：音色 / 语速 / 音调 / 试听
//
//  - 音色：晓晓 / 小艺 / 云希 / 云扬（Edge 免费非官方接口）
//  - 语速/音调：-50...50 映射到 Edge TTS 参数，持久化到 App Group
//  - 试听：直接调用 ClawEdgeTTSService 合成播放，失败自动降级系统语音
//

import HamsterKit
import UIKit

/// 语音设置页（设置 → 键盘相关 → 语音设置）
public final class VoiceSettingsViewController: UITableViewController {
  private struct VoiceOption {
    let title: String
    let name: String
    let desc: String
  }

  private let voices: [VoiceOption] = [
    VoiceOption(title: "晓晓（女）", name: "zh-CN-XiaoxiaoNeural", desc: "温暖女声，默认音色"),
    VoiceOption(title: "小艺", name: "zh-CN-XiaoyiNeural", desc: "年轻女声"),
    VoiceOption(title: "云希（男）", name: "zh-CN-YunxiNeural", desc: "阳光男声"),
    VoiceOption(title: "云扬（男）", name: "zh-CN-YunyangNeural", desc: "沉稳男声"),
  ]

  private let tts = ClawEdgeTTSService.shared
  private let previewText = "你好，我是 ClawTalk 语音助手。音色、语速、音调都可以在这里调整。"

  private let rateSlider = UISlider()
  private let pitchSlider = UISlider()
  private let rateLabel = UILabel()
  private let pitchLabel = UILabel()

  public init() {
    super.init(style: .insetGrouped)
    title = "语音设置"
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "slider")
    setupSliders()
  }

  deinit {
    tts.stop()
  }

  private func setupSliders() {
    rateSlider.minimumValue = -50
    rateSlider.maximumValue = 50
    rateSlider.value = Float(tts.ratePercent)
    rateSlider.addTarget(self, action: #selector(rateChanged(_:)), for: .valueChanged)
    pitchSlider.minimumValue = -50
    pitchSlider.maximumValue = 50
    pitchSlider.value = Float(tts.pitchHz)
    pitchSlider.addTarget(self, action: #selector(pitchChanged(_:)), for: .valueChanged)
    updateSliderLabels()
  }

  private func updateSliderLabels() {
    let rate = tts.ratePercent
    rateLabel.text = rate == 0 ? "标准" : (rate > 0 ? "+\(rate)%" : "\(rate)%")
    let pitch = tts.pitchHz
    pitchLabel.text = pitch == 0 ? "标准" : (pitch > 0 ? "+\(pitch)Hz" : "\(pitch)Hz")
  }

  @objc private func rateChanged(_ sender: UISlider) {
    tts.ratePercent = Int(sender.value.rounded())
    sender.value = Float(tts.ratePercent)
    updateSliderLabels()
  }

  @objc private func pitchChanged(_ sender: UISlider) {
    tts.pitchHz = Int(sender.value.rounded())
    sender.value = Float(tts.pitchHz)
    updateSliderLabels()
  }

  @objc private func previewTapped() {
    tts.speak(previewText)
  }

  public override func numberOfSections(in tableView: UITableView) -> Int { 3 }

  public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch section {
    case 0: return "音色"
    case 1: return "语速与音调"
    default: return "试听"
    }
  }

  public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return voices.count
    case 1: return 2
    default: return 1
    }
  }

  public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    switch indexPath.section {
    case 0:
      let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "voiceCell")
      let voice = voices[indexPath.row]
      cell.textLabel?.text = voice.title
      cell.detailTextLabel?.text = voice.desc
      cell.accessoryType = tts.voice == voice.name ? .checkmark : .none
      cell.selectionStyle = .default
      return cell
    case 1:
      let cell = tableView.dequeueReusableCell(withIdentifier: "slider", for: indexPath)
      cell.textLabel?.text = nil
      cell.detailTextLabel?.text = nil
      cell.accessoryType = .none
      cell.selectionStyle = .none
      cell.contentView.subviews.forEach { $0.removeFromSuperview() }
      let container = UIStackView()
      container.axis = .vertical
      container.spacing = 4
      let header = UIStackView()
      header.axis = .horizontal
      header.distribution = .equalSpacing
      let title = UILabel()
      title.font = .preferredFont(forTextStyle: .subheadline)
      title.text = indexPath.row == 0 ? "语速" : "音调"
      let value = indexPath.row == 0 ? rateLabel : pitchLabel
      value.font = .preferredFont(forTextStyle: .subheadline)
      value.textColor = .secondaryLabel
      let slider = indexPath.row == 0 ? rateSlider : pitchSlider
      header.addArrangedSubview(title)
      header.addArrangedSubview(value)
      container.addArrangedSubview(header)
      container.addArrangedSubview(slider)
      container.translatesAutoresizingMaskIntoConstraints = false
      cell.contentView.addSubview(container)
      NSLayoutConstraint.activate([
        container.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
        container.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
        container.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
        container.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
      ])
      return cell
    default:
      let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
      cell.textLabel?.text = "播放试听"
      cell.textLabel?.textColor = .systemBlue
      cell.detailTextLabel?.text = nil
      cell.accessoryType = .none
      return cell
    }
  }

  public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch indexPath.section {
    case 0:
      let voice = voices[indexPath.row]
      tts.voice = voice.name
      tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    default:
      previewTapped()
    }
  }

  public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    section == 2 ? "试听使用 Edge TTS 在线合成，无网络时自动降级为系统语音。" : nil
  }
}
