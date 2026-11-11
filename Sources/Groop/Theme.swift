//
//  Theme.swift
//  Groop
//
//  The studio's look: dark panels, light cards, one blue accent.
//

import AppKit
import SwiftUI

enum Theme {
    /// Light and dark values in one colour, resolved by the view's appearance.
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let window = adaptive(NSColor(white: 0.93, alpha: 1), NSColor(red: 0.067, green: 0.071, blue: 0.082, alpha: 1))
    static let panel = adaptive(NSColor(white: 0.985, alpha: 1), NSColor(red: 0.106, green: 0.110, blue: 0.125, alpha: 1))
    static let card = adaptive(NSColor(white: 0, alpha: 0.035), NSColor(white: 1, alpha: 0.045))
    static let well = adaptive(NSColor(white: 0, alpha: 0.055), NSColor(white: 1, alpha: 0.07))
    static let wellSelected = adaptive(NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 0.16))
    static let track = adaptive(NSColor(white: 0, alpha: 0.06), NSColor(white: 0, alpha: 0.3))
    static let hairline = adaptive(NSColor(white: 0, alpha: 0.08), NSColor(white: 1, alpha: 0.08))
    static let text = adaptive(NSColor(white: 0.08, alpha: 1), NSColor(white: 1, alpha: 0.93))
    static let secondary = adaptive(NSColor(white: 0, alpha: 0.55), NSColor(white: 1, alpha: 0.58))
    static let tertiary = adaptive(NSColor(white: 0, alpha: 0.36), NSColor(white: 1, alpha: 0.36))
    static let floating = adaptive(NSColor(white: 1, alpha: 0.96), NSColor(white: 0.18, alpha: 1))

    /// The accent the user picked in the studio's settings.
    nonisolated(unsafe) static var accentHex = "#3D8BFF"
    static var accent: Color { Color(hex: accentHex) }
    static var accentSoft: Color { Color(hex: accentHex).opacity(0.16) }

    static let accents: [(String, String)] = [
        ("#3D8BFF", L("Blue", "Bleu")), ("#9B5CF6", L("Purple", "Violet")), ("#F0509A", L("Pink", "Rose")),
        ("#FF8A1F", L("Orange", "Orange")), ("#22B573", L("Green", "Vert")), ("#8E8E93", L("Graphite", "Graphite")),
    ]

    static let radius: CGFloat = 16
    static let cardRadius: CGFloat = 12
}

// MARK: - Containers

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

/// A group of rows in the inspector, with an optional small title.
struct InspectorCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Controls

/// A row with a title and a blue switch at its end.
struct SwitchRow: View {
    let title: String
    var info: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.text)
            if let info {
                Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(Theme.tertiary).help(info)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(Theme.accent)
        }
        .frame(minHeight: 22)
    }
}

/// A title, its value, and a slider under them.
struct SliderRow: View {
    let title: String
    let value: String
    @Binding var amount: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(value).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            if let step {
                Slider(value: $amount, in: range, step: step).controlSize(.small).tint(Theme.accent)
            } else {
                Slider(value: $amount, in: range).controlSize(.small).tint(Theme.accent)
            }
        }
    }
}

/// Two to five choices in one dark pill, the chosen one lit.
struct Segmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> AnyView

    init(_ options: [Value], selection: Binding<Value>, title: @escaping (Value) -> String) {
        self.options = options
        self._selection = selection
        self.label = { AnyView(Text(title($0)).font(.system(size: 11.5, weight: .medium))) }
    }

    init(_ options: [Value], selection: Binding<Value>, @ViewBuilder content: @escaping (Value) -> some View) {
        self.options = options
        self._selection = selection
        self.label = { AnyView(content($0)) }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    label(option)
                        .foregroundStyle(on ? Theme.text : Theme.secondary)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.wellSelected : .clear).shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.track))
    }
}

/// A labelled segmented control.
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let name: (Value) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Segmented(options, selection: $selection, title: name)
        }
    }
}

struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                Text("\(value)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                    .frame(width: 26)
                stepButton("plus", enabled: value < range.upperBound) { value += 1 }
            }
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.track))
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? Theme.text : Theme.tertiary).disabled(!enabled)
    }
}

/// The row of colour dots, plus the system colour wheel at the end.
struct SwatchGrid: View {
    @Binding var hex: String

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(18), spacing: 7), count: 10)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(Palette.swatches, id: \.self) { swatch in
                let on = swatch.uppercased() == hex.uppercased()
                Circle().fill(Color(hex: swatch))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .padding(2)
                    .overlay(Circle().strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5))
                    .onTapGesture { hex = swatch }
            }
        }
        HStack {
            Text(L("Custom colour", "Couleur libre")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Spacer()
            ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hex }), supportsOpacity: false)
                .labelsHidden()
        }
    }
}

/// A plain dark button of the studio.
struct WellButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? .white : Theme.text)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(prominent ? Theme.accent : Theme.well).opacity(configuration.isPressed ? 0.7 : 1))
    }
}

/// A slider for an exact size in points, with its value at the end.
struct PxSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "px"

    var body: some View {
        SliderRow(title: title, value: unit == "%" ? "\(Int((value * 100).rounded())) %" : "\(Int(value.rounded())) \(unit)",
                  amount: $value, range: range, step: step)
    }
}
