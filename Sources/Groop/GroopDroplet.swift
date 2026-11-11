//
//  GroopDroplet.swift
//  Groop
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(GroopPrincipal)
public final class GroopPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { GroopDroplet() }
}

/// Groop: folders of apps in the Dock. Each folder is a tile among the
/// apps; a click opens its glass window above the tile with the apps in a
/// grid. The studio designs the tile and the window.
@MainActor
public final class GroopDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "groop"

    private var host: DropletHost?
    private(set) var store: GroopStore?
    private var studio: StudioWindowController?
    private let windows = FolderWindowController()
    private var storeChanges: AnyCancellable?
    private var folderChanges: AnyCancellable?
    private var folderShortcuts: [String: String] = [:]

    public override init() { super.init() }

    public func activate(host: DropletHost) throws {
        self.host = host
        let store = GroopStore(root: host.environment.containerDirectory)
        store.callbackBase = host.environment.dropletCallbackURL
        storeChanges = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        self.store = store
        Theme.accentHex = store.settings.accentHex
        store.onSettingsChange = { [weak self] settings in self?.studio?.applyTheme(settings) }
        windows.settings = { [weak store] in store?.settings ?? GroopSettings() }
        windows.onEdit = { [weak self] id in self?.edit(id) }
        windows.onUpdate = { [weak store] id, change in store?.update(id, change) }

        if host.isGranted(.globalShortcuts) {
            host.shortcuts.register(id: "open-studio", title: L("Open the Groop studio", "Ouvrir le studio Groop"),
                                    defaultShortcut: nil) { [weak self] in self?.openStudio() }
            folderChanges = store.$document.receive(on: DispatchQueue.main).sink { [weak self] document in
                MainActor.assumeIsolated { self?.syncShortcuts(document.folders) }
            }
        }
        host.log.info("Groop activated")
    }

    public func deactivate() {
        folderChanges = nil
        folderShortcuts.removeAll()
        windows.close()
        store?.saveNow()
        studio?.close()
        studio = nil
        storeChanges = nil
        store = nil
        host = nil
    }

    // MARK: Actions

    func openStudio() {
        guard let store else { return }
        windows.close()
        if studio == nil {
            studio = StudioWindowController(store: store) { [weak self] in self?.openShortcutSettings() }
        }
        studio?.show()
    }

    func edit(_ id: UUID) {
        store?.selection = id
        openStudio()
    }

    func newFolder() {
        store?.newFolder()
        openStudio()
    }

    /// Opens a folder's window: above the pointer when its Dock tile was
    /// clicked, in the middle of the screen from a shortcut.
    func openFolder(_ id: UUID, anchored: Bool) {
        guard let store, let folder = store.folder(id) else { return }
        if folder.apps.isEmpty { edit(id); return }
        windows.toggle(folder, anchored: anchored)
    }

    private func openShortcutSettings() {
        guard let host else { return }
        if !host.workspace.openShortcuts() { host.workspace.openSettings() }
    }

    /// One shortcut per folder, named after it, that opens its window.
    private func syncShortcuts(_ folders: [Folder]) {
        guard let host, host.isGranted(.globalShortcuts) else { return }
        var wanted: [String: (UUID, String)] = [:]
        for folder in folders {
            wanted["folder-\(folder.id.uuidString.lowercased())"] = (folder.id, L("Open “\(folder.name)”", "Ouvrir « \(folder.name) »"))
        }
        for id in folderShortcuts.keys where wanted[id] == nil {
            host.shortcuts.unregister(id: id)
            folderShortcuts[id] = nil
        }
        for (id, (folderID, title)) in wanted where folderShortcuts[id] != title {
            host.shortcuts.register(id: id, title: title, defaultShortcut: nil) { [weak self] in
                self?.openFolder(folderID, anchored: false)
            }
            folderShortcuts[id] = title
        }
    }

    fileprivate var folders: [Folder] { store?.folders ?? [] }
    fileprivate func isInDock(_ folder: Folder) -> Bool { store?.inDock.contains(folder.id) == true }
}

// MARK: - URLs

