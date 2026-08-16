//
//  InputSchemaRootView.swift
//
//
//  Created by morse on 2023/7/8.
//

import Combine
import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

class InputSchemaRootView: NibLessView {
  // MARK: properties

  private static let cellIdentifier = "InputSchemaTableCell"

  private let inputSchemaViewModel: InputSchemaViewModel

  private var subscriptions = Set<AnyCancellable>()

  let tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: InputSchemaRootView.cellIdentifier)
    return tableView
  }()

  // MARK: methods

  init(frame: CGRect = .zero, inputSchemaViewModel: InputSchemaViewModel) {
    self.inputSchemaViewModel = inputSchemaViewModel

    super.init(frame: frame)

    constructViewHierarchy()
    activateViewConstraints()

    inputSchemaViewModel.reloadTableStatePublisher
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] _ in
        updateEmptyState()
        tableView.reloadData()
      }
      .store(in: &subscriptions)
  }

  /// 列表为空时显示占位提示（数据仍来自 rimeContext.schemas，仅提示不造假数据）
  private func updateEmptyState() {
    if inputSchemaViewModel.rimeContext.schemas.isEmpty {
      let label = UILabel()
      label.text = "暂无输入方案\n可在右上角 + 号导入方案，或到 RIME 页面重新部署"
      label.textAlignment = .center
      label.textColor = .secondaryLabel
      label.numberOfLines = 0
      label.font = .systemFont(ofSize: 14)
      tableView.backgroundView = label
    } else {
      tableView.backgroundView = nil
    }
  }

  override func constructViewHierarchy() {
    addSubview(tableView)
    tableView.delegate = self
    tableView.dataSource = self
  }

  override func activateViewConstraints() {
    tableView.fillSuperview()
  }
}

extension InputSchemaRootView: UITableViewDataSource {
  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    inputSchemaViewModel.rimeContext.schemas.count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    let schema = inputSchemaViewModel.rimeContext.schemas[indexPath.row]

    var config = UIListContentConfiguration.cell()
    config.text = schema.schemaName
    cell.contentConfiguration = config
    cell.accessoryType = inputSchemaViewModel.rimeContext.selectSchemas.contains(schema) ? .checkmark : .none

    return cell
  }
}

extension InputSchemaRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    Task {
      do {
        let schema = inputSchemaViewModel.rimeContext.schemas[indexPath.row]
        try await inputSchemaViewModel.checkboxForInputSchema(schema)
      } catch {
        ProgressHUD.failed(error.localizedDescription, delay: 1.5)
      }
    }
  }
}
