//
//  FolderWindow.swift
//  Groop
//
//  The folder's window: a glass card above the Dock tile with the folder's
//  name and its apps in pages of a grid, a list or tiles. The same view is
//  the live window and the studio's preview.
//

import AppKit
import SwiftUI

// MARK: - Model

@MainActor
final class PopupModel: ObservableObject {
    @Published var page = 0
    @Published var opened = false
    @Published var hovered: String?
    /// Where the pointer is over the window, from -1 to 1 on each axis.
    @Published var pointer: CGPoint = .zero
    @Published var detached = false
    /// The window's scale on screen, changed live by pinching, ⌘+ / ⌘− or
    /// the corner handle.
    @Published var scale: CGFloat = 1
}

// MARK: - Metrics

struct FolderMetrics {
    let folder: Folder
    let count: Int

    var layout: (columns: Int, rows: Int, pages: Int) { folder.layout(count: count) }
    var padding: CGFloat { CGFloat(folder.paddingPx) * (folder.view == .list ? 0.65 : 1) }
    var gap: CGFloat { folder.view == .list ? max(3, CGFloat(folder.gapPx) * 0.4) : CGFloat(folder.gapPx) }
    var labelHeight: CGFloat { folder.showNames ? folder.labelPoints * 1.35 + 6 : 0 }

    var cell: CGSize {
        let icon = folder.iconPoints
        switch folder.view {
        case .icons: return CGSize(width: icon + max(12, folder.labelPoints * 1.8), height: icon + labelHeight)
        case .list: return CGSize(width: max(150, 120 + folder.labelPoints * 7), height: max(26, icon * 0.6))
        case .tiles: return CGSize(width: icon * 1.6, height: icon * 1.3 + (folder.showNames ? folder.labelPoints * 1.3 : 0))
        }
    }

    var headerHeight: CGFloat { folder.header == .off ? 0 : folder.titlePoints + 22 }
    var footerHeight: CGFloat { layout.pages > 1 && !folder.hidePagination ? 22 : 0 }

    var gridSize: CGSize {
        let (cols, rows, _) = layout
        return CGSize(width: CGFloat(cols) * cell.width + CGFloat(max(0, cols - 1)) * gap,
                      height: CGFloat(rows) * cell.height + CGFloat(max(0, rows - 1)) * gap)
    }

    var size: CGSize {
        let grid = gridSize
        let minWidth: CGFloat = folder.header == .off ? 80 : 160
        return CGSize(width: max(minWidth, grid.width + padding * 2),
                      height: grid.height + padding * 2 + headerHeight + footerHeight)
    }
}

// MARK: - View

struct FolderWindowView: View {
    let folder: Folder
    let settings: GroopSettings
    @ObservedObject var model: PopupModel
    /// A live window: the system glass and real clicks. False in the studio.
    var live = true
    var onLaunch: (AppItem) -> Void = { _ in }
    var onLaunchAll: () -> Void = {}
    var onEdit: () -> Void = {}
    var onClose: () -> Void = {}
    var onDetach: (() -> Void)? = nil
    var onRemove: ((AppItem) -> Void)? = nil
    var onMove: (@MainActor @Sendable (AppItem, AppItem) -> Void)? = nil
    /// Live window only: a size step (-1, +1, 0 for the original size), a
    /// drag of the corner handle, and where the window should open.
    var onResizeStep: ((Int) -> Void)? = nil
    var onResizeDrag: ((Bool) -> Void)? = nil
    var onPlace: ((Placement?) -> Void)? = nil
    var placement: Placement? = nil

    @State private var hoverWindow = false
    private var metrics: FolderMetrics { FolderMetrics(folder: folder, count: folder.apps.count) }
    private var ink: Color { folder.resolvedFontIsDark ? .black.opacity(0.85) : .white }
    private var tint: Color { Color(hex: folder.windowColorHex) }
    private var radius: CGFloat { CGFloat(folder.cornerRadius) }