extension GroopDroplet: DropletURLHandling {
    /// `open?folder=<id>`, sent by a folder's tile in the Dock: opens its
    /// window above the tile. `studio` opens the studio. Anything else is
    /// ignored.
    public func handle(_ request: DropletURLRequest) {
        switch request.path {
        case "open":
            guard let raw = request.query["folder"], raw.count <= 64, let id = UUID(uuidString: raw) else { return }
            openFolder(id, anchored: true)
        case "studio":
            openStudio()
        default:
            break
        }
    }
}

// MARK: - Settings pane

extension GroopDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(GroopSettingsPane(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [SettingsSearchEntry(title: L("Dock folders", "Dossiers du Dock"),
                             keywords: ["dock", "folder", "dossier", "groop", "apps", "grid", "grille", "launcher"])]
    }
}

private struct GroopSettingsPane: View {
    @ObservedObject var droplet: GroopDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsCard {
                DropletControlRow(title: L("Studio", "Studio"), icon: "square.grid.2x2.fill") {
                    HStack(spacing: 8) {
                        Button(L("New folder", "Nouveau dossier")) { droplet.newFolder() }.buttonStyle(.bordered)
                        Button(L("Open the studio", "Ouvrir le studio")) { droplet.openStudio() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            if let store = droplet.store {
                DropletSettingsSection {
                    settingsSectionHeader(LocalizedStringKey(L("Folder window", "Fenêtre de dossier")))
                } content: {
                    DropletSettingsCard {
                        DropletGroupedPickerRow(title: L("Position on screen", "Position à l’écran")) {
                            Picker("", selection: store.settingBinding(\.placement)) {
                                ForEach(Placement.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        DropletToggleRow(title: L("Close after launch", "Fermer après le lancement"), isOn: store.settingBinding(\.closeAfterLaunch))
                        DropletToggleRow(title: L("Close when the pointer leaves", "Fermer quand le curseur sort"), isOn: store.settingBinding(\.closeOnLeave))
                        DropletToggleRow(title: L("Zoom icons on hover", "Zoom des icônes au survol"), isOn: store.settingBinding(\.hoverZoom))
                        DropletToggleRow(title: L("Always on top", "Toujours au premier plan"), isOn: store.settingBinding(\.keepOnTop))
                        DropletToggleRow(title: L("Page arrows", "Flèches de page"), isOn: store.settingBinding(\.showArrows))
                    }
                }
            }
            DropletSettingsSection {
                settingsSectionHeader(LocalizedStringKey(L("Folders", "Dossiers")))
            } content: {
                DropletSettingsCard {
                    if droplet.folders.isEmpty {
                        DropletControlRow(title: L("No folders yet", "Aucun dossier pour l’instant"), icon: "square.dashed") {
                            Button(L("Create a folder", "Créer un dossier")) { droplet.newFolder() }.buttonStyle(.bordered)
                        }
                    } else {
                        ForEach(droplet.folders) { folder in
                            DropletControlRow(title: folder.name, icon: "square.grid.2x2") {
                                HStack(spacing: 10) {
                                    DropletValuePill(text: droplet.isInDock(folder) ? L("In the Dock", "Dans le Dock")
                                                     : folder.apps.count == 1 ? "1 app" : "\(folder.apps.count) apps")
                                    Button(L("Edit", "Modifier")) { droplet.edit(folder.id) }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Command Center

extension GroopDroplet: MenuBarExtraProviding {
    /// A tile in Droppy's Command Center with the folders the user put
    /// there, so their apps open without the Dock.
    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        let shown = folders.filter(\.inTray)
        guard !shown.isEmpty else { return nil }
        return MenuBarExtraDescriptor(title: "Groop", systemImage: "square.grid.2x2.fill") { [weak self] in
            AnyView(GroopTrayView(droplet: self))
        }
    }
}

private struct GroopTrayView: View {
    weak var droplet: GroopDroplet?

    var body: some View {
        let folders = (droplet?.folders ?? []).filter(\.inTray)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(folders) { folder in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TileIcon(folder: folder, size: 22)
                            Text(folder.name).font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Button { droplet?.openFolder(folder.id, anchored: false) } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help(L("Open the folder’s window", "Ouvrir la fenêtre du dossier"))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 8) {
                            ForEach(folder.apps) { app in
                                Button { NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) } label: {
                                    VStack(spacing: 3) {
                                        Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 34, height: 34)
                                        Text(app.label).font(.system(size: 9.5)).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain).help(app.label)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 320)
    }
}
