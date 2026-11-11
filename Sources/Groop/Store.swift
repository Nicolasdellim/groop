//
//  Store.swift
//  Groop
//

import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Groop's state: the folders, the one being edited, and what is in the Dock.
@MainActor
final class GroopStore: ObservableObject {
    @Published var document: GroopDocument
    @Published var selection: UUID?
    @Published private(set) var inDock: Set<UUID> = []
    @Published private(set) var busy: Set<UUID> = []
    /// Folders whose look changed since they were put in the Dock.
    @Published private(set) var stale: Set<UUID> = []
    @Published var message: String?
    @Published var error: String?

    /// Where a tile sends its click: `droppy://droplet/groop`. Set by the
    /// droplet from the host; without it nothing can be pinned.
    var callbackBase: URL?

    let service: DockService
    private let queue = DispatchQueue(label: "app.getdroppy.groop.dock")
    private var saveWork: DispatchWorkItem?

    init(root: URL) {
        service = DockService(root: root)
        document = service.load()
        Theme.accentHex = document.settings.accentHex
        ImageCache.shared.directory = root.appendingPathComponent("Images", isDirectory: true)
        selection = document.folders.first?.id
        refreshDockState()
    }

    var folders: [Folder] { document.folders }
    var settings: GroopSettings {
        get { document.settings }
        set { document.settings = newValue; Theme.accentHex = newValue.accentHex; scheduleSave() }
    }

    /// Called whenever the app-wide settings change, so the studio window
    /// can follow the theme.
    var onSettingsChange: (GroopSettings) -> Void = { _ in }

    var selected: Folder? {
        guard let selection else { return nil }
        return document.folders.first { $0.id == selection }
    }

    func folder(_ id: UUID) -> Folder? { document.folders.first { $0.id == id } }

