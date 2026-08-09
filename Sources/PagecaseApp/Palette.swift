import PagecaseCore
import SwiftUI

enum Palette {
  static func canvas(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(red: 0.090, green: 0.090, blue: 0.086)
      : Color(red: 0.969, green: 0.965, blue: 0.953)
  }

  static func surface(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(red: 0.125, green: 0.125, blue: 0.122)
      : .white
  }

  static func ink(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(red: 0.941, green: 0.937, blue: 0.925)
      : Color(red: 0.184, green: 0.204, blue: 0.216)
  }

  static func muted(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(red: 0.647, green: 0.635, blue: 0.608)
      : Color(red: 0.471, green: 0.467, blue: 0.455)
  }

  static func border(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(red: 0.188, green: 0.188, blue: 0.180)
      : Color(red: 0.918, green: 0.918, blue: 0.918)
  }

  static func selection(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color.white.opacity(0.07)
      : Color.black.opacity(0.045)
  }
}

extension BrowserKind {
  var displayName: String {
    switch self {
    case .chrome:
      return "Chrome"
    case .safari:
      return "Safari"
    }
  }

  var symbol: String {
    switch self {
    case .chrome:
      return "circle.grid.2x2.fill"
    case .safari:
      return "safari"
    }
  }

  var accentColor: Color {
    switch self {
    case .chrome:
      return Color(red: 0.24, green: 0.48, blue: 0.66)
    case .safari:
      return Color(red: 0.43, green: 0.38, blue: 0.62)
    }
  }

  func tint(_ colorScheme: ColorScheme) -> Color {
    switch (self, colorScheme) {
    case (.chrome, .dark):
      return Color(red: 0.13, green: 0.20, blue: 0.25)
    case (.chrome, _):
      return Color(red: 0.88, green: 0.94, blue: 0.98)
    case (.safari, .dark):
      return Color(red: 0.20, green: 0.18, blue: 0.27)
    case (.safari, _):
      return Color(red: 0.94, green: 0.92, blue: 0.97)
    }
  }
}

extension ChromeGroupColor {
  var displayColor: Color {
    switch self {
    case .grey:
      return Color(red: 0.55, green: 0.55, blue: 0.52)
    case .blue:
      return Color(red: 0.33, green: 0.56, blue: 0.72)
    case .red:
      return Color(red: 0.73, green: 0.40, blue: 0.38)
    case .yellow:
      return Color(red: 0.78, green: 0.65, blue: 0.30)
    case .green:
      return Color(red: 0.38, green: 0.61, blue: 0.43)
    case .pink:
      return Color(red: 0.72, green: 0.47, blue: 0.58)
    case .purple:
      return Color(red: 0.55, green: 0.45, blue: 0.68)
    case .cyan:
      return Color(red: 0.34, green: 0.64, blue: 0.67)
    case .orange:
      return Color(red: 0.78, green: 0.50, blue: 0.29)
    }
  }
}
