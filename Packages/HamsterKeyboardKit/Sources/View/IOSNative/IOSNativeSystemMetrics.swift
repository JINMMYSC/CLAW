//
//  IOSNativeSystemMetrics.swift
//
//  Central calibration surface for the existing iOS-native keyboard mode.
//  Geometry may expand with the device, while typography and symbol point sizes stay stable.
//

import CoreGraphics

struct IOSNativeSystemMetrics {
  let viewWidth: CGFloat
  let safeAreaBottom: CGFloat

  private var horizontalEdge: CGFloat {
    if viewWidth >= 428 { return 4 }
    if viewWidth >= 390 { return 3.5 }
    return 3
  }

  private var referenceContentWidth: CGFloat {
    IOSNativeDesign.width - 2 * IOSNativeDesign.paddingH
  }

  private var contentScale: CGFloat {
    guard referenceContentWidth > 0 else { return 1 }
    return max(0.85, (viewWidth - 2 * horizontalEdge) / referenceContentWidth)
  }

  func x(_ designX: CGFloat) -> CGFloat {
    horizontalEdge + (designX - IOSNativeDesign.paddingH) * contentScale
  }

  func width(_ designWidth: CGFloat) -> CGFloat {
    designWidth * contentScale
  }

  /// UIKit normally owns the full Home Indicator inset; native mode only keeps a small visual breathing space.
  var bottomKeyInset: CGFloat {
    safeAreaBottom > 0 ? 4 : 0
  }

  var cornerRadius: CGFloat {
    viewWidth >= 428 ? 6 : 5.5
  }

  /// System keyboard typography is point based rather than proportional to screen width.
  func fontSize(_ base: CGFloat) -> CGFloat {
    base
  }
}
