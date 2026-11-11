//
//  Models.swift
//  Groop
//
//  A Groop folder: a few apps behind one tile of the Dock. A click on the
//  tile opens the folder's glass window above it, with the apps in a grid.
//

import AppKit
import SwiftUI

// MARK: - Apps

/// An app of a folder, kept by path with the name the user gave it.
struct AppItem: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var bundleID: String?
    var name: String
    var customName: String?
    var category: AppCategory = .other

    var id: String { path }
    var label: String { customName?.isEmpty == false ? customName! : name }
    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    @MainActor var icon: NSImage { IconCache.shared.icon(for: path) }

    init(path: String, bundleID: String?, name: String, category: AppCategory) {
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.category = category
    }

    init?(url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        // The file name is what Finder shows; prefer it unless it is generic.
        let fileName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        self.init(path: url.path, bundleID: bundle?.bundleIdentifier,
                  name: fileName.isEmpty ? name : fileName,
                  category: AppCategory(lsCategory: info["LSApplicationCategoryType"] as? String, path: url.path))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        category = (try? c.decodeIfPresent(AppCategory.self, forKey: .category)) ?? .other
    }
}

enum AppCategory: String, Codable, CaseIterable, Sendable {
    case productivity, design, developer, media, ai, social, games, utilities, other

    var title: String {
        switch self {
        case .productivity: L("Productivity", "Productivité")
        case .design: L("Design", "Design")
        case .developer: L("Developer", "Développement")
        case .media: L("Media", "Médias")
        case .ai: L("AI", "IA")
        case .social: L("Social", "Social")
        case .games: L("Games", "Jeux")
        case .utilities: L("Utilities", "Utilitaires")
        case .other: L("Other", "Autres")
        }
    }

    init(lsCategory: String?, path: String) {
        let lower = path.lowercased()
        let aiHints = ["chatgpt", "claude", "gemini", "perplexity", "grok", "copilot", "ollama", "lm studio", "hermes", "codex", "cursor"]
        if aiHints.contains(where: { lower.contains($0) }) { self = .ai; return }
        switch lsCategory ?? "" {
        case "public.app-category.productivity", "public.app-category.business", "public.app-category.finance",
             "public.app-category.education", "public.app-category.reference":
            self = .productivity
        case "public.app-category.graphics-design", "public.app-category.photography":
            self = .design
        case "public.app-category.developer-tools":
            self = .developer
        case "public.app-category.music", "public.app-category.video", "public.app-category.entertainment",
             "public.app-category.news":
            self = .media
        case "public.app-category.social-networking", "public.app-category.lifestyle":
            self = .social
        case let category where category.contains("games"):
            self = .games
        case "public.app-category.utilities":
            self = .utilities
        default:
            self = lower.hasPrefix("/system/") ? .utilities : .other
        }
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let image = cache[path] { return image }
        // Resolve links first: /Applications/Safari.app is one, and its own
        // icon carries an alias arrow.
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let image = FileManager.default.fileExists(atPath: real)
            ? NSWorkspace.shared.icon(forFile: real)
            : NSWorkspace.shared.icon(for: .application)
        image.size = NSSize(width: 256, height: 256)
        cache[path] = image
        return image
    }
}

// MARK: - Choices

/// How the folder's tile looks in the Dock.
enum IconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, stack, folder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: L("Classic", "Classique")
        case .stack: L("Stack", "Pile")
        case .folder: L("Folder", "Dossier")
        }
    }
    var symbol: String {
        switch self {
        case .classic: "square.grid.2x2"
        case .stack: "square.stack.3d.up"
        case .folder: "folder"
        }
    }
}

enum FolderShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case folder, squircle
    var id: String { rawValue }
    var title: String { self == .folder ? L("Folder", "Dossier") : "Squircle" }
}

