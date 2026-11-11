//
//  Inspector.swift
//  Groop
//
//  Every setting of the selected folder, in three tabs: its icon in the
//  Dock, its window, and the grid of apps inside it.
//

import AppKit
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case icon, window, grid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: L("Icon", "Icône")
        case .window: L("Window", "Fenêtre")
        case .grid: L("Grid", "Grille")
        }
    }
}

struct Inspector: View {
    @ObservedObject var store: GroopStore
    let openShortcuts: () -> Void
    @State private var tab: InspectorTab = .icon

    var body: some View {
        VStack(spacing: 0) {
            Segmented(InspectorTab.allCases, selection: $tab) { $0.title }
                .padding(12)
            Divider().overlay(Theme.hairline)
            if store.selected != nil {
                ScrollView {
                    VStack(spacing: 10) {
                        switch tab {
                        case .icon: IconTab(store: store)
                        case .window: WindowTab(store: store, openShortcuts: openShortcuts)
                        case .grid: GridTab(store: store)
                        }
                    }
                    .padding(12)
                }
            } else {
                Spacer()
                Text(L("Select a folder", "Sélectionnez un dossier")).font(.system(size: 12.5)).foregroundStyle(Theme.tertiary)
                Spacer()
            }
        }
        .panel()
    }
}

// MARK: - Shared pieces

private extension GroopStore {
    func f<T>(_ keyPath: WritableKeyPath<Folder, T>, _ fallback: T) -> Binding<T> { binding(keyPath, fallback: fallback) }
}

/// The adjustments of a picture behind the tile or the window.
private struct ImageControls: View {
    @ObservedObject var store: GroopStore
    let keyPath: WritableKeyPath<Folder, ImageStyle?>
    let title: String

    private var style: ImageStyle? { store.selected?[keyPath: keyPath] }

    private func value(_ path: WritableKeyPath<ImageStyle, Double>, _ fallback: Double) -> Binding<Double> {
        Binding(get: { style?[keyPath: path] ?? fallback },
                set: { newValue in store.updateSelected { $0[keyPath: keyPath]?[keyPath: path] = newValue } })
    }

