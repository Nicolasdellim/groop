//
//  Studio.swift
//  Groop
//
//  The studio: presets and folders on the left, the preview and the app
//  picker in the middle, the inspector on the right in creator mode.
//

import AppKit
import SwiftUI

// MARK: - Window

@MainActor
final class StudioWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: GroopStore
    private let openShortcuts: () -> Void

    init(store: GroopStore, openShortcuts: @escaping () -> Void) {
        self.store = store
        self.openShortcuts = openShortcuts
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Groop"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(Theme.window)
            window.contentMinSize = NSSize(width: 820, height: 600)
            window.contentView = NSHostingView(rootView: StudioView(store: store, openShortcuts: openShortcuts))
            window.delegate = self
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.setFrameAutosaveName("GroopStudio")
            if !window.setFrameUsingName("GroopStudio") { window.center() }
            self.window = window
        }
        applyTheme(store.settings)
        store.refreshDockState()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func applyTheme(_ settings: GroopSettings) {
        switch settings.theme {
        case .system: window?.appearance = nil
        case .light: window?.appearance = NSAppearance(named: .aqua)
        case .dark: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { store.refreshDockState() }

    func windowWillClose(_ notification: Notification) { store.saveNow() }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
    }
}

// MARK: - Root

struct StudioView: View {
    @ObservedObject var store: GroopStore
    let openShortcuts: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Sidebar(store: store, openShortcuts: openShortcuts).frame(width: 236)
            StudioCanvas(store: store).frame(maxWidth: .infinity)
            if store.settings.creatorMode {
                Inspector(store: store, openShortcuts: openShortcuts)
                    .frame(width: 286)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.settings.creatorMode)
        .padding(8).padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .overlay(alignment: .top) { Toast(store: store).padding(.top, 14) }
        .tint(Theme.accent)
        .onAppear { AppCatalog.shared.load() }
    }
}

/// A short confirmation or an error, at the top of the window.
private struct Toast: View {
    @ObservedObject var store: GroopStore

    var body: some View {
        let text = store.error ?? store.message
        Group {
            if let text {
                HStack(spacing: 8) {
                    Image(systemName: store.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.error == nil ? Theme.accent : .orange)
                    Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Theme.floating))
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.error = nil; store.message = nil }
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(store.error == nil ? 2 : 5))
                    withAnimation { store.error = nil; store.message = nil }
                }
            }
        }
        .animation(.spring(response: 0.3), value: text)
    }
}

// MARK: - Sidebar

private enum SidebarTab: Hashable { case presets, folders }