enum TileContent: String, Codable, CaseIterable, Identifiable, Sendable {
    case icon, text
    var id: String { rawValue }
    var title: String { self == .icon ? L("Icon", "Icône") : L("Text", "Texte") }
}

enum HeaderPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft, topCenter, bottomLeft, bottomCenter, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeft: L("Top left", "En haut à gauche")
        case .topCenter: L("Top centre", "En haut au centre")
        case .bottomLeft: L("Bottom left", "En bas à gauche")
        case .bottomCenter: L("Bottom centre", "En bas au centre")
        case .off: L("Off", "Non")
        }
    }
    var isTop: Bool { self == .topLeft || self == .topCenter }
    var isCentered: Bool { self == .topCenter || self == .bottomCenter }
}

enum LaunchAllPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topRight: L("Top right", "En haut à droite")
        case .bottomLeft: L("Bottom left", "En bas à gauche")
        case .bottomRight: L("Bottom right", "En bas à droite")
        }
    }
}

enum FontColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, white, black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .white: L("White", "Blanc")
        case .black: L("Black", "Noir")
        }
    }
}

enum SizeStep: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

enum GridView: String, Codable, CaseIterable, Identifiable, Sendable {
    case icons, list, tiles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icons: L("Icons", "Icônes")
        case .list: L("List", "Liste")
        case .tiles: L("Tiles", "Tuiles")
        }
    }
}

enum Density: String, Codable, CaseIterable, Identifiable, Sendable {
    case tight, normal, airy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tight: L("Tight", "Serrée")
        case .normal: L("Normal", "Normale")
        case .airy: L("Airy", "Aérée")
        }
    }
    var gap: CGFloat {
        switch self {
        case .tight: 6
        case .normal: 12
        case .airy: 20
        }
    }
}

enum Surface: String, Codable, CaseIterable, Identifiable, Sendable {
    case glass, frost, grain, shine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: L("Glass", "Verre")
        case .frost: L("Frost", "Givre")
        case .grain: L("Grain", "Grain")
        case .shine: L("Shine", "Éclats")
        }
    }
}

// MARK: - Folder