    var body: some View {
        InspectorCard(title: title) {
            if let style {
                HStack(spacing: 10) {
                    if let image = ImageCache.shared.image(named: style.file) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Button(L("Replace…", "Remplacer…")) { store.chooseImage(for: keyPath) }.buttonStyle(WellButtonStyle())
                        Button(L("Remove", "Retirer")) { store.updateSelected { $0[keyPath: keyPath] = nil } }
                            .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.red.opacity(0.85))
                    }
                    Spacer()
                }
                PxSliderRow(title: L("Scale", "Échelle"), value: value(\.scale, 1), range: 0.5...3, step: 0.01, unit: "%")
                PxSliderRow(title: L("Saturation", "Saturation"), value: value(\.saturation, 1), range: 0...2, step: 0.01, unit: "%")
                SliderRow(title: L("Blur", "Flou"), value: "\(Int(style.blur)) px", amount: value(\.blur, 0), range: 0...30, step: 1)
                SliderRow(title: L("Brightness", "Luminosité"), value: "\(Int((style.brightness * 100).rounded())) %",
                          amount: value(\.brightness, 0), range: -0.5...0.5, step: 0.01)
            } else {
                Button { store.chooseImage(for: keyPath) } label: {
                    Label(L("Import a picture…", "Importer une image…"), systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(WellButtonStyle())
                Text(L("PNG, JPEG, HEIC or GIF. It sits under the colour.", "PNG, JPEG, HEIC ou GIF. Elle passe sous la couleur."))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

private struct ColorCard: View {
    let title: String
    @Binding var hex: String
    @Binding var opacity: Double

    var body: some View {
        InspectorCard(title: title) {
            SwatchGrid(hex: $hex)
            PxSliderRow(title: L("Opacity", "Opacité"), value: $opacity, range: 0...1, step: 0.01, unit: "%")
        }
    }
}

// MARK: - Icon

private struct IconTab: View {
    @ObservedObject var store: GroopStore
    @State private var symbolQuery = ""

    private static let symbols = [
        "square.grid.2x2.fill", "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "moon.fill", "sun.max.fill",
        "sparkles", "music.note", "gamecontroller.fill", "paintbrush.fill", "pencil", "hammer.fill", "wrench.and.screwdriver.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "briefcase.fill", "folder.fill", "doc.text.fill", "book.fill",
        "graduationcap.fill", "camera.fill", "photo.fill", "film.fill", "headphones", "message.fill", "envelope.fill",
        "globe", "cart.fill", "creditcard.fill", "chart.bar.fill", "brain.head.profile", "cpu.fill", "cloud.fill", "house.fill",
    ]

    var body: some View {
        let folder = store.selected ?? Folder()
        InspectorCard(title: L("Style", "Style")) {
            Segmented(IconStyle.allCases, selection: store.f(\.iconStyle, .classic)) { style in
                HStack(spacing: 4) { Image(systemName: style.symbol).font(.system(size: 10)); Text(style.title).font(.system(size: 11, weight: .medium)) }
            }
        }
        ColorCard(title: L("Colour", "Couleur"), hex: store.f(\.colorHex, "#8E8E93"), opacity: store.f(\.opacity, 0.3))
        InspectorCard(title: L("Finish", "Finition")) {
            PxSliderRow(title: L("Matte", "Mat"), value: store.f(\.matte, 0), range: 0...1, step: 0.01, unit: "%")
            SwitchRow(title: L("Glossy", "Brillant"), isOn: store.f(\.glossy, true))
            SwitchRow(title: L("Lifted", "Surélevé"), info: L("A deeper shadow under the tile", "Une ombre plus marquée sous la tuile"),
                      isOn: store.f(\.lift, false))
            if folder.iconStyle != .folder {
                SwitchRow(title: L("Round app icons", "Icônes d’apps rondes"), isOn: store.f(\.roundIcons, false))
            }
        }
        switch folder.iconStyle {
        case .classic:
            InspectorCard(title: L("Apps in the icon", "Apps dans l’icône")) {
                SwitchRow(title: L("Nine apps (3 × 3)", "Neuf apps (3 × 3)"), isOn: store.f(\.dense, false))
                PxSliderRow(title: L("Size of the apps in the icon", "Taille des apps dans l’icône"),
                            value: store.f(\.tileAppScale, 1), range: 0.5...1.25, step: 0.01, unit: "%")
            }
        case .stack:
            InspectorCard(title: L("Stack", "Pile")) {
                StepperRow(title: L("Cards", "Cartes"), value: store.f(\.stackDepth, 3), range: 2...5)
            }
        case .folder:
            InspectorCard(title: L("Folder", "Dossier")) {
                ChoiceRow(title: L("Shape", "Forme"), options: FolderShape.allCases, selection: store.f(\.folderShape, .folder)) { $0.title }
                ChoiceRow(title: L("Content", "Contenu"), options: TileContent.allCases, selection: store.f(\.tileContent, .icon)) { $0.title }
                if folder.tileContent == .text {
                    TextField(L("Text or emoji", "Texte ou emoji"), text: store.f(\.tileText, ""))
                        .textFieldStyle(.roundedBorder).font(.system(size: 12.5))
                } else {
                    symbolGrid(selected: folder.tileSymbol)
                }
                PxSliderRow(title: L("Size", "Taille"), value: store.f(\.tileSymbolScale, 1), range: 0.4...2, step: 0.01, unit: "%")
                SliderRow(title: L("Rotation", "Rotation"), value: "\(Int(folder.tileRotation))°",
                          amount: store.f(\.tileRotation, 0), range: -180...180, step: 1)
            }
        }
        ImageControls(store: store, keyPath: \.tileImage, title: L("Background picture", "Image de fond"))
        HStack(spacing: 8) {
            Button { store.shuffleApps() } label: { Label(L("Shuffle apps", "Mélanger les apps"), systemImage: "shuffle").frame(maxWidth: .infinity) }
                .buttonStyle(WellButtonStyle())
            Button { store.saveStyle() } label: { Label(L("Save style", "Enregistrer le style"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                .buttonStyle(WellButtonStyle())
        }
        if !store.document.savedStyles.isEmpty {
            InspectorCard(title: L("My styles", "Mes styles")) {
                ForEach(store.document.savedStyles) { style in
                    HStack(spacing: 8) {
                        TileIcon(folder: style.style, size: 28)
                        Text(style.name).font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Button(L("Apply", "Appliquer")) { store.applyStyle(style) }.buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                        Button { store.deleteStyle(style.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.tertiary).help(L("Delete style", "Supprimer le style"))
                    }
                }
            }
        }
    }

    private func symbolGrid(selected: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("SF Symbol name", "Nom de symbole SF"), text: $symbolQuery)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                .onSubmit {
                    let name = symbolQuery.trimmingCharacters(in: .whitespaces)
                    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                        store.updateSelected { $0.tileSymbol = name }
                    }
                }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button { store.updateSelected { $0.tileSymbol = symbol } } label: {
                        Image(systemName: symbol).font(.system(size: 13))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(symbol == selected ? Theme.accentSoft : Theme.well))
                            .foregroundStyle(symbol == selected ? Theme.accent : Theme.text)
                    }
                    .buttonStyle(.plain).help(symbol)
                }
            }
        }
    }
}

// MARK: - Window

private struct WindowTab: View {
    @ObservedObject var store: GroopStore
    let openShortcuts: () -> Void

    var body: some View {
        let folder = store.selected ?? Folder()
        InspectorCard(title: L("Window colour", "Couleur de la fenêtre")) {
            SwitchRow(title: L("Own colour", "Couleur propre"),
                      info: L("Off: the window takes the icon’s colour", "Désactivé : la fenêtre reprend la couleur de l’icône"),
                      isOn: store.f(\.popupCustom, false))
            if folder.popupCustom {
                SwatchGrid(hex: store.f(\.popupColorHex, "#8E8E93"))
                PxSliderRow(title: L("Opacity", "Opacité"), value: store.f(\.popupOpacity, 0.55), range: 0...1, step: 0.01, unit: "%")
            }
            ChoiceRow(title: L("Surface", "Surface"), options: Surface.allCases, selection: store.f(\.surface, .glass)) { $0.title }
        }
        InspectorCard(title: L("Header", "En-tête")) {
            Picker(L("Folder name", "Nom du dossier"), selection: store.f(\.header, .topLeft)) {
                ForEach(HeaderPosition.allCases) { Text($0.title).tag($0) }
            }
            .font(.system(size: 12.5))
            SwitchRow(title: L("“Open all” button", "Bouton « Tout ouvrir »"), isOn: store.f(\.launchAll, false))
            if folder.launchAll {
                Picker(L("Position", "Position"), selection: store.f(\.launchAllPosition, .topRight)) {
                    ForEach(LaunchAllPosition.allCases) { Text($0.title).tag($0) }
                }
                .font(.system(size: 12.5))
            }
        }
        InspectorCard(title: L("Text", "Police")) {
            ChoiceRow(title: L("Colour", "Couleur"), options: FontColor.allCases, selection: store.f(\.fontColor, .auto)) { $0.title }
            ChoiceRow(title: L("Size", "Taille"), options: SizeStep.allCases, selection: Binding(
                get: { folder.textSize },
                set: { step in
                    let px = Folder.textPx(for: step)
                    store.updateSelected { $0.textSize = step; $0.labelPx = px.label; $0.titlePx = px.title }
                })) { $0.title }
            PxSliderRow(title: L("Title", "Titre"), value: store.f(\.titlePx, 18), range: 10...40, step: 0.5)
            PxSliderRow(title: L("App names", "Noms des apps"), value: store.f(\.labelPx, 12), range: 8...22, step: 0.5)
            SwitchRow(title: L("Show names", "Afficher les noms"), isOn: store.f(\.showNames, true))
            SwitchRow(title: L("Text shadow", "Ombre du texte"), isOn: store.f(\.textShadow, false))
            SwitchRow(title: L("Backdrop behind names", "Fond derrière les noms"), isOn: store.f(\.textBackdrop, false))
        }
        ImageControls(store: store, keyPath: \.windowImage, title: L("Window picture", "Image de la fenêtre"))
        InspectorCard(title: L("Dimensions", "Dimensions")) {
            PxSliderRow(title: L("Corner radius", "Arrondi des coins"), value: store.f(\.cornerRadius, 26), range: 0...60)
            PxSliderRow(title: L("Inner margins", "Marges intérieures"), value: store.f(\.paddingPx, 22), range: 6...60)
            PxSliderRow(title: L("Window size on screen", "Taille de la fenêtre à l’écran"), value: store.f(\.folderScale, 1),
                        range: 0.4...2.2, step: 0.01, unit: "%")
            Text(L("Also right on the window: pinch, ⌘+ / ⌘−, or drag its corner.",
                   "Aussi directement sur la fenêtre : pincez, ⌘+ / ⌘−, ou tirez son coin."))
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
        InspectorCard(title: L("Where it opens", "Où elle s’ouvre")) {
            Picker(L("Position", "Position"), selection: store.f(\.placement, nil)) {
                Text(L("Like the other folders", "Comme les autres dossiers")).tag(Placement?.none)
                Divider()
                ForEach(Placement.allCases) { Text($0.title).tag(Placement?.some($0)) }
            }
            .font(.system(size: 12.5))
            if folder.placement == .remembered {
                Text(folder.windowCenterX == nil
                     ? L("Open the folder, detach it, move it where you want: it opens there from then on.",
                         "Ouvrez le dossier, détachez-le, placez-le où vous voulez : il s’ouvrira là ensuite.")
                     : L("It opens where you last left it. Detach it to move it.",
                         "Elle s’ouvre là où vous l’avez laissée. Détachez-la pour la déplacer."))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
        }
        Button { openShortcuts() } label: {
            Label(L("Keyboard shortcut for this folder…", "Raccourci clavier pour ce dossier…"), systemImage: "command").frame(maxWidth: .infinity)
        }
        .buttonStyle(WellButtonStyle())
    }
}

// MARK: - Grid

private struct GridTab: View {
    @ObservedObject var store: GroopStore

    var body: some View {
        let folder = store.selected ?? Folder()
        let layout = folder.layout(count: folder.apps.count)
        InspectorCard(title: L("Layout", "Disposition")) {
            SwitchRow(title: L("Automatic", "Automatique"),
                      info: L("Columns and rows follow the number of apps", "Colonnes et rangées suivent le nombre d’apps"),
                      isOn: store.f(\.autoLayout, true))
            if !folder.autoLayout {
                GridShapePicker(columns: store.f(\.columns, 4), rows: store.f(\.rowsPerPage, 3))
                StepperRow(title: L("Columns", "Colonnes"), value: store.f(\.columns, 4), range: 1...10)
                StepperRow(title: L("Rows", "Rangées"), value: store.f(\.rowsPerPage, 3), range: 1...8)
            } else {
                Text(L("Now \(layout.columns) × \(layout.rows)", "Actuellement \(layout.columns) × \(layout.rows)"))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
        }
        InspectorCard(title: L("View", "Vue")) {
            Segmented(GridView.allCases, selection: store.f(\.view, .icons)) { $0.title }
            if folder.view == .list {
                StepperRow(title: L("List columns", "Colonnes de liste"), value: store.f(\.listColumns, 1), range: 1...4)
            }
        }
        InspectorCard(title: L("Icon size", "Taille des icônes")) {
            Segmented(SizeStep.allCases, selection: Binding(
                get: { folder.nearestIconStep },
                set: { step in store.updateSelected { $0.iconSize = step; $0.iconPx = Folder.iconPx(for: step) } })) { $0.title }
            PxSliderRow(title: L("Exact size", "Taille exacte"), value: store.f(\.iconPx, 60), range: 28...120)
        }
        InspectorCard(title: L("Spacing", "Espacement")) {
            Segmented(Density.allCases, selection: Binding(
                get: { folder.density },
                set: { density in store.updateSelected { $0.density = density; $0.gapPx = Double(density.gap) } })) { $0.title }
            PxSliderRow(title: L("Gap between apps", "Écart entre les apps"), value: store.f(\.gapPx, 16), range: 0...48)
        }
        InspectorCard(title: L("Pages", "Pages")) {
            HStack(spacing: 6) {
                ForEach(0..<layout.pages, id: \.self) { page in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(page < layout.pages - folder.extraPages ? Theme.accent.opacity(0.75) : Theme.well)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
                        .frame(width: 22, height: 16)
                }
                Spacer()
                Text("\(layout.pages)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                Button { store.updateSelected { $0.extraPages += 1 } } label: {
                    Label(L("Add a page", "Ajouter une page"), systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(WellButtonStyle())
                Button { store.updateSelected { $0.extraPages = max(0, $0.extraPages - 1) } } label: {
                    Label(L("Remove", "Retirer"), systemImage: "minus").frame(maxWidth: .infinity)
                }
                .buttonStyle(WellButtonStyle()).disabled(folder.extraPages == 0)
            }
            SwitchRow(title: L("Hide page dots", "Masquer la pagination"), isOn: store.f(\.hidePagination, false))
        }
    }
}

/// A small grid of cells: hover to preview a shape, click to set columns and rows.
private struct GridShapePicker: View {
    @Binding var columns: Int
    @Binding var rows: Int
    @State private var hover: (Int, Int)?
    private let maxColumns = 8, maxRows = 6

    var body: some View {
        let shown = hover ?? (columns, rows)
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 3) {
                ForEach(0..<maxRows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<maxColumns, id: \.self) { column in
                            let on = column < shown.0 && row < shown.1
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.8) : Theme.well)
                                .frame(height: 18)
                                .onHover { inside in if inside { hover = (column + 1, row + 1) } }
                                .onTapGesture { columns = column + 1; rows = row + 1 }
                        }
                    }
                }
            }
            .onHover { if !$0 { hover = nil } }
            Text("\(shown.0) × \(shown.1)").font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.secondary)
        }
    }
}
