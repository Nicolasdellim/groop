//
//  Presets.swift
//  Groop
//
//  Ready-made looks, a starting point the user tweaks in the inspector.
//

import SwiftUI

struct Preset: Identifiable, Sendable {
    let id: String
    let name: String
    let group: PresetGroup
    let apply: @Sendable (inout Folder) -> Void

    func styled(_ folder: Folder) -> Folder {
        var copy = folder
        apply(&copy)
        copy.presetID = id
        return copy
    }
}

enum PresetGroup: String, CaseIterable, Identifiable {
    case colorGlass, themes, candy, special
    var id: String { rawValue }
    var title: String {
        switch self {
        case .colorGlass: L("Colour glass", "Verre coloré")
        case .themes: L("Themes", "Thèmes")
        case .candy: L("Candy", "Bonbons")
        case .special: L("Cosmos", "Cosmos")
        }
    }
}

/// The colours of the swatch row, shared by the icon and the window.
enum Palette {
    static let swatches: [String] = [
        "#FFFFFF", "#C7C7CC", "#8E8E93", "#0A84FF", "#30D158", "#FFD60A", "#FF9F0A", "#FF453A", "#FF6FB5", "#BF5AF2",
        "#1C1C1E", "#2C2C54", "#3A3A8C", "#3D7A9E", "#A33A5C", "#4A5BD4", "#6B4FD8", "#3B8C6E", "#C77D2E", "#2E7D32",
    ]
}

enum Presets {
    static let all: [Preset] = glass + themes + candy + special

    static func preset(_ id: String?) -> Preset? { all.first { $0.id == id } }

    private static func glassPreset(_ id: String, _ en: String, _ fr: String, _ hex: String) -> Preset {
        Preset(id: "glass-\(id)", name: L(en, fr), group: .colorGlass) { f in
            f.iconStyle = .classic
            f.colorHex = hex
            f.opacity = 0.32
            f.matte = 0
            f.glossy = true
            f.popupCustom = false
            f.surface = .glass
            f.fontColor = .auto
        }
    }

    static let glass: [Preset] = [
        glassPreset("grey", "Grey", "Gris", "#8E8E93"),
        glassPreset("blue", "Blue", "Bleu", "#0A84FF"),
        glassPreset("green", "Green", "Vert", "#30D158"),
        glassPreset("pink", "Pink", "Rose", "#FF6FB5"),
        glassPreset("purple", "Purple", "Violet", "#BF5AF2"),
        glassPreset("orange", "Orange", "Orange", "#FF9F0A"),
        glassPreset("night", "Night", "Nuit", "#1C1C1E"),
        glassPreset("snow", "Snow", "Neige", "#FFFFFF"),
    ]

    private static func themePreset(_ id: String, _ en: String, _ fr: String, _ hex: String, _ window: String,
                                    emoji: String? = nil, text: String? = nil, symbol: String? = nil,
                                    shape: FolderShape = .squircle, rotation: Double = 0) -> Preset {
        Preset(id: "theme-\(id)", name: L(en, fr), group: .themes) { f in
            f.iconStyle = .folder
            f.folderShape = shape
            if let emoji { f.tileContent = .text; f.tileText = emoji }
            else if let text { f.tileContent = .text; f.tileText = text }
            else { f.tileContent = .icon; f.tileSymbol = symbol ?? "folder.fill" }
            f.tileRotation = rotation
            f.colorHex = hex
            f.opacity = 0.85
            f.glossy = true
            f.popupCustom = true
            f.popupColorHex = window
            f.popupOpacity = 0.72
            f.header = .topLeft
            f.view = .icons
        }
    }

    static let themes: [Preset] = [
        themePreset("tomato", "Tomato", "Tomate", "#FFB3AE", "#D9443A", emoji: "🍅"),
        themePreset("pizza", "Pizza", "Pizza", "#FFD59A", "#E0902A", emoji: "🍕"),
        themePreset("dev", "Dev mode", "Dev Mode", "#9FE3A8", "#2E7D32", text: "Dev Mode", shape: .folder, rotation: -4),
        themePreset("manifest", "Manifest", "Manifeste", "#A9D8F0", "#2A7EA8", text: "Mobile First", shape: .folder, rotation: 4),
        themePreset("design", "Design", "Design", "#C8B6FF", "#6B4FD8", symbol: "paintpalette.fill", shape: .folder),
        themePreset("music", "Music", "Musique", "#FF8A80", "#C62828", emoji: "🎧"),
        themePreset("games", "Games", "Jeux", "#9FA8FF", "#3949AB", emoji: "🎮"),
        themePreset("work", "Work", "Travail", "#FFE0A3", "#A86B1E", emoji: "💼"),
    ]

    private static func candyPreset(_ id: String, _ en: String, _ fr: String, _ hex: String, _ window: String, emoji: String,
                                    view: GridView = .icons, header: HeaderPosition = .topLeft, radius: Double = 26) -> Preset {
        Preset(id: "candy-\(id)", name: L(en, fr), group: .candy) { f in
            f.iconStyle = .folder
            f.folderShape = .squircle
            f.tileContent = .text
            f.tileText = emoji
            f.colorHex = hex
            f.opacity = 0.9
            f.glossy = true
            f.lift = true
            f.popupCustom = true
            f.popupColorHex = window
            f.popupOpacity = 0.78
            f.surface = .shine
            f.view = view
            f.header = header
            f.cornerRadius = radius
        }
    }

    static let candy: [Preset] = [
        candyPreset("granita", "Granita", "Granité", "#8FD3FF", "#2D8FD5", emoji: "🌊"),
        candyPreset("bubblegum", "Bubblegum", "Bubblegum", "#FF9CC7", "#E8508F", emoji: "💗"),
        candyPreset("licorice", "Licorice", "Réglisse", "#4A4A4F", "#1C1C1E", emoji: "⚫️", view: .tiles, header: .off, radius: 22),
        candyPreset("grape", "Grape", "Raisin", "#B892FF", "#7B3FC4", emoji: "🍇", header: .off, radius: 40),
    ]

    private static func stackPreset(_ id: String, _ en: String, _ fr: String, _ hex: String) -> Preset {
        Preset(id: "space-\(id)", name: L(en, fr), group: .special) { f in
            f.iconStyle = .stack
            f.stackDepth = 3
            f.colorHex = hex
            f.opacity = 0.5
            f.popupCustom = true
            f.popupColorHex = hex
            f.popupOpacity = 0.6
            f.surface = .frost
            f.header = .topCenter
        }
    }

    static let special: [Preset] = [
        stackPreset("nebula", "Nebula", "Nébuleuse", "#3A3A8C"),
        stackPreset("aurora", "Aurora", "Aurore", "#3B8C6E"),
        stackPreset("mars", "Mars", "Mars", "#A33A5C"),
        stackPreset("void", "Void", "Vide", "#1C1C1E"),
    ]
}