    var body: some View {
        let m = metrics
        VStack(spacing: 0) {
            if folder.header.isTop { header.frame(height: m.headerHeight) }
            pages(m).padding(m.padding)
            if m.footerHeight > 0 { dots(m).frame(height: m.footerHeight).padding(.top, -m.padding * 0.55) }
            if !folder.header.isTop, folder.header != .off { header.frame(height: m.headerHeight) }
        }
        .frame(width: m.size.width, height: m.size.height)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08), .white.opacity(0.2)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .overlay(alignment: launchAllAlignment) { if folder.launchAll { launchAllButton } }
        .overlay { if settings.showArrows && m.layout.pages > 1 { arrows(m) } }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .overlay(alignment: .topTrailing) { resizeHandle }
        .onHover { hoverWindow = $0 }
        .contextMenu { windowMenu }
        .onContinuousHover { phase in
            guard live, settings.parallax else { return }
            if case .active(let point) = phase {
                model.pointer = CGPoint(x: point.x / max(1, m.size.width) * 2 - 1, y: point.y / max(1, m.size.height) * 2 - 1)
            } else {
                model.pointer = .zero
            }
        }
        .environment(\.colorScheme, folder.resolvedFontIsDark ? .light : .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if folder.header.isCentered { Spacer(minLength: 0) }
            Text(folder.name)
                .font(.system(size: folder.titlePoints, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .shadow(color: .black.opacity(folder.textShadow ? 0.45 : 0), radius: 2, y: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.top, folder.header.isTop ? 12 : 0)
        .padding(.bottom, folder.header.isTop ? 0 : 12)
        .padding(.trailing, folder.launchAll && folder.launchAllPosition == .topRight && folder.header.isTop ? 30 : 0)
    }

    // MARK: Background

    @ViewBuilder private var background: some View {
        ZStack {
            if live {
                VisualEffect(material: .hudWindow)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            tint.opacity(folder.windowOpacity)
            if let image = folder.windowImage {
                StyledImage(style: image, parallax: parallaxOffset)
                    .animation(.easeOut(duration: 0.25), value: model.pointer)
            }
            switch folder.surface {
            case .glass:
                LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
            case .frost:
                Color.white.opacity(0.1)
                LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
            case .grain:
                GrainView().opacity(0.18).blendMode(.overlay)
            case .shine:
                LinearGradient(stops: [.init(color: .clear, location: 0.0), .init(color: .white.opacity(0.18), location: 0.32),
                                       .init(color: .clear, location: 0.38), .init(color: .white.opacity(0.1), location: 0.62),
                                       .init(color: .clear, location: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    /// The picture drifts with the pointer when parallax is on.
    private var parallaxOffset: CGSize {
        guard live, settings.parallax, folder.windowImage != nil else { return .zero }
        let amount = 14 * CGFloat(settings.parallaxStrength) * (settings.parallaxInvert ? 1 : -1)
        let x = settings.parallaxDirection == .vertical ? 0 : model.pointer.x * amount
        let y = settings.parallaxDirection == .horizontal ? 0 : model.pointer.y * amount
        return CGSize(width: x == 0 && y == 0 ? 0.001 : x, height: y)
    }

    // MARK: Pages

    private func pages(_ m: FolderMetrics) -> some View {
        let (cols, rows, pageCount) = m.layout
        let perPage = max(1, cols * rows)
        let page = min(model.page, pageCount - 1)
        return ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: m.padding * 2) {
                ForEach(0..<pageCount, id: \.self) { index in
                    let slice = Array(folder.apps.dropFirst(index * perPage).prefix(perPage))
                    grid(slice, columns: cols, m: m)
                        .frame(width: m.gridSize.width, height: m.gridSize.height, alignment: .topLeading)
                }
            }
            .offset(x: -CGFloat(page) * (m.gridSize.width + m.padding * 2))
            .animation(.spring(response: settings.swipeSpeed.duration, dampingFraction: 0.86), value: page)
        }
        .frame(width: m.gridSize.width, height: m.gridSize.height, alignment: .topLeading)
        .clipped()
        .frame(maxWidth: .infinity)
    }

    private func grid(_ apps: [AppItem], columns: Int, m: FolderMetrics) -> some View {
        let gridColumns = Array(repeating: GridItem(.fixed(m.cell.width), spacing: m.gap, alignment: .top), count: columns)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: m.gap) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                item(app, m: m)
                    .opacity(model.opened ? 1 : 0)
                    .scaleEffect(model.opened ? 1 : 0.6)
                    .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(model.opened ? Double(index) * 0.018 : 0),
                               value: model.opened)
            }
        }
    }

    @ViewBuilder private func item(_ app: AppItem, m: FolderMetrics) -> some View {
        let lit = model.hovered == app.id
        let zoom = lit && settings.hoverZoom ? 1.1 : 1
        Button { onLaunch(app) } label: {
            switch folder.view {
            case .icons:
                VStack(spacing: 6) {
                    icon(app, side: folder.iconPoints).scaleEffect(zoom)
                    if folder.showNames { label(app.label) }
                }
                .frame(width: m.cell.width, height: m.cell.height, alignment: .top)
            case .list:
                HStack(spacing: 10) {
                    icon(app, side: m.cell.height - 4).scaleEffect(zoom)
                    Text(app.label).font(.system(size: folder.labelPoints + 1, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: m.cell.width, height: m.cell.height)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ink.opacity(lit ? 0.12 : 0)))
            case .tiles:
                VStack(spacing: 6) {
                    icon(app, side: folder.iconPoints * 0.9).scaleEffect(zoom)
                    if folder.showNames {
                        Text(app.label).font(.system(size: folder.labelPoints, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    }
                }
                .frame(width: m.cell.width, height: m.cell.height)
                .background(RoundedRectangle(cornerRadius: min(22, CGFloat(folder.cornerRadius) * 0.7), style: .continuous)
                    .fill(ink.opacity(lit ? 0.18 : 0.09)))
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { model.hovered = inside ? app.id : (model.hovered == app.id ? nil : model.hovered) }
        }
        .help(app.label)
        .contextMenu {
            if let onRemove { Button(L("Remove from folder", "Retirer du dossier")) { onRemove(app) } }
            Button(L("Show in Finder", "Afficher dans le Finder")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
        .modifier(DragReorder(app: app, onMove: onMove))
    }

    private func icon(_ app: AppItem, side: CGFloat) -> some View {
        Image(nsImage: app.icon).resizable().interpolation(.high)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: folder.roundIcons ? side / 2 : side * 0.23, style: .continuous))
            .opacity(app.exists ? 1 : 0.4)
            .shadow(color: .black.opacity(0.25), radius: side * 0.06, y: side * 0.04)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: folder.labelPoints, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, folder.textBackdrop ? 6 : 0)
            .padding(.vertical, folder.textBackdrop ? 1.5 : 0)
            .background { if folder.textBackdrop { Capsule().fill(.black.opacity(0.35)) } }
            .shadow(color: .black.opacity(folder.textShadow ? 0.6 : 0), radius: 2, y: 1)
            .frame(maxWidth: metrics.cell.width)
    }

    // MARK: Pagination

    private func dots(_ m: FolderMetrics) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<m.layout.pages, id: \.self) { index in
                Circle().fill(ink.opacity(index == model.page ? 0.9 : 0.3))
                    .frame(width: 6.5, height: 6.5)
                    .onTapGesture { model.page = index }
            }
        }
    }

    private func arrows(_ m: FolderMetrics) -> some View {
        HStack {
            arrow("chevron.left", enabled: model.page > 0) { model.page -= 1 }
            Spacer()
            arrow("chevron.right", enabled: model.page < m.layout.pages - 1) { model.page += 1 }
        }
        .padding(.horizontal, 4)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(ink.opacity(0.8))
                .frame(width: 22, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    // MARK: Launch all

    private var launchAllAlignment: Alignment {
        switch folder.launchAllPosition {
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    private var launchAllButton: some View {
        Button(action: onLaunchAll) {
            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(ink.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help(L("Open every app", "Ouvrir toutes les apps"))
        .padding(10)
    }

    /// A corner grip, shown on hover: drag it to make the window bigger or
    /// smaller right where it is.
    @ViewBuilder private var resizeHandle: some View {
        if live, let onResizeDrag {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.black.opacity(0.22)))
                .padding(6)
                .opacity(hoverWindow ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hoverWindow)
                .help(L("Drag to resize (or pinch, ⌘+ / ⌘−)", "Tirez pour redimensionner (ou pincez, ⌘+ / ⌘−)"))
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { _ in onResizeDrag(false) }
                    .onEnded { _ in onResizeDrag(true) })
        }
    }

    @ViewBuilder private var windowMenu: some View {
        Button(L("Edit in the studio", "Modifier dans le studio"), action: onEdit)
        if live {
            Button(L("Open every app", "Ouvrir toutes les apps"), action: onLaunchAll)
            if let onResizeStep {
                Menu(L("Size", "Taille")) {
                    Button(L("Bigger  ⌘+", "Plus grande  ⌘+")) { onResizeStep(1) }
                    Button(L("Smaller  ⌘−", "Plus petite  ⌘−")) { onResizeStep(-1) }
                    Button(L("Original size  ⌘0", "Taille d’origine  ⌘0")) { onResizeStep(0) }
                }
            }
            if let onPlace {
                Menu(L("Opens", "S’ouvre")) {
                    Button(L("Like the other folders", "Comme les autres dossiers")) { onPlace(nil) }
                    Divider()
                    ForEach([Placement.dock, .center, .pointer]) { place in
                        Button((placement == place ? "✓ " : "") + place.title) { onPlace(place) }
                    }
                    Button((placement == .remembered ? "✓ " : "") + L("Right here (remember)", "Ici (mémoriser)")) { onPlace(.remembered) }
                }
            }
            if let onDetach {
                Button(model.detached ? L("Put back", "Remettre en place") : L("Detach", "Détacher"), action: onDetach)
            }
            Divider()
            Button(L("Close the folder", "Fermer le dossier"), action: onClose)
        }
    }
}

/// Lets the studio's preview reorder apps by dragging one onto another.
private struct DragReorder: ViewModifier {
    let app: AppItem
    let onMove: (@MainActor @Sendable (AppItem, AppItem) -> Void)?

    func body(content: Content) -> some View {
        if let onMove {
            content
                .onDrag { NSItemProvider(object: app.path as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    providers.first?.loadObject(ofClass: NSString.self) { object, _ in
                        guard let path = object as? String else { return }
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                onMove(AppItem(path: path, bundleID: nil, name: "", category: .other), app)
                            }
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

/// A fine noise for the Grain surface, drawn once.
struct GrainView: View {
    var body: some View {
        Canvas { context, size in
            var generator = SystemRandomNumberGenerator()
            let count = Int(size.width * size.height / 9)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0..<size.width, using: &generator)
                let y = CGFloat.random(in: 0..<size.height, using: &generator)
                let white = Double.random(in: 0...1, using: &generator)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color(white: white)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// The system's blur behind a live window.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

// MARK: - Window controller

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Opens and closes the window of one folder at a time.
@MainActor
final class FolderWindowController {
    private var panel: FloatingPanel?
    private var shown: UUID?
    private var model = PopupModel()
    private var monitors: [Any] = []
    private var leaveWork: DispatchWorkItem?
    /// A click outside closes the window; when that click was on the
    /// folder's own tile its URL arrives next and must not reopen it.
    private var closedByClick: (id: UUID, at: Date)?

    var onEdit: (UUID) -> Void = { _ in }
    var settings: () -> GroopSettings = { GroopSettings() }
    /// Saves a change the user made on the window itself (its size, where it opens).
    var onUpdate: (UUID, @escaping (inout Folder) -> Void) -> Void = { _, _ in }

    private var folder: Folder?
    private var margin: CGFloat = 40
    private var dragStart: (mouse: NSPoint, scale: CGFloat)?
    private var moveObserver: Any?

    var isOpen: Bool { panel != nil }

    func toggle(_ folder: Folder, anchored: Bool = true) {
        if shown == folder.id { close(); return }
        if let closed = closedByClick, closed.id == folder.id, Date().timeIntervalSince(closed.at) < 0.8 {
            closedByClick = nil
            return
        }
        show(folder, anchored: anchored)
    }

    func show(_ folder: Folder, anchored: Bool = true) {
        close()
        let settings = settings()
        self.folder = folder
        let metrics = FolderMetrics(folder: folder, count: folder.apps.count)
        let scale = CGFloat(settings.windowScale * folder.folderScale)
        let size = panelSize(folder, scale: scale)
        var placement = folder.placement ?? settings.placement
        if !anchored && placement == .dock { placement = .center }
        let saved = folder.windowCenterX.flatMap { x in folder.windowCenterY.map { NSPoint(x: x, y: $0) } }
        let frame = Self.frame(for: size, inset: margin, placement: placement, savedCenter: saved)

        let panel = FloatingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = settings.keepOnTop ? .statusBar : .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let model = PopupModel()
        model.scale = scale
        self.model = model
        let id = folder.id
        let root = FolderWindowView(
            folder: folder, settings: settings, model: model, live: true,
            onLaunch: { [weak self] app in self?.launch(app) },
            onLaunchAll: { [weak self] in self?.launchAll(folder) },
            onEdit: { [weak self] in self?.close(); self?.onEdit(id) },
            onClose: { [weak self] in self?.close() },
            onDetach: { [weak self] in self?.toggleDetached(folder) },
            onResizeStep: { [weak self] step in self?.resizeStep(step) },
            onResizeDrag: { [weak self] ended in self?.resizeDrag(ended: ended) },
            onPlace: { [weak self] place in self?.place(place) },
            placement: folder.placement
        )
        .onHover { [weak self] inside in self?.hoverChanged(inside) }
        let host = NSHostingView(rootView: PopupEntrance(model: model) { root })
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        }
        shown = folder.id
        install(pages: metrics.layout.pages)
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        dragStart = nil
        leaveWork?.cancel()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        shown = nil
    }

    /// A detached window stays open, can be dragged anywhere and closes
    /// only on Escape or from its menu. Putting it back re-anchors it.
    private func toggleDetached(_ folder: Folder) {
        guard let panel else { return }
        if model.detached {
            show(folder)
        } else {
            model.detached = true
            panel.isMovableByWindowBackground = true
            panel.isMovable = true
            panel.level = .floating
        }
    }

    // MARK: Size and place, on screen

    private func panelSize(_ folder: Folder, scale: CGFloat) -> CGSize {
        let metrics = FolderMetrics(folder: folder, count: folder.apps.count)
        return CGSize(width: metrics.size.width * scale + margin * 2, height: metrics.size.height * scale + margin * 2)
    }

    private static let scaleRange: ClosedRange<CGFloat> = 0.4...2.2

    /// Resizes the window around its anchor: its bottom edge above a bottom
    /// Dock, its centre anywhere else.
    private func apply(scale newScale: CGFloat, save: Bool) {
        guard let panel, let folder else { return }
        let scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, newScale))
        let old = panel.frame
        let size = panelSize(folder, scale: scale)
        let keepBottom = (folder.placement ?? settings().placement) == .dock && Self.dockEdge == .bottom && !model.detached
        let origin = NSPoint(x: old.midX - size.width / 2, y: keepBottom ? old.minY : old.midY - size.height / 2)
        model.scale = scale
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if save { saveScale(scale) }
    }

    private func saveScale(_ scale: CGFloat) {
        guard let id = folder?.id else { return }
        let global = max(0.1, settings().windowScale)
        let folderScale = Double(scale) / global
        folder?.folderScale = folderScale
        onUpdate(id) { $0.folderScale = (folderScale * 100).rounded() / 100 }
    }

    private func resizeStep(_ step: Int) {
        let base = CGFloat(settings().windowScale)
        switch step {
        case 0: apply(scale: base, save: true)
        default: apply(scale: model.scale * (step > 0 ? 1.1 : 1 / 1.1), save: true)
        }
    }

    /// Dragging the corner handle: up or right grows the window.
    private func resizeDrag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, model.scale) }
        guard let start = dragStart, let folder else { return }
        let width = FolderMetrics(folder: folder, count: folder.apps.count).size.width
        let delta = (mouse.x - start.mouse.x) + (mouse.y - start.mouse.y)
        apply(scale: start.scale * (1 + delta / max(120, width * start.scale)), save: ended)
        if ended { dragStart = nil }
    }

    private func place(_ placement: Placement?) {
        guard let panel, let id = folder?.id else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        folder?.placement = placement
        onUpdate(id) { folder in
            folder.placement = placement
            if placement == .remembered { folder.windowCenterX = center.x; folder.windowCenterY = center.y }
        }
        if placement == .remembered, !model.detached, let folder { toggleDetached(folder) }
    }

    /// A detached window that opens "where I left it" remembers each move.
    private func panelMoved() {
        guard model.detached, dragStart == nil, let panel, let folder, folder.placement == .remembered else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        onUpdate(folder.id) { $0.windowCenterX = center.x; $0.windowCenterY = center.y }
    }

    private func hoverChanged(_ inside: Bool) {
        guard settings().closeOnLeave, !model.detached else { return }
        leaveWork?.cancel()
        guard !inside else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.close() } }
        leaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func launch(_ app: AppItem) {
        if settings().closeAfterLaunch { close() }
        guard app.exists else { NSSound.beep(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    }

    private func launchAll(_ folder: Folder) {
        close()
        for app in folder.apps where app.exists {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
        }
    }

    private func install(pages: Int) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let id = self.shown, !self.model.detached else { return }
                self.closedByClick = (id, Date())
                self.close()
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if command {
                    switch code {
                    case 24, 69: self.resizeStep(1); return true   // ⌘= / ⌘+
                    case 27, 78: self.resizeStep(-1); return true  // ⌘-
                    case 29, 82: self.resizeStep(0); return true   // ⌘0
                    default: break
                    }
                }
                switch code {
                case 53: self.close(); return true                                         // Escape
                case 123: self.model.page = max(0, self.model.page - 1); return true        // ←
                case 124: self.model.page = min(pages - 1, self.model.page + 1); return true // →
                default: return false
                }
            }
            return handled ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify, handler: { [weak self] event in
            let amount = event.magnification
            let ended = event.phase == .ended || event.phase == .cancelled
            MainActor.assumeIsolated {
                guard let self, self.panel != nil else { return }
                self.apply(scale: self.model.scale * (1 + amount), save: ended)
            }
            return nil
        }) { monitors.append(monitor) }
        let swipe = SwipeTracker()
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard pages > 1 else { return event }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let began = event.phase == .began || event.phase == .mayBegin
            let ended = event.phase == .ended || event.phase == .cancelled
            let wheel = event.phase == [] && event.momentumPhase == []
            MainActor.assumeIsolated {
                guard let self, let step = swipe.feed(dx: dx, dy: dy, began: began, ended: ended, wheel: wheel) else { return }
                self.model.page = min(pages - 1, max(0, self.model.page + step))
            }
            return nil
        }) { monitors.append(monitor) }
    }

    // MARK: Placement

    enum Edge { case bottom, left, right }

    static var dockEdge: Edge {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": .left
        case "right": .right
        default: .bottom
        }
    }

    private static func frame(for size: CGSize, inset: CGFloat, placement: Placement, savedCenter: NSPoint?) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let anchor = placement == .remembered ? (savedCenter ?? mouse) : mouse
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin: NSPoint
        if placement == .center {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        } else if placement == .pointer || (placement == .remembered && savedCenter != nil) {
            origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2)
        } else {
            let gap: CGFloat = 8 - inset
            switch dockEdge {
            case .bottom: origin = NSPoint(x: mouse.x - size.width / 2, y: visible.minY + gap)
            case .left: origin = NSPoint(x: visible.minX + gap, y: mouse.y - size.height / 2)
            case .right: origin = NSPoint(x: visible.maxX - size.width - gap, y: mouse.y - size.height / 2)
            }
        }
        origin.x = min(max(origin.x, visible.minX - inset + 6), visible.maxX - size.width + inset - 6)
        origin.y = min(max(origin.y, visible.minY - inset + 6), visible.maxY - size.height + inset - 6)
        return NSRect(origin: origin, size: size)
    }
}

/// Turns trackpad swipes and wheel clicks into one page step each.
@MainActor
private final class SwipeTracker {
    private var accumulated: CGFloat = 0
    private var locked = false

    func feed(dx: CGFloat, dy: CGFloat, began: Bool, ended: Bool, wheel: Bool) -> Int? {
        if began { accumulated = 0; locked = false }
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        if wheel { return delta == 0 ? nil : (delta > 0 ? 1 : -1) }
        accumulated += delta
        defer { if ended { accumulated = 0; locked = false } }
        guard !locked, abs(accumulated) > 40 else { return nil }
        locked = true
        return accumulated > 0 ? 1 : -1
    }
}

/// The window springs up from the Dock once it is on screen.
private struct PopupEntrance<Content: View>: View {
    @ObservedObject var model: PopupModel
    @ViewBuilder let content: () -> Content
    @State private var shown = false

    var body: some View {
        content()
            .scaleEffect(model.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(shown ? 1 : 0.86, anchor: FolderWindowController.dockEdge == .bottom ? .bottom : .center)
            .opacity(shown ? 1 : 0)
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { shown = true }
                    model.opened = true
                }
            }
    }
}
