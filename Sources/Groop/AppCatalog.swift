//
//  AppCatalog.swift
//  Groop
//

import AppKit

/// The apps installed on the Mac, read once off the main actor.
@MainActor
final class AppCatalog: ObservableObject {
    static let shared = AppCatalog()
    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var loading = false

    func load(force: Bool = false) {
        guard (apps.isEmpty || force), !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppCatalog.scan()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.apps = found; self.loading = false } }
        }
    }

    private nonisolated static func scan() -> [AppItem] {
        let fm = FileManager.default
        let roots = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                     "/System/Applications", "/System/Applications/Utilities"]
        var seen = Set<String>(), found: [AppItem] = []
        func scan(_ folder: URL, depth: Int) {
            guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { return }
            for url in urls {
                if url.pathExtension.lowercased() == "app" {
                    if let item = AppItem(url: url), seen.insert(item.path).inserted { found.append(item) }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    scan(url, depth: depth - 1)
                }
            }
        }
        for root in roots { scan(URL(fileURLWithPath: root), depth: 1) }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
