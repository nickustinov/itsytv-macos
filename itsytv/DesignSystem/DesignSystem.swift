import AppKit
import SwiftUI

// MARK: - Design tokens

enum DS {

    // MARK: - Colors

    enum Colors {
        static var background: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.145, alpha: 1) : NSColor(white: 1, alpha: 1)
            }
        }

        static var foreground: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.985, alpha: 1) : NSColor(white: 0.145, alpha: 1)
            }
        }

        static var primary: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.985, alpha: 1) : NSColor(white: 0.205, alpha: 1)
            }
        }

        static var primaryForeground: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.205, alpha: 1) : NSColor(white: 0.985, alpha: 1)
            }
        }

        static var secondary: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.269, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            }
        }

        static var secondaryForeground: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.985, alpha: 1) : NSColor(white: 0.205, alpha: 1)
            }
        }

        static var muted: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.269, alpha: 1) : NSColor(white: 0.85, alpha: 1)
            }
        }

        static var mutedForeground: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.708, alpha: 1) : NSColor(white: 0.556, alpha: 1)
            }
        }

        static var iconForeground: NSColor {
            foreground
        }

        static var remoteButton: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.27, alpha: 1) : NSColor(white: 0.205, alpha: 1)
            }
        }

        static var remoteButtonForeground: NSColor {
            NSColor(white: 0.985, alpha: 1)
        }

        static var border: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.269, alpha: 1) : NSColor(white: 0.922, alpha: 1)
            }
        }

        static var promoGradientStart: NSColor {
            NSColor(red: 0.30, green: 0.45, blue: 0.95, alpha: 1)
        }

        static var promoGradientEnd: NSColor {
            NSColor(red: 0.65, green: 0.35, blue: 0.90, alpha: 1)
        }

    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        static let full: CGFloat = 9999
    }

    // MARK: - Typography

    enum Typography {
        static let label = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let labelMedium = NSFont.systemFont(ofSize: 13, weight: .medium)
    }

    // MARK: - Control sizes

    enum ControlSize {
        static let iconMedium: CGFloat = 14
        static let menuItemHeight: CGFloat = 28
        static let menuItemWidth: CGFloat = 260
    }
}

// MARK: - NSAppearance extension

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - NSColor convenience

extension NSColor {
    func resolvedColor(for appearance: NSAppearance? = nil) -> NSColor {
        let appearance = appearance ?? NSAppearance.current ?? NSApp.effectiveAppearance
        var resolved = self
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.deviceRGB) ?? self
        }
        return resolved
    }

    var cgColorResolved: CGColor {
        resolvedColor().cgColor
    }
}

// MARK: - Capsule segment picker

struct CapsuleSegmentPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<options.count, id: \.self) { index in
                let value = options[index].0
                let label = options[index].1
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = value
                    }
                } label: {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selection == value ? Color(nsColor: DS.Colors.primary) : .clear)
                        )
                        .contentShape(Capsule())
                        .foregroundStyle(selection == value ? Color(nsColor: DS.Colors.primaryForeground) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(nsColor: DS.Colors.muted)))
    }
}
