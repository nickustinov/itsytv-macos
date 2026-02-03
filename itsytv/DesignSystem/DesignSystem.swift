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

        static var accent: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.269, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            }
        }

        static var border: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.269, alpha: 1) : NSColor(white: 0.922, alpha: 1)
            }
        }

        static var input: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.35, alpha: 1) : NSColor(white: 0.88, alpha: 1)
            }
        }

        static var ring: NSColor {
            NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(white: 0.556, alpha: 1) : NSColor(white: 0.708, alpha: 1)
            }
        }

        // Status colors
        static let success = NSColor(red: 0.22, green: 0.78, blue: 0.45, alpha: 1)
        static let warning = NSColor(red: 0.95, green: 0.68, blue: 0.25, alpha: 1)
        static let destructive = NSColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        static let info = NSColor(red: 0.25, green: 0.60, blue: 0.95, alpha: 1)
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
        static let labelSmall = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let label = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let labelMedium = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let body = NSFont.systemFont(ofSize: 14, weight: .regular)
        static let bodyMedium = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let headline = NSFont.systemFont(ofSize: 15, weight: .semibold)
    }

    // MARK: - Shadows

    enum Shadow {
        static func small() -> NSShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
            shadow.shadowOffset = NSSize(width: 0, height: 1)
            shadow.shadowBlurRadius = 2
            return shadow
        }

        static func medium() -> NSShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
            shadow.shadowOffset = NSSize(width: 0, height: 2)
            shadow.shadowBlurRadius = 4
            return shadow
        }
    }

    // MARK: - Animation

    enum Animation {
        static let fast: CFTimeInterval = 0.15
        static let normal: CFTimeInterval = 0.25
        static let slow: CFTimeInterval = 0.35

        static let springDamping: CGFloat = 0.7
        static let springVelocity: CGFloat = 0.5
    }

    // MARK: - Control sizes

    enum ControlSize {
        static let iconSmall: CGFloat = 14
        static let iconMedium: CGFloat = 14
        static let iconLarge: CGFloat = 22

        static let menuItemHeight: CGFloat = 28
        static let menuItemWidth: CGFloat = 260

        static let buttonHeight: CGFloat = 32
        static let buttonHeightSmall: CGFloat = 28
    }
}

// MARK: - Button factory

enum DSButton {

    enum Variant {
        case primary
        case secondary
        case ghost
        case destructive
    }

    static func create(
        title: String,
        variant: Variant = .primary,
        small: Bool = false,
        width: CGFloat? = nil
    ) -> NSButton {
        let height = small ? DS.ControlSize.buttonHeightSmall : DS.ControlSize.buttonHeight
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = DS.Radius.md

        let font = small ? DS.Typography.label : DS.Typography.labelMedium
        let (bg, fg) = colors(for: variant)

        button.layer?.backgroundColor = bg.cgColorResolved
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: fg.resolvedColor(),
            .font: font,
        ])

        let w = width ?? (CGFloat(title.count) * 8 + DS.Spacing.xl)
        button.frame = NSRect(x: 0, y: 0, width: w, height: height)

        return button
    }

    static func colors(for variant: Variant) -> (bg: NSColor, fg: NSColor) {
        switch variant {
        case .primary:
            return (DS.Colors.primary, DS.Colors.primaryForeground)
        case .secondary:
            return (DS.Colors.secondary, DS.Colors.secondaryForeground)
        case .ghost:
            return (.clear, DS.Colors.foreground)
        case .destructive:
            return (DS.Colors.destructive, .white)
        }
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
