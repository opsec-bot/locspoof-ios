import SwiftUI
import UIKit

/// One accent color for the primary action; everything else stays neutral.
/// No pure black or white: dark surfaces carry a little navy, light ones a little warmth.
enum Theme {
    static let accent = Color(red: 0.18, green: 0.45, blue: 0.96)

    static let good = Color(red: 0.20, green: 0.66, blue: 0.40)
    static let caution = Color(red: 0.93, green: 0.58, blue: 0.13)
    static let bad = Color(red: 0.88, green: 0.28, blue: 0.27)

    static let panel = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.085, blue: 0.115, alpha: 1)
            : UIColor(red: 0.988, green: 0.982, blue: 0.972, alpha: 1)
    })

    static let raised = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.145, blue: 0.19, alpha: 1)
            : UIColor(red: 0.94, green: 0.935, blue: 0.925, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.945, blue: 0.93, alpha: 1)
            : UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
    })

    static let routeLine = accent
}

extension TunnelManager.Status {
    var label: String {
        switch self {
        case .idle:        return "Not connected"
        case .connecting:  return "Connecting…"
        case .findingPort: return "Finding port…"
        case .connected:   return "Connected"
        case .failed:      return "Can't connect · Fix"
        }
    }

    var color: Color {
        switch self {
        case .connected:                return Theme.good
        case .connecting, .findingPort: return Theme.caution
        case .failed:                   return Theme.bad
        case .idle:                     return .secondary
        }
    }
}