struct Sidebar: View {
    @ObservedObject var store: GroopStore
    let openShortcuts: () -> Void
    @State private var tab: SidebarTab = .presets
    @State private var showSettings = false
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var selecting = false
    @State private var picked: Set<UUID> = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain).help(L("Settings (⌘,)", "Réglages (⌘,)"))
                .keyboardShortcut(",", modifiers: .command)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    GlobalSettings(store: store, openShortcuts: openShortcuts).frame(width: 320)
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 12).padding(.top, 6)

            headerCard.padding(.horizontal, 8).padding(.top, 6)

            HStack(spacing: 14) {
                tabButton(L("Presets", "Préréglages"), .presets)
                tabButton(L("My folders", "Mes dossiers"), .folders)
                Spacer()
                Button { store.newFolder(); tab = .presets } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain).help(L("Create a new folder", "Créer un nouveau dossier"))
                .keyboardShortcut("n", modifiers: [.control, .option])
            }
            .padding(.horizontal, 14).padding(.top, 14)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, 8)

            ScrollView {
                switch tab {
                case .presets: presets
                case .folders: folders
                }
            }
            if tab == .folders, !store.folders.isEmpty { selectBar }
        }
        .panel()
    }

    private func tabButton(_ title: String, _ value: SidebarTab) -> some View {
        Button { tab = value; selecting = false; picked = [] } label: {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(tab == value ? Theme.text : Theme.tertiary)
                Rectangle().fill(tab == value ? Theme.accent : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    @ViewBuilder private var headerCard: some View {
        if let folder = store.selected {
            let pinned = store.inDock.contains(folder.id)
            let stale = store.stale.contains(folder.id)
            VStack(spacing: 10) {
            HStack(spacing: 10) {
                TileIcon(folder: folder, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(pinned ? (stale ? L("Changed — refresh", "Modifié — actualiser") : L("Pinned!", "Épinglé !"))
                         : (Presets.preset(folder.presetID)?.name ?? L("Your own style", "Votre style")))
                        .font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                Spacer(minLength: 4)
                if pinned && !store.busy.contains(folder.id) {
                    Button { store.unpin(folder.id) } label: { Image(systemName: "pin.slash").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(L("Remove from the Dock", "Retirer du Dock"))
                }
            }
            dockButton(folder, pinned: pinned, stale: stale)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentSoft))
        } else {
            Button { store.newFolder() } label: {
                Label(L("Create your first folder", "Créez votre premier dossier"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(WellButtonStyle(prominent: true))
        }
    }

    /// The one obvious way into the Dock: add, refresh after a change, or
    /// a quiet confirmation once it is there.
    @ViewBuilder private func dockButton(_ folder: Folder, pinned: Bool, stale: Bool) -> some View {
        if store.busy.contains(folder.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Adding to the Dock…", "Ajout au Dock…")).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 28)
        } else if !pinned || stale {
            Button { store.pin(folder.id) } label: {
                Label(pinned ? L("Refresh in the Dock", "Actualiser dans le Dock") : L("Add to the Dock", "Ajouter au Dock"),
                      systemImage: pinned ? "arrow.clockwise" : "dock.arrow.down.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WellButtonStyle(prominent: true))
            .disabled(folder.apps.isEmpty)
            .help(folder.apps.isEmpty ? L("Add apps first", "Ajoutez d’abord des apps") : L("⌥⌘P", "⌥⌘P"))
            .keyboardShortcut("p", modifiers: [.option, .command])
        } else {
            Label(L("In the Dock — click its tile", "Dans le Dock — cliquez sa tuile"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity).frame(height: 28)
        }
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.document.savedStyles.isEmpty {
                section(L("Made by you", "Fait par vous")) {
                    ForEach(store.document.savedStyles) { saved in
                        card(name: saved.name, folder: (store.selected ?? Folder()).applyingStyle(of: saved.style), selected: false) {
                            if store.selected == nil { store.newFolder() }
                            store.applyStyle(saved)
                        }
                        .contextMenu {
                            Button(L("Apply this style", "Appliquer ce style")) { store.applyStyle(saved) }
                            Button(L("Delete saved style", "Supprimer le style enregistré"), role: .destructive) { store.deleteStyle(saved.id) }
                        }
                    }
                }
            }
            ForEach(PresetGroup.allCases) { group in
                section(group.title) {
                    ForEach(Presets.all.filter { $0.group == group }) { preset in
                        let base = store.selected ?? Folder()
                        card(name: preset.name, folder: preset.styled(base), selected: base.presetID == preset.id) {
                            if store.selected == nil { store.newFolder() }
                            store.apply(preset)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { store.randomStyle() } label: {
                    Label(L("Shuffle styles", "Mélanger les styles"), systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(WellButtonStyle())
                if store.canRestoreRandom {
                    Button { store.restoreRandom() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(WellButtonStyle()).help(L("Restore previous", "Restaurer le précédent"))
                }
            }
            .disabled(store.selected == nil)
        }
        .padding(10)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) { content() }
        }
    }

    private func card(name: String, folder: Folder, selected: Bool, checked: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                TileIcon(folder: folder, size: 52)
                Text(name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity).frame(height: 90)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.accentSoft : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let checked {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14)).foregroundStyle(checked ? Theme.accent : Theme.tertiary).padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Folders

    private var folders: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.tertiary)
                    Text(L("Create your first folder", "Créez votre premier dossier")).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    Button(L("New folder", "Nouveau dossier")) { store.newFolder(); tab = .presets }.buttonStyle(WellButtonStyle(prominent: true))
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            }
            ForEach(dateSections, id: \.title) { section in
                self.section(section.title) {
                    ForEach(section.folders) { folder in
                        let pinned = store.inDock.contains(folder.id)
                        card(name: folder.name, folder: folder, selected: !selecting && store.selection == folder.id,
                             checked: selecting ? picked.contains(folder.id) : nil) {
                            if selecting {
                                if picked.contains(folder.id) { picked.remove(folder.id) } else { picked.insert(folder.id) }
                            } else {
                                store.selection = folder.id
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if pinned && !selecting {
                                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.accent).padding(7)
                            }
                        }
                        .contextMenu { folderMenu(folder) }
                    }
                }
            }
        }
        .padding(10)
        .alert(L("Rename folder", "Renommer le dossier"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Folder name", "Nom du dossier"), text: $renameText)
            Button(L("Cancel", "Annuler"), role: .cancel) { renaming = nil }
            Button(L("Rename", "Renommer")) { if let id = renaming { store.rename(id, to: renameText) }; renaming = nil }
        }
    }

    private var selectBar: some View {
        HStack(spacing: 8) {
            if selecting {
                Button(L("Cancel", "Annuler")) { selecting = false; picked = [] }.buttonStyle(WellButtonStyle())
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text(picked.isEmpty ? L("Delete", "Supprimer") : L("Delete \(picked.count)", "Supprimer (\(picked.count))"))
                }
                .buttonStyle(WellButtonStyle(prominent: !picked.isEmpty)).disabled(picked.isEmpty)
            } else {
                Button(L("Select", "Sélectionner")) { selecting = true }.buttonStyle(WellButtonStyle())
            }
        }
        .padding(10)
        .confirmationDialog(L("Delete the selected folders?", "Supprimer les dossiers sélectionnés ?"), isPresented: $confirmDelete) {
            Button(L("Delete selection", "Supprimer la sélection"), role: .destructive) {
                store.delete(picked); picked = []; selecting = false
            }
            Button(L("Cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(L("Their tiles leave the Dock too.", "Leurs tuiles quittent aussi le Dock."))
        }
    }

    private var dateSections: [(title: String, folders: [Folder])] {
        let calendar = Calendar.current
        let now = Date()
        func bucket(_ date: Date) -> Int {
            if calendar.isDateInToday(date) { return 0 }
            if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return 1 }
            if calendar.isDate(date, equalTo: now, toGranularity: .month) { return 2 }
            if calendar.isDate(date, equalTo: now, toGranularity: .year) { return 3 }
            return 4
        }
        let titles = [L("Today", "Aujourd’hui"), L("This week", "Cette semaine"), L("This month", "Ce mois-ci"),
                      L("This year", "Cette année"), L("Earlier", "Plus tôt")]
        let sorted = store.folders.sorted { $0.createdAt > $1.createdAt }
        return (0..<5).compactMap { index in
            let items = sorted.filter { bucket($0.createdAt) == index }
            return items.isEmpty ? nil : (titles[index], items)
        }
    }

    @ViewBuilder private func folderMenu(_ folder: Folder) -> some View {
        let pinned = store.inDock.contains(folder.id)
        Button(L("Edit", "Modifier")) { store.selection = folder.id }
        Button(L("Duplicate", "Dupliquer")) { store.duplicate(folder.id) }
        Button(L("Rename", "Renommer")) { renameText = folder.name; renaming = folder.id }
        Divider()
        if pinned {
            Button(L("Refresh in the Dock", "Actualiser dans le Dock")) { store.pin(folder.id) }
            Button(L("Remove from the Dock", "Retirer du Dock")) { store.unpin(folder.id) }
        } else {
            Button(L("Pin to the Dock", "Épingler au Dock")) { store.pin(folder.id) }
        }
        Button(folder.inTray ? L("Remove from the Command Center", "Retirer du Centre de contrôle")
                             : L("Pin to the Command Center", "Épingler au Centre de contrôle")) {
            store.setInTray(folder.id, !folder.inTray)
        }
        Divider()
        Button(L("Delete", "Supprimer"), role: .destructive) { store.delete(folder.id) }
    }
}

// MARK: - Global settings

struct GlobalSettings: View {
    @ObservedObject var store: GroopStore
    let openShortcuts: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                InspectorCard(title: L("General", "Général")) {
                    SwitchRow(title: L("Creator mode", "Mode créateur"),
                              info: L("Shows the inspector with every setting for the icon, the window and the grid.",
                                      "Affiche l’inspecteur avec tous les réglages de l’icône, de la fenêtre et de la grille."),
                              isOn: store.settingBinding(\.creatorMode))
                }
                InspectorCard(title: L("Appearance", "Apparence")) {
                    ChoiceRow(title: L("Theme", "Thème"), options: StudioTheme.allCases, selection: store.settingBinding(\.theme), name: \.title)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Accent colour", "Couleur d’accent")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        HStack(spacing: 8) {
                            ForEach(Theme.accents, id: \.0) { hex, name in
                                let on = store.settings.accentHex == hex
                                Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                    .padding(2).overlay(Circle().strokeBorder(on ? Color(hex: hex) : .clear, lineWidth: 1.5))
                                    .help(name)
                                    .onTapGesture { store.settingBinding(\.accentHex).wrappedValue = hex }
                            }
                        }
                    }
                }
                InspectorCard(title: L("Folder window", "Fenêtre de dossier")) {
                    Picker(L("Position on screen", "Position à l’écran"), selection: store.settingBinding(\.placement)) {
                        ForEach(Placement.allCases) { Text($0.title).tag($0) }
                    }
                    .font(.system(size: 12.5))
                    PxSliderRow(title: L("Window scale", "Échelle de la fenêtre"), value: store.settingBinding(\.windowScale),
                                range: 0.6...1.6, step: 0.05, unit: "%")
                    SwitchRow(title: L("Parallax in the open folder", "Parallaxe dans le dossier ouvert"),
                              info: L("The window’s picture follows the pointer.", "L’image de la fenêtre suit le curseur."),
                              isOn: store.settingBinding(\.parallax))
                    if store.settings.parallax {
                        PxSliderRow(title: L("Strength", "Intensité"), value: store.settingBinding(\.parallaxStrength), range: 0.2...2, step: 0.1, unit: "%")
                        ChoiceRow(title: L("Direction", "Direction"), options: ParallaxDirection.allCases,
                                  selection: store.settingBinding(\.parallaxDirection), name: \.title)
                        SwitchRow(title: L("Invert", "Inverser le sens"),
                                  info: L("The picture follows the pointer instead of moving away.",
                                          "L’arrière-plan suit le curseur au lieu d’aller à l’inverse."),
                                  isOn: store.settingBinding(\.parallaxInvert))
                    }
                }
                InspectorCard(title: L("Behaviour", "Comportement")) {
                    SwitchRow(title: L("Close after launch", "Fermer après le lancement"), isOn: store.settingBinding(\.closeAfterLaunch))
                    SwitchRow(title: L("Close when the pointer leaves", "Fermer quand le curseur sort"), isOn: store.settingBinding(\.closeOnLeave))
                    SwitchRow(title: L("Zoom icons on hover", "Zoom des icônes au survol"), isOn: store.settingBinding(\.hoverZoom))
                    SwitchRow(title: L("Always on top", "Toujours au premier plan"), isOn: store.settingBinding(\.keepOnTop))
                    SwitchRow(title: L("Page arrows", "Flèches de page"), isOn: store.settingBinding(\.showArrows))
                    ChoiceRow(title: L("Page swipe speed", "Vitesse de défilement des pages"), options: SwipeSpeed.allCases,
                              selection: store.settingBinding(\.swipeSpeed), name: \.title)
                }
                InspectorCard(title: L("Shortcuts", "Raccourcis")) {
                    HStack {
                        Text(L("Open the studio, each folder", "Ouvrir le studio, chaque dossier")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button(L("Set…", "Régler…"), action: openShortcuts).buttonStyle(WellButtonStyle())
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 620)
        .background(Theme.panel)
        .tint(Theme.accent)
    }
}
