import SwiftUI
import UIKit

extension View {
  /// Dismisses the software keyboard on a background tap or interactive scroll.
  /// The simultaneous gesture leaves buttons, links, and form controls responsive.
  @ViewBuilder
  func clawKeyboardDismissal() -> some View {
    if #available(iOS 16.0, *) {
      scrollDismissesKeyboard(.interactively)
        .modifier(ClawBackgroundKeyboardDismissalModifier())
    } else {
      modifier(ClawBackgroundKeyboardDismissalModifier())
        .background(ClawScrollKeyboardDismissalConfigurator())
    }
  }
}

private struct ClawBackgroundKeyboardDismissalModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.simultaneousGesture(
      TapGesture().onEnded {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder),
          to: nil,
          from: nil,
          for: nil
        )
      }
    )
  }
}

/// SwiftUI gained `scrollDismissesKeyboard` in iOS 16. Configure the backing
/// scroll view directly on iOS 15 so the interaction stays consistent.
private struct ClawScrollKeyboardDismissalConfigurator: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    DispatchQueue.main.async { configureNearestScrollView(from: view) }
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async { configureNearestScrollView(from: uiView) }
  }

  private func configureNearestScrollView(from view: UIView) {
    if let window = view.window {
      configureScrollViews(in: window)
      return
    }
    var candidate = view.superview
    while let current = candidate {
      if let scrollView = current as? UIScrollView {
        scrollView.keyboardDismissMode = .interactive
        return
      }
      candidate = current.superview
    }
  }

  private func configureScrollViews(in view: UIView) {
    if let scrollView = view as? UIScrollView {
      scrollView.keyboardDismissMode = .interactive
    }
    view.subviews.forEach(configureScrollViews)
  }
}