struct Folder: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = L("New folder", "Nouveau dossier")
    var createdAt = Date()
    var apps: [AppItem] = []
    var presetID: String? = "glass-grey"

    // Icon
    var iconStyle: IconStyle = .classic
    var colorHex = "#8E8E93"
    var opacity = 0.3
    var matte = 0.0
    var dense = false
    var roundIcons = false
    var glossy = true
    var lift = false
    var stackDepth = 3
    var folderShape: FolderShape = .folder
    var tileContent: TileContent = .icon
    var tileSymbol = "square.grid.2x2.fill"
    var tileText = ""
    var tileSymbolScale = 1.0
    var tileRotation = 0.0

    // Window
    var popupCustom = false
    var popupColorHex = "#8E8E93"
    var popupOpacity = 0.55
    var surface: Surface = .glass
    var header: HeaderPosition = .topLeft
    var launchAll = false
    var launchAllPosition: LaunchAllPosition = .topRight
    var fontColor: FontColor = .auto
    var textSize: SizeStep = .medium
    var showNames = true
    var textShadow = false
    var textBackdrop = false
    var cornerRadius = 26.0

    // Grid
    var autoLayout = true
    var columns = 4
    var rowsPerPage = 3
    var view: GridView = .icons
    var listColumns = 1
    var iconSize: SizeStep = .medium
    var density: Density = .normal
    var hidePagination = false

    // Exact sizes, in points; the S / M / L and density choices set them.
    var iconPx = 52.0
    var labelPx = 11.5
    var titlePx = 16.0
    var gapPx = 12.0
    var paddingPx = 18.0
    var folderScale = 1.0
    var tileAppScale = 1.0
    var extraPages = 0

    // Pictures and the Command Center.
    var tileImage: ImageStyle?
    var windowImage: ImageStyle?
    var inTray = false

    // Where the window opens: nil follows the app-wide setting. The centre
    // is kept for "where I left it", in screen points.
    var placement: Placement?
    var windowCenterX: Double?
    var windowCenterY: Double?

    init() {}

    var windowColorHex: String { popupCustom ? popupColorHex : colorHex }
    var windowOpacity: Double { popupCustom ? popupOpacity : max(opacity, 0.25) }

    /// Columns and rows of one page of the folder's window.
    func layout(count: Int) -> (columns: Int, rows: Int, pages: Int) {
        let n = max(count, 1)
        let cols: Int, rows: Int
        if view == .list {
            cols = max(1, listColumns)
            rows = autoLayout ? min(8, Int(ceil(Double(n) / Double(cols)))) : max(1, rowsPerPage)
        } else if autoLayout {
            switch n {
            case 1...4: cols = n
            case 5...9: cols = 3
            case 10...16: cols = 4
            default: cols = 5
            }
            rows = min(view == .tiles ? 4 : 4, Int(ceil(Double(n) / Double(cols))))
        } else {
            cols = max(1, columns)
            rows = max(1, rowsPerPage)
        }
        let perPage = max(1, cols * rows)
        let needed = max(1, Int(ceil(Double(count) / Double(perPage))))
        return (cols, rows, needed + max(0, extraPages))
    }

    var iconPoints: CGFloat { CGFloat(iconPx) }
    var labelPoints: CGFloat { CGFloat(labelPx) }
    var titlePoints: CGFloat { CGFloat(titlePx) }

    static func iconPx(for step: SizeStep) -> Double {
        switch step {
        case .small: 40
        case .medium: 52
        case .large: 64
        }
    }

    static func textPx(for step: SizeStep) -> (label: Double, title: Double) {
        switch step {
        case .small: (10, 14)
        case .medium: (11.5, 16)
        case .large: (13, 19)
        }
    }

    /// The S / M / L step closest to the exact icon size, for the picker.
    var nearestIconStep: SizeStep {
        SizeStep.allCases.min { abs(Self.iconPx(for: $0) - iconPx) < abs(Self.iconPx(for: $1) - iconPx) }!
    }

    /// Text on the window: the user's choice, or what reads best on its colour.
    var resolvedFontIsDark: Bool {
        switch fontColor {
        case .white: false
        case .black: true
        case .auto: Color(hex: windowColorHex).luminance > 0.72 && windowOpacity > 0.6
        }
    }

    // Decoding keeps every default for keys an older file does not have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Folder()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        id = v(.id, d.id); name = v(.name, d.name); createdAt = v(.createdAt, d.createdAt); apps = v(.apps, d.apps)
        presetID = v(.presetID, d.presetID)
        iconStyle = v(.iconStyle, d.iconStyle); colorHex = v(.colorHex, d.colorHex); opacity = v(.opacity, d.opacity)
        matte = v(.matte, d.matte); dense = v(.dense, d.dense); roundIcons = v(.roundIcons, d.roundIcons)
        glossy = v(.glossy, d.glossy); lift = v(.lift, d.lift); stackDepth = v(.stackDepth, d.stackDepth)
        folderShape = v(.folderShape, d.folderShape); tileContent = v(.tileContent, d.tileContent)
        tileSymbol = v(.tileSymbol, d.tileSymbol); tileText = v(.tileText, d.tileText)
        tileSymbolScale = v(.tileSymbolScale, d.tileSymbolScale); tileRotation = v(.tileRotation, d.tileRotation)
        popupCustom = v(.popupCustom, d.popupCustom); popupColorHex = v(.popupColorHex, d.popupColorHex)
        popupOpacity = v(.popupOpacity, d.popupOpacity); surface = v(.surface, d.surface); header = v(.header, d.header)
        launchAll = v(.launchAll, d.launchAll); launchAllPosition = v(.launchAllPosition, d.launchAllPosition)
        fontColor = v(.fontColor, d.fontColor); textSize = v(.textSize, d.textSize); showNames = v(.showNames, d.showNames)
        textShadow = v(.textShadow, d.textShadow); textBackdrop = v(.textBackdrop, d.textBackdrop)
        cornerRadius = v(.cornerRadius, d.cornerRadius)
        autoLayout = v(.autoLayout, d.autoLayout); columns = v(.columns, d.columns); rowsPerPage = v(.rowsPerPage, d.rowsPerPage)
        view = v(.view, d.view); listColumns = v(.listColumns, d.listColumns); iconSize = v(.iconSize, d.iconSize)
        density = v(.density, d.density); hidePagination = v(.hidePagination, d.hidePagination)
        iconPx = v(.iconPx, d.iconPx); labelPx = v(.labelPx, d.labelPx); titlePx = v(.titlePx, d.titlePx)
        gapPx = v(.gapPx, d.gapPx); paddingPx = v(.paddingPx, d.paddingPx); folderScale = v(.folderScale, d.folderScale)
        tileAppScale = v(.tileAppScale, d.tileAppScale); extraPages = v(.extraPages, d.extraPages)
        tileImage = v(.tileImage, d.tileImage); windowImage = v(.windowImage, d.windowImage); inTray = v(.inTray, d.inTray)
        placement = v(.placement, d.placement); windowCenterX = v(.windowCenterX, d.windowCenterX)
        windowCenterY = v(.windowCenterY, d.windowCenterY)
    }
}

