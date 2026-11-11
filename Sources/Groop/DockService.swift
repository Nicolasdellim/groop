//
//  DockService.swift
//  Groop
//
//  A folder lives in the Dock as a tiny launcher app among the apps
//  (`persistent-apps`). A click opens `droppy://droplet/groop/open?folder=…`
//  and Groop shows the folder's window above the tile. The launcher is an
//  AppleScript applet made with `osacompile`, which every Mac has, so Groop
//  ships no executable.
//

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DockError: LocalizedError {
    case noApps, failed(String)
    var errorDescription: String? {
        switch self {
        case .noApps: L("Add at least one app to the folder.", "Ajoutez au moins une app au dossier.")
        case .failed(let detail): L("Couldn’t make the folder’s Dock tile: \(detail)", "Impossible de créer la tuile du dossier : \(detail)")
        }
    }
}

/// File and Dock work, called off the main actor.
struct DockService: Sendable {
    let root: URL

    var launchersDirectory: URL { root.appendingPathComponent("Launchers", isDirectory: true) }
    var backupsDirectory: URL { root.appendingPathComponent("Dock Backups", isDirectory: true) }
    var storeURL: URL { root.appendingPathComponent("groop.json") }

    static func bundleID(for id: UUID) -> String { "app.getdroppy.groop.folder.\(id.uuidString.lowercased())" }

    /// The launcher's file name: the folder's name, made safe for a path.
    static func fileName(for folder: Folder) -> String {
        let cleaned = folder.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Groop" : String(cleaned.prefix(60))
    }

    func launcher(for folder: Folder) -> URL {
        launchersDirectory.appendingPathComponent(folder.id.uuidString, isDirectory: true)
            .appendingPathComponent(Self.fileName(for: folder) + ".app", isDirectory: true)
    }

    // MARK: Store

    func load() -> GroopDocument {
        guard let data = try? Data(contentsOf: storeURL),
              let document = try? JSONDecoder().decode(GroopDocument.self, from: data) else { return GroopDocument() }
        return document
    }

    func save(_ document: GroopDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: storeURL, options: .atomic)
    }

    // MARK: Launcher

    /// Builds the folder's launcher: an applet that opens `openURL`, named
    /// after the folder, with the folder's tile as its icon.
    func writeLauncher(for folder: Folder, iconPNG: Data?, openURL: URL) throws {
        let fm = FileManager.default
        let app = launcher(for: folder)
        let directory = app.deletingLastPathComponent()
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = "open location \"\(openURL.absoluteString.replacingOccurrences(of: "\"", with: ""))\""
        try run("/usr/bin/osacompile", ["-o", app.path, "-e", script])

        // An agent app: no menu bar, no running dot, no bounce; the tile stays.
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DockError.failed("Info.plist")
        }
        let name = Self.fileName(for: folder)
        plist["CFBundleIdentifier"] = Self.bundleID(for: folder.id)
        plist["CFBundleName"] = name
        plist["CFBundleDisplayName"] = name
        plist["LSUIElement"] = true
        plist["CFBundleIconFile"] = "applet"
        plist.removeValue(forKey: "CFBundleIconName")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        try? fm.removeItem(at: app.appendingPathComponent("Contents/Resources/Assets.car"))

        if let iconPNG { try writeICNS(iconPNG, to: app.appendingPathComponent("Contents/Resources/applet.icns")) }
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
        try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                 ["-f", app.path])
    }

    func removeLauncher(for id: UUID) {
        let directory = launchersDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    /// An .icns with every size the Dock asks for, from one 1024 PNG.
    private func writeICNS(_ png: Data, to url: URL) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString, 6, nil) else {
            throw DockError.failed("icns")
        }
        for side in [16, 32, 128, 256, 512, 1024] {
            guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .high
            context.draw(full, in: CGRect(x: 0, y: 0, width: side, height: side))
            if let scaled = context.makeImage() { CGImageDestinationAddImage(destination, scaled, nil) }
        }
        guard CGImageDestinationFinalize(destination) else { throw DockError.failed("icns") }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            throw DockError.failed(L("\(URL(fileURLWithPath: tool).lastPathComponent) took too long",
                                     "\(URL(fileURLWithPath: tool).lastPathComponent) a mis trop de temps"))
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DockError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Dock

    private static var domain: CFString { "com.apple.dock" as CFString }
    private static var appsKey: CFString { "persistent-apps" as CFString }

    private func tiles() -> [[String: Any]] {
        CFPreferencesAppSynchronize(Self.domain)
        return (CFPreferencesCopyAppValue(Self.appsKey, Self.domain) as? [[String: Any]]) ?? []
    }

    private func write(_ tiles: [[String: Any]]) {
        CFPreferencesSetAppValue(Self.appsKey, tiles as CFArray, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
    }

    private static func url(of tile: [String: Any]) -> String? {
        ((tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])?["_CFURLString"] as? String
    }

    private static func isLauncher(_ url: String, of id: UUID) -> Bool {
        url.contains("/Launchers/\(id.uuidString)/")
    }

    /// The folders that have a tile in the Dock right now.
    func foldersInDock(_ ids: [UUID]) -> Set<UUID> {
        let urls = tiles().compactMap(Self.url(of:))
        return Set(ids.filter { id in urls.contains { Self.isLauncher($0, of: id) } })
    }

    private func tile(for folder: Folder) -> [String: Any] {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": URL(fileURLWithPath: launcher(for: folder).path, isDirectory: true).absoluteString,
                              "_CFURLStringType": 15],
                "file-label": Self.fileName(for: folder),
                "bundle-identifier": Self.bundleID(for: folder.id),
                "file-type": 41,
            ] as [String: Any],
        ]
    }

    /// Adds the folder's tile, or updates it where it already is.
    func putInDock(_ folder: Folder) {
        backupDock()
        var apps = tiles()
        if let index = apps.firstIndex(where: { Self.url(of: $0).map { Self.isLauncher($0, of: folder.id) } == true }) {
            apps[index] = tile(for: folder)
        } else {
            apps.append(tile(for: folder))
        }
        write(apps)
    }

    func removeFromDock(_ id: UUID) {
        backupDock()
        write(tiles().filter { Self.url(of: $0).map { !Self.isLauncher($0, of: id) } ?? true })
    }

    /// Keeps the ten latest copies of the Dock's preferences before any write.
    private func backupDock() {
        let fm = FileManager.default
        let source = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? fm.copyItem(at: source, to: backupsDirectory.appendingPathComponent("com.apple.dock \(stamp).plist"))
        let backups = ((try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(10) { try? fm.removeItem(at: old) }
    }

    /// The Dock reads its tiles only when it starts; it is back in a second.
    func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
