//
//  StudioCanvas.swift
//  Groop
//
//  The middle of the studio: the folder as it will look (its Dock tile and
//  its open window) on the user's wallpaper, and the app picker under it.
//

import AppKit
import SwiftUI

enum PreviewBackground: String, CaseIterable, Identifiable {
    case wallpaper, blue, plain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallpaper: L("Wallpaper", "Fond d’écran")
        case .blue: L("Blue", "Bleu")
        case .plain: L("Plain", "Uni")
        }
    }
}

struct StudioCanvas: View {
    @ObservedObject var store: GroopStore
    @State private var pickerShown = false
    @State private var pickerHeight: CGFloat = 300
    @State private var dragStart: CGFloat?
    @State private var background: PreviewBackground = .wallpaper
    @State private var blur: Double = 0
    @State private var tint: Double = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                preview
                    .frame(height: pickerShown ? max(200, geometry.size.height - pickerHeight) : geometry.size.height)
                if pickerShown {
                    AppPicker(store: store, onCollapse: { withAnimation(.spring(response: 0.3)) { pickerShown = false } })
                        .frame(height: min(pickerHeight, geometry.size.height - 200))
                        .background(Theme.panel)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: pickerShown)
            .overlay(alignment: .top) {
                if pickerShown {
                    handle
                        .offset(y: max(200, geometry.size.height - pickerHeight) - 9)
                        .gesture(DragGesture()
                            .onChanged { value in
                                if dragStart == nil { dragStart = pickerHeight }
                                pickerHeight = min(geometry.size.height - 160, max(170, (dragStart ?? 300) - value.translation.height))
                            }
                            .onEnded { _ in dragStart = nil })
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
    }

    private var handle: some View {
        Capsule().fill(.white.opacity(0.55)).frame(width: 36, height: 4)
            .frame(width: 120, height: 18).contentShape(Rectangle())
            .help(L("Drag to resize", "Tirez pour redimensionner"))
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            backdrop
            if let folder = store.selected {
                HStack(alignment: .center, spacing: 22) {
                    dockTile(folder)
                    windowPreview(folder)
                }
                .padding(.horizontal, 30).padding(.vertical, 50)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.6))
                    Text(L("Create a folder to start", "Créez un dossier pour commencer")).foregroundStyle(.white.opacity(0.8))
                    Button(L("New folder", "Nouveau dossier")) { store.newFolder() }.buttonStyle(WellButtonStyle(prominent: true))
                }
            }
        }
        .overlay(alignment: .topLeading) { backgroundMenu.padding(12) }
        .overlay(alignment: .topTrailing) { creatorSwitch.padding(12) }
        .overlay(alignment: .bottom) {
            if !pickerShown {
                Button { withAnimation(.spring(response: 0.3)) { pickerShown = true } } label: {
                    Label("Apps", systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                }
                .buttonStyle(.plain).padding(.bottom, 14)
                .help(L("Show the app picker", "Afficher le sélecteur d’apps"))
            }
        }
        .clipped()
    }

    @ViewBuilder private var backdrop: some View {
        ZStack {
            switch background {
            case .wallpaper:
                if let image = Wallpaper.image {
                    Color.clear.overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).blur(radius: blur)).clipped()
                } else {
                    Color(white: 0.1)
                }
            case .blue:
                LinearGradient(colors: [Color(red: 0.22, green: 0.45, blue: 0.95), Color(red: 0.08, green: 0.18, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .plain:
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(tint)
        }
    }

    private var backgroundMenu: some View {
        Menu {
            Picker(L("Background", "Arrière-plan"), selection: $background) {
                ForEach(PreviewBackground.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Button(L("More blur", "Plus de flou")) { blur = min(30, blur + 6) }
            Button(L("Less blur", "Moins de flou")) { blur = max(0, blur - 6) }
            Button(L("Darker", "Plus sombre")) { tint = min(0.6, tint + 0.1) }
            Button(L("Lighter", "Plus clair")) { tint = max(0, tint - 0.1) }
            Button(L("Reset", "Réinitialiser")) { blur = 0; tint = 0 }
        } label: {
            Image(systemName: "photo.on.rectangle").font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Circle().fill(.black.opacity(0.4)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(L("Preview background", "Arrière-plan de l’aperçu"))
    }

    private var creatorSwitch: some View {
        Toggle("", isOn: store.settingBinding(\.creatorMode))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            .padding(.horizontal, 7).frame(height: 28)
            .background(Capsule().fill(.black.opacity(0.4)))
            .help(L("Creator mode: every setting for the icon, the window and the grid",
                    "Mode créateur : tous les réglages de l’icône, de la fenêtre et de la grille"))
    }

    private func dockTile(_ folder: Folder) -> some View {
        VStack(spacing: 6) {
            TileIcon(folder: folder, size: 76)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.22)))
                .environment(\.colorScheme, .dark)
            Circle().fill(.white.opacity(store.inDock.contains(folder.id) ? 0.85 : 0)).frame(width: 4, height: 4)
        }
        .help(L("This is your folder’s icon in the Dock", "C’est l’icône de votre dossier dans le Dock"))
        .contextMenu {
            Button(store.inDock.contains(folder.id) ? L("Refresh in the Dock", "Actualiser dans le Dock") : L("Pin to the Dock", "Épingler au Dock")) {
                store.pin(folder.id)
            }
        }
    }

    @ViewBuilder private func windowPreview(_ folder: Folder) -> some View {
        if folder.apps.isEmpty {
            VStack(spacing: 6) {
                Text(L("Pick apps\nbelow", "Choisissez\nles apps\nen bas")).font(.system(size: 12.5, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 170, height: 170)
            .background(RoundedRectangle(cornerRadius: CGFloat(folder.cornerRadius), style: .continuous)
                .fill(Color(hex: folder.windowColorHex).opacity(folder.windowOpacity)))
            .background(RoundedRectangle(cornerRadius: CGFloat(folder.cornerRadius), style: .continuous).fill(.ultraThinMaterial))
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
            .onTapGesture { withAnimation(.spring(response: 0.3)) { pickerShown = true } }
            .onDrop(of: [.fileURL, .text], isTargeted: nil, perform: dropApps)
        } else {
            PreviewWindow(store: store, folder: folder)
                .onDrop(of: [.fileURL], isTargeted: nil, perform: dropApps)
        }
    }

    /// Apps dragged from the Finder or the picker join the folder.
    private func dropApps(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let item = AppItem(url: url) else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { store.add([item]) } }
                }
            } else {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let path = object as? String, let item = AppItem(url: URL(fileURLWithPath: path)) else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { store.add([item]) } }
                }
            }
        }
        return true
    }
}