extension Folder {
    /// What the Dock tile is drawn from. Only a change here makes a pinned
    /// folder's tile out of date; window and grid settings apply at once.
    var tileSignature: [String] {
        [name, iconStyle.rawValue, colorHex, "\(opacity)", "\(matte)", "\(dense)", "\(roundIcons)", "\(glossy)", "\(lift)",
         "\(stackDepth)", folderShape.rawValue, tileContent.rawValue, tileSymbol, tileText, "\(tileSymbolScale)",
         "\(tileRotation)", "\(tileAppScale)", tileImage.map { "\($0)" } ?? "-"] + apps.prefix(9).map(\.path)
    }
}

/// A picture behind the tile or the window, with its adjustments.
struct ImageStyle: Codable, Hashable, Sendable {
    var file: String
    var scale = 1.0
    var saturation = 1.0
    var blur = 0.0
    var brightness = 0.0

    init(file: String) { self.file = file }
}

// MARK: - App-wide settings

enum Placement: String, Codable, CaseIterable, Identifiable, Sendable {
    case dock, center, pointer, remembered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: L("Near the Dock", "Près du Dock")
        case .center: L("Centred", "Centrée")
        case .pointer: L("At the pointer", "Au pointeur")
        case .remembered: L("Where I left it", "Là où je l’ai mise")
        }
    }
}

enum SwipeSpeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case slow, medium, fast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: L("Slow", "Lente")
        case .medium: L("Medium", "Moyenne")
        case .fast: L("Fast", "Rapide")
        }
    }
    var duration: Double {
        switch self {
        case .slow: 0.5
        case .medium: 0.32
        case .fast: 0.2
        }
    }
}