    /// A binding to one field of the selected folder, saved as it changes.
    func binding<T>(_ keyPath: WritableKeyPath<Folder, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { self.selected?[keyPath: keyPath] ?? fallback },
            set: { value in self.updateSelected { $0[keyPath: keyPath] = value } }
        )
    }

    func settingBinding<T>(_ keyPath: WritableKeyPath<GroopSettings, T>) -> Binding<T> {
        Binding(get: { self.document.settings[keyPath: keyPath] },
                set: {
                    self.document.settings[keyPath: keyPath] = $0
                    Theme.accentHex = self.document.settings.accentHex
                    self.onSettingsChange(self.document.settings)
                    self.scheduleSave()
                })
    }

    func updateSelected(_ change: (inout Folder) -> Void) {
        guard let selection else { return }
        update(selection, change)
    }

    func update(_ id: UUID, _ change: (inout Folder) -> Void) {
        guard let index = document.folders.firstIndex(where: { $0.id == id }) else { return }
        let before = document.folders[index]
        change(&document.folders[index])
        if before.tileSignature != document.folders[index].tileSignature, inDock.contains(id) { stale.insert(id) }
        scheduleSave()
    }

    // MARK: Folders

    @discardableResult
    func newFolder(apps: [AppItem] = []) -> Folder {
        var folder = Folder()
        if let preset = Presets.preset("glass-grey") { folder = preset.styled(folder) }
        folder.name = uniqueName(L("New folder", "Nouveau dossier"))
        folder.apps = apps
        document.folders.insert(folder, at: 0)
        selection = folder.id
        scheduleSave()
        return folder
    }

    func duplicate(_ id: UUID) {
        guard var copy = folder(id), let index = document.folders.firstIndex(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.createdAt = Date()
        copy.name = uniqueName(copy.name + L(" copy", " (copie)"))
        document.folders.insert(copy, at: index + 1)
        selection = copy.id
        scheduleSave()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    func delete(_ id: UUID) {
        if inDock.contains(id) { unpin(id) }
        document.folders.removeAll { $0.id == id }
        if selection == id { selection = document.folders.first?.id }
        let service = service
        queue.async { service.removeLauncher(for: id) }
        scheduleSave()
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids { delete(id) }
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(document.folders.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Apps

    func add(_ apps: [AppItem], to id: UUID? = nil) {
        guard let id = id ?? selection else {
            newFolder(apps: apps)
            return
        }
        update(id) { folder in
            let existing = Set(folder.apps.map(\.path))
            folder.apps.append(contentsOf: apps.filter { !existing.contains($0.path) })
        }
    }

    func remove(_ app: AppItem, from id: UUID? = nil) {
        guard let id = id ?? selection else { return }
        update(id) { $0.apps.removeAll { $0.path == app.path } }
    }

    func toggle(_ app: AppItem) {
        guard let selected else { add([app]); return }
        if selected.apps.contains(where: { $0.path == app.path }) { remove(app) } else { add([app]) }
    }

    /// Moves `app` to where `target` is. An app dragged in from the picker
    /// that is not in the folder yet joins it there.
    func move(_ app: AppItem, before target: AppItem) {
        let resolved = app.name.isEmpty ? (AppItem(url: URL(fileURLWithPath: app.path)) ?? app) : app
        updateSelected { folder in
            guard let to = folder.apps.firstIndex(where: { $0.path == target.path }) else { return }
            if let from = folder.apps.firstIndex(where: { $0.path == resolved.path }) {
                guard from != to else { return }
                let item = folder.apps.remove(at: from)
                folder.apps.insert(item, at: to)
            } else {
                folder.apps.insert(resolved, at: to)
            }
        }
    }

    // MARK: Pictures

    var imagesDirectory: URL { service.root.appendingPathComponent("Images", isDirectory: true) }

    /// Copies a picture into Groop's folder and returns its file name.
    func importImage(from url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            error = L("This file is not a picture.", "Ce fichier n’est pas une image.")
            return nil
        }
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: imagesDirectory.appendingPathComponent(name))) != nil else { return nil }
        return name
    }

    func image(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        return ImageCache.shared.image(imagesDirectory.appendingPathComponent(name))
    }

    /// Asks for a picture and puts it behind the tile or the window.
    func chooseImage(for target: WritableKeyPath<Folder, ImageStyle?>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = L("Choose", "Choisir")
        guard panel.runModal() == .OK, let url = panel.url, let name = importImage(from: url) else { return }
        updateSelected { $0[keyPath: target] = ImageStyle(file: name) }
    }

    // MARK: Command Center

    func setInTray(_ id: UUID, _ on: Bool) {
        update(id) { $0.inTray = on }
        message = on ? L("Added to the Command Center", "Ajouté au Centre de contrôle de Droppy")
                     : L("Removed from the Command Center", "Retiré du Centre de contrôle de Droppy")
    }

    func renameApp(_ app: AppItem, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in document.folders.indices {
            for appIndex in document.folders[index].apps.indices where document.folders[index].apps[appIndex].path == app.path {
                document.folders[index].apps[appIndex].customName = trimmed?.isEmpty == false ? trimmed : nil
            }
        }
        document.settings.appRenames[app.path] = trimmed?.isEmpty == false ? trimmed : nil
        scheduleSave()
    }

    func setHidden(_ app: AppItem, _ hidden: Bool) {
        if hidden { if !document.settings.hiddenApps.contains(app.path) { document.settings.hiddenApps.append(app.path) } }
        else { document.settings.hiddenApps.removeAll { $0 == app.path } }
        scheduleSave()
    }

    // MARK: Styles

    func apply(_ preset: Preset) {
        updateSelected { $0 = preset.styled($0) }
    }

    func saveStyle() {
        guard let selected else { return }
        document.savedStyles.insert(SavedStyle(name: selected.name, style: selected), at: 0)
        message = L("Style saved", "Style enregistré")
        scheduleSave()
    }

    func applyStyle(_ style: SavedStyle) {
        updateSelected { $0 = $0.applyingStyle(of: style.style) }
    }

    func deleteStyle(_ id: UUID) {
        document.savedStyles.removeAll { $0.id == id }
        scheduleSave()
    }

    func shuffleApps() {
        updateSelected { $0.apps.shuffle() }
    }

    private var previousBeforeRandom: Folder?

    func randomStyle() {
        guard let selected else { return }
        previousBeforeRandom = selected
        updateSelected { f in
            f.iconStyle = IconStyle.allCases.randomElement()!
            f.colorHex = Palette.swatches.randomElement()!
            f.opacity = Double.random(in: 0.25...0.9)
            f.glossy = Bool.random()
            f.lift = Bool.random()
            f.dense = Bool.random()
            f.roundIcons = Bool.random()
            f.tileSymbol = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "moon.fill", "sparkles", "music.note"].randomElement()!
            f.presetID = nil
        }
    }

    var canRestoreRandom: Bool { previousBeforeRandom?.id == selection }

    func restoreRandom() {
        guard let previous = previousBeforeRandom, previous.id == selection else { return }
        updateSelected { $0 = previous }
        previousBeforeRandom = nil
    }

    // MARK: Dock

    func refreshDockState() {
        let ids = document.folders.map(\.id)
        let service = service
        queue.async {
            let found = service.foldersInDock(ids)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.inDock = found } }
        }
    }

    /// Writes the folder's launcher and puts it in the Dock (or refreshes it).
    func pin(_ id: UUID) {
        guard let folder = folder(id) else { return }
        guard !folder.apps.isEmpty else { error = DockError.noApps.localizedDescription; return }
        guard let base = callbackBase,
              var components = URLComponents(url: base.appendingPathComponent("open"), resolvingAgainstBaseURL: false) else {
            error = L("Groop can only pin folders while it runs inside Droppy.", "Groop ne peut épingler un dossier que dans Droppy.")
            return
        }
        components.queryItems = [URLQueryItem(name: "folder", value: folder.id.uuidString)]
        guard let openURL = components.url else { return }
        let icon = TileIcon.pngData(for: folder)
        let service = service
        busy.insert(id)
        queue.async {
            do {
                try service.writeLauncher(for: folder, iconPNG: icon, openURL: openURL)
                service.putInDock(folder)
                service.restartDock()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.busy.remove(id)
                        self.stale.remove(id)
                        self.inDock.insert(id)
                        self.message = L("Pinned to the Dock", "Épinglé au Dock")
                    }
                }
            } catch {
                let text = error.localizedDescription
                DispatchQueue.main.async { MainActor.assumeIsolated { self.busy.remove(id); self.error = text } }
            }
        }
    }

    func unpin(_ id: UUID) {
        let service = service
        inDock.remove(id)
        stale.remove(id)
        queue.async {
            service.removeFromDock(id)
            service.restartDock()
            service.removeLauncher(for: id)
        }
        message = L("Removed from the Dock", "Retiré du Dock")
    }

    // MARK: Saving

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do { try service.save(document) } catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    /// Where Groop keeps its pictures, set by the store.
    var directory: URL?

    func image(named name: String?) -> NSImage? {
        guard let name, let directory else { return nil }
        return image(directory.appendingPathComponent(name))
    }
    private var cache: [URL: NSImage] = [:]

    func image(_ url: URL) -> NSImage? {
        if let image = cache[url] { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[url] = image
        return image
    }
}