/// The folder's window as a live preview, scaled down to fit the canvas.
private struct PreviewWindow: View {
    @ObservedObject var store: GroopStore
    let folder: Folder
    @StateObject private var model = PopupModel()

    var body: some View {
        let raw = FolderMetrics(folder: folder, count: folder.apps.count).size
        let size = CGSize(width: raw.width * folder.folderScale, height: raw.height * folder.folderScale)
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / size.width, geometry.size.height / size.height) * folder.folderScale
            FolderWindowView(folder: folder, settings: store.settings, model: model, live: false,
                             onLaunch: { _ in }, onEdit: {},
                             onRemove: { store.remove($0) }, onMove: { store.move($0, before: $1) })
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: size.width, maxHeight: size.height)
        .onAppear { model.opened = true }
        .onChange(of: folder.layout(count: folder.apps.count).pages) { _, pages in
            if model.page >= pages { model.page = max(0, pages - 1) }
        }
    }
}

enum Wallpaper {
    @MainActor static var image: NSImage? = {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1400,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }()
}

// MARK: - App picker

struct AppPicker: View {
    @ObservedObject var store: GroopStore
    var onCollapse: () -> Void = {}
    @ObservedObject private var catalog = AppCatalog.shared
    @State private var search = ""
    @State private var searching = false
    @State private var showHidden = false
    @State private var hovered: String?
    @State private var renaming: AppItem?
    @State private var renameText = ""
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool

    private var inFolder: Set<String> { Set(store.selected?.apps.map(\.path) ?? []) }
    private var sort: AppsSort { store.settings.appsSort }
    private var cards: Bool { store.settings.pickerCards }