struct GroopSettings: Codable, Equatable, Sendable {
    var placement: Placement = .dock
    var windowScale = 1.0
    var closeAfterLaunch = true
    var closeOnLeave = false
    var hoverZoom = true
    var keepOnTop = false
    var showArrows = true
    var swipeSpeed: SwipeSpeed = .medium
    var hiddenApps: [String] = []
    var appRenames: [String: String] = [:]
    var theme: StudioTheme = .system
    var accentHex = "#3D8BFF"
    var creatorMode = true
    var parallax = false
    var parallaxStrength = 1.0
    var parallaxDirection: ParallaxDirection = .vertical
    var parallaxInvert = false
    var appsSort: AppsSort = .category
    var pickerCards = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GroopSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        placement = v(.placement, d.placement); windowScale = v(.windowScale, d.windowScale)
        closeAfterLaunch = v(.closeAfterLaunch, d.closeAfterLaunch); closeOnLeave = v(.closeOnLeave, d.closeOnLeave)
        hoverZoom = v(.hoverZoom, d.hoverZoom); keepOnTop = v(.keepOnTop, d.keepOnTop); showArrows = v(.showArrows, d.showArrows)
        swipeSpeed = v(.swipeSpeed, d.swipeSpeed); hiddenApps = v(.hiddenApps, d.hiddenApps); appRenames = v(.appRenames, d.appRenames)
        theme = v(.theme, d.theme); accentHex = v(.accentHex, d.accentHex); creatorMode = v(.creatorMode, d.creatorMode)
        parallax = v(.parallax, d.parallax); parallaxStrength = v(.parallaxStrength, d.parallaxStrength)
        parallaxDirection = v(.parallaxDirection, d.parallaxDirection); parallaxInvert = v(.parallaxInvert, d.parallaxInvert)
        appsSort = v(.appsSort, d.appsSort); pickerCards = v(.pickerCards, d.pickerCards)
    }
}

enum StudioTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("System", "Système")
        case .light: L("Light", "Clair")
        case .dark: L("Dark", "Sombre")
        }
    }
}

enum ParallaxDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case vertical, horizontal, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vertical: L("Vertical", "Vertical")
        case .horizontal: L("Horizontal", "Horizontal")
        case .all: L("All", "Toutes")
        }
    }
}

enum AppsSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case category, az, za
    var id: String { rawValue }
    var title: String {
        switch self {
        case .category: L("By category", "Par catégories")
        case .az: "A → Z"
        case .za: "Z → A"
        }
    }
}

/// What Groop keeps on disk: the folders, the user's own styles and the
/// app-wide settings.
struct GroopDocument: Codable, Sendable {
    var folders: [Folder] = []
    var savedStyles: [SavedStyle] = []
    var settings = GroopSettings()
    /// 2 since the window's sizes were made compact.
    var sizeVersion = 2

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = (try? c.decodeIfPresent([Folder].self, forKey: .folders)) ?? []
        savedStyles = (try? c.decodeIfPresent([SavedStyle].self, forKey: .savedStyles)) ?? []
        settings = (try? c.decodeIfPresent(GroopSettings.self, forKey: .settings)) ?? GroopSettings()
        sizeVersion = (try? c.decodeIfPresent(Int.self, forKey: .sizeVersion)) ?? 1
        if sizeVersion < 2 {
            // The first sizes were far too big next to the Dock: bring them
            // down by the same ratio as the new S / M / L steps.
            for i in folders.indices {
                folders[i].iconPx = min(52, (folders[i].iconPx * 52 / 60).rounded())
                folders[i].labelPx = min(folders[i].labelPx, 13)
                folders[i].titlePx = (folders[i].titlePx * 16 / 18).rounded()
                folders[i].gapPx = (folders[i].gapPx * 0.75).rounded()
                folders[i].paddingPx = (folders[i].paddingPx * 18 / 22).rounded()
            }
            sizeVersion = 2
        }
    }
}

/// A style the user saved from a folder: everything but its name and apps.
struct SavedStyle: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var style: Folder
}

extension Folder {
    /// This folder with another one's look, keeping its own identity and apps.
    func applyingStyle(of source: Folder) -> Folder {
        var copy = source
        copy.id = id
        copy.name = name
        copy.createdAt = createdAt
        copy.apps = apps
        return copy
    }
}

// MARK: - Colour

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255, opacity: 1)
    }

    var hex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }

    var luminance: Double {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
    }

    func mixed(with other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        return Color(.sRGB, red: a.redComponent + (b.redComponent - a.redComponent) * amount,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount, opacity: 1)
    }
}