    private var visible: [AppItem] {
        let hidden = Set(store.settings.hiddenApps)
        let renames = store.settings.appRenames
        let query = search.trimmingCharacters(in: .whitespaces)
        let apps: [AppItem] = catalog.apps.compactMap { app in
            guard showHidden || !hidden.contains(app.path) else { return nil }
            var app = app
            app.customName = renames[app.path]
            guard query.isEmpty || app.label.localizedStandardContains(query) || app.name.localizedStandardContains(query) else { return nil }
            return app
        }
        switch sort {
        case .za: return apps.sorted { $0.label.localizedStandardCompare($1.label) == .orderedDescending }
        default: return apps.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
    }

    private var sections: [(title: String, apps: [AppItem])] {
        let apps = visible
        guard sort == .category else { return [(L("All apps", "Toutes les apps"), apps)] }
        return AppCategory.allCases.compactMap { category in
            let items = apps.filter { $0.category == category }
            return items.isEmpty ? nil : (category.title, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if catalog.loading && catalog.apps.isEmpty {
                    ProgressView().controlSize(.small).padding(.top, 60)
                } else if visible.isEmpty {
                    Text(search.isEmpty ? L("No apps available", "Aucune app disponible") : L("No app for “\(search)”", "Aucune app pour « \(search) »"))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.secondary).padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections, id: \.title) { section in
                            Section {
                                if cards {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 8)], spacing: 8) {
                                        ForEach(section.apps) { app in card(app) }
                                    }
                                    .padding(.horizontal, 14).padding(.bottom, 8)
                                } else {
                                    ForEach(section.apps) { app in row(app) }
                                }
                            } header: {
                                HStack {
                                    Text(section.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                                        .foregroundStyle(Theme.tertiary)
                                    Spacer()
                                    if sort == .category, store.selected != nil {
                                        Button(L("Add category", "Ajouter la catégorie")) { store.add(section.apps) }
                                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 16).frame(height: 26)
                                .background(Theme.panel)
                            }
                        }
                    }
                    .padding(.bottom, 54)
                }
            }
        }
        .overlay(alignment: .bottom) { footer.padding(10) }
        .alert(L("Rename app", "Renommer l’application"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(renaming?.name ?? "", text: $renameText)
            Button(L("Cancel", "Annuler"), role: .cancel) { renaming = nil }
            Button(L("Rename", "Renommer")) { if let app = renaming { store.renameApp(app, to: renameText) }; renaming = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("APP PICKER", "SÉLECTEUR D’APPS")).font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.secondary)
            Button { store.add(visible) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(L("Add all apps", "Ajouter toutes les apps"))
                .disabled(store.selected == nil)
            Spacer()
            if searching {
                HStack(spacing: 6) {
                    TextField(L("Search apps", "Rechercher des apps"), text: $search).textFieldStyle(.plain).font(.system(size: 12))
                        .focused($searchFocused).frame(width: 170)
                    Button { search = ""; searching = false } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.tertiary).help(L("Close search", "Fermer la recherche"))
                }
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: 1) }
            } else {
                Button { searching = true; searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(L("Search apps", "Rechercher des apps"))
                    .keyboardShortcut("f", modifiers: .command)
            }
            Menu {
                Picker(L("Sort apps", "Trier les apps"), selection: store.settingBinding(\.appsSort)) {
                    ForEach(AppsSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle(L("Show hidden apps", "Afficher les masquées"), isOn: $showHidden)
                Button(L("Refresh the list", "Actualiser la liste")) { catalog.load(force: true) }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(L("Sort apps", "Trier les apps"))
        }
        .padding(.horizontal, 16).frame(height: 40)
    }

    private func row(_ app: AppItem) -> some View {
        let added = inFolder.contains(app.path)
        let hidden = store.settings.hiddenApps.contains(app.path)
        return Button { store.toggle(app) } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                Text(app.label).font(.system(size: 12.5)).foregroundStyle(hidden ? Theme.tertiary : Theme.text).lineLimit(1)
                Spacer()
                if added {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else if hovered == app.id {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 16).frame(height: 34)
            .background(hovered == app.id ? Theme.card : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? app.id : (hovered == app.id ? nil : hovered) }
        .help(added ? L("Already in this folder — click to remove", "Déjà dans ce dossier — cliquez pour retirer")
              : L("Click to add or drag into a slot", "Cliquez pour ajouter ou glissez dans un emplacement"))
        .onDrag { NSItemProvider(object: app.path as NSString) }
        .contextMenu { appMenu(app, hidden: hidden) }
    }

    private func card(_ app: AppItem) -> some View {
        let added = inFolder.contains(app.path)
        let hidden = store.settings.hiddenApps.contains(app.path)
        return Button { store.toggle(app) } label: {
            VStack(spacing: 6) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 40, height: 40)
                Text(app.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(hidden ? Theme.tertiary : Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6).frame(maxWidth: .infinity).frame(height: 84)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(added ? Theme.accentSoft : Theme.card))
            .overlay(alignment: .topTrailing) {
                if added { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.accent).padding(5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.label)
        .onDrag { NSItemProvider(object: app.path as NSString) }
        .contextMenu { appMenu(app, hidden: hidden) }
    }

    @ViewBuilder private func appMenu(_ app: AppItem, hidden: Bool) -> some View {
        Button(L("Rename app", "Renommer l’application")) { renameText = app.label; renaming = app }
        if app.customName != nil { Button(L("Restore original name", "Restaurer le nom d’origine")) { store.renameApp(app, to: nil) } }
        Button(hidden ? L("Show app", "Afficher l’application") : L("Hide app", "Masquer l’application")) { store.setHidden(app, !hidden) }
        Button(L("Show in Finder", "Afficher dans le Finder")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let folder = store.selected, !folder.apps.isEmpty {
                HStack(spacing: 8) {
                    Text(L("\(folder.apps.count) added", "\(folder.apps.count) ajoutées")).font(.system(size: 11.5, weight: .medium))
                    Button { confirmClear = true } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).help(L("Clear selection…", "Vider la sélection…"))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(Theme.floating))
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .confirmationDialog(L("Clear everything?", "Tout vider ?"), isPresented: $confirmClear) {
                    Button(L("Clear", "Vider"), role: .destructive) { store.updateSelected { $0.apps.removeAll() } }
                    Button(L("Cancel", "Annuler"), role: .cancel) {}
                }
            }
            Spacer()
            roundButton(cards ? "list.bullet" : "square.grid.2x2", help: cards ? L("List view", "Vue en liste") : L("Card view", "Vue en cartes")) {
                store.settingBinding(\.pickerCards).wrappedValue.toggle()
            }
            roundButton("chevron.down", help: L("Hide", "Masquer"), action: onCollapse)
        }
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(width: 30, height: 28)
                .background(Capsule().fill(Theme.floating))
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain).help(help)
    }
}
