//
//  TileIcon.swift
//  Groop
//
//  The folder's tile in the Dock, in its three styles. Drawn on Apple's icon
//  grid (an 824-point body centred on a 1024 canvas) so it lines up with the
//  icons beside it.
//

import AppKit
import SwiftUI

struct TileIcon: View {
    let folder: Folder
    /// The canvas side; the body is 80 % of it, as on Apple's grid.
    var size: CGFloat = 128

    private var bodySide: CGFloat { size * 824 / 1024 }
    private var radius: CGFloat { bodySide * 0.225 }
    private var tint: Color { Color(hex: folder.colorHex) }

    var body: some View {
        Group {
            switch folder.iconStyle {
            case .classic: classic
            case .stack: stack
            case .folder: folderTile
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Classic

    private var classic: some View {
        ZStack {
            plate(RoundedRectangle(cornerRadius: radius, style: .continuous))
            appGrid(side: bodySide)
        }
        .frame(width: bodySide, height: bodySide)
        .shadow(color: .black.opacity(folder.lift ? 0.45 : 0.22), radius: size * (folder.lift ? 0.045 : 0.018),
                y: size * (folder.lift ? 0.035 : 0.01))
    }

    /// The glass behind the apps: the folder's colour at its opacity, frosted
    /// by `matte`, lit from the top when glossy.
    private func plate<S: InsettableShape>(_ shape: S) -> some View {
        ZStack {
            shape.fill(Color(white: 0.16).opacity(0.55 + folder.opacity * 0.2))
            if let style = folder.tileImage {
                StyledImage(style: style).clipShape(shape)
            }
            shape.fill(LinearGradient(colors: [tint.mixed(with: .white, 0.18), tint.mixed(with: .black, 0.12)],
                                      startPoint: .top, endPoint: .bottom).opacity(folder.opacity))
            if folder.matte > 0 { shape.fill(.white.opacity(folder.matte * 0.35)) }
            if folder.glossy {
                shape.fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06), .clear],
                                          startPoint: .top, endPoint: .center))
                shape.fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading,
                                          startRadius: 0, endRadius: bodySide * 0.9))
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.28)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: max(0.6, size * 0.008))
        }
    }

    private func appGrid(side: CGFloat) -> some View {
        let n = folder.dense ? 3 : 2
        let shown = Array(folder.apps.prefix(n * n))
        let inset = side * (n == 2 ? 0.15 : 0.12)
        let gap = side * (n == 2 ? 0.07 : 0.045)
        let fit = (side - inset * 2 - gap * CGFloat(n - 1)) / CGFloat(n)
        let cell = fit * CGFloat(max(0.5, min(1.25, folder.tileAppScale)))
        return VStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { column in
                        let index = row * n + column
                        if index < shown.count {
                            AppGlyph(app: shown[index], size: cell, round: folder.roundIcons)
                        } else {
                            RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                                .fill(.white.opacity(0.13))
                                .frame(width: cell * 0.86, height: cell * 0.86)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    // MARK: Stack

    private var stack: some View {
        let depth = max(2, min(5, folder.stackDepth))
        let apps = Array(folder.apps.prefix(depth))
        let card = bodySide * 0.78
        return ZStack {
            ForEach(Array((0..<depth).reversed()), id: \.self) { index in
                let step = CGFloat(index)
                ZStack {
                    plate(RoundedRectangle(cornerRadius: card * 0.24, style: .continuous))
                    if index < apps.count {
                        AppGlyph(app: apps[index], size: card * 0.62, round: folder.roundIcons)
                    }
                }
                .frame(width: card, height: card)
                .scaleEffect(1 - step * 0.08)
                .offset(x: step * card * 0.07, y: -step * card * 0.11)
                .opacity(1 - step * 0.16)
            }
        }
        .offset(y: bodySide * 0.06)
        .frame(width: bodySide, height: bodySide)
        .shadow(color: .black.opacity(folder.lift ? 0.45 : 0.25), radius: size * 0.03, y: size * 0.02)
    }

    // MARK: Folder

    private var folderTile: some View {
        ZStack {
            if folder.folderShape == .folder {
                FolderBody(tint: tint, opacity: folder.opacity, glossy: folder.glossy, size: bodySide, image: folder.tileImage)
            } else {
                plate(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            emblem
                .rotationEffect(.degrees(folder.tileRotation))
                .offset(y: folder.folderShape == .folder ? bodySide * 0.07 : 0)
        }
        .frame(width: bodySide, height: bodySide)
        .shadow(color: .black.opacity(folder.lift ? 0.45 : 0.22), radius: size * 0.025, y: size * 0.015)
    }

    @ViewBuilder private var emblem: some View {
        let ink = tint.luminance > 0.7 ? Color.black.opacity(0.55) : Color.white.opacity(0.92)
        if folder.tileContent == .text, !folder.tileText.isEmpty {
            let emoji = folder.tileText.count <= 2 && folder.tileText.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            Text(folder.tileText)
                .font(.system(size: bodySide * (emoji ? 0.5 : folder.tileText.count <= 2 ? 0.34 : 0.17) * folder.tileSymbolScale,
                              weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.4).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: bodySide * 0.7)
        } else {
            Image(systemName: folder.tileSymbol.isEmpty ? "square.grid.2x2.fill" : folder.tileSymbol)
                .font(.system(size: bodySide * 0.3 * folder.tileSymbolScale, weight: .semibold))
                .foregroundStyle(ink)
                .shadow(color: .black.opacity(0.2), radius: bodySide * 0.01, y: bodySide * 0.008)
        }
    }
}

/// A picture of the user's with its scale, saturation, blur and brightness,
/// filling the space it is given.
struct StyledImage: View {
    let style: ImageStyle
    var parallax: CGSize = .zero

    var body: some View {
        if let image = ImageCache.shared.image(named: style.file) {
            Color.clear
                .overlay(
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .scaleEffect(CGFloat(style.scale) * (parallax == .zero ? 1 : 1.08))
                        .offset(parallax)
                        .saturation(style.saturation)
                        .brightness(style.brightness)
                        .blur(radius: CGFloat(style.blur))
                )
                .clipped()
        }
    }
}

/// An app's icon inside a tile, optionally cut round.
struct AppGlyph: View {
    let app: AppItem
    let size: CGFloat
    var round = false

    var body: some View {
        Image(nsImage: app.icon).resizable().interpolation(.high)
            .frame(width: size * 1.12, height: size * 1.12)   // app icons carry their own margin
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.2, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: size * 0.04, y: size * 0.03)
    }
}

/// A macOS-style folder: a tab at the back, a front flap with light on top.
struct FolderBody: View {
    let tint: Color
    let opacity: Double
    let glossy: Bool
    let size: CGFloat
    var image: ImageStyle? = nil

    var body: some View {
        let w = size, h = size * 0.78
        ZStack(alignment: .top) {
            // Back with its tab.
            FolderBack(tabWidth: 0.38)
                .fill(tint.mixed(with: .black, 0.22).opacity(max(0.35, opacity)))
                .frame(width: w, height: h)
            // Front flap.
            RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                .fill(LinearGradient(colors: [tint.mixed(with: .white, 0.2), tint],
                                     startPoint: .top, endPoint: .bottom).opacity(max(0.4, opacity)))
                .overlay {
                    if let image {
                        StyledImage(style: image).clipShape(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous))
                    }
                }
                .overlay {
                    if glossy {
                        RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: max(0.6, w * 0.006)))
                .frame(width: w, height: h * 0.84)
                .offset(y: h * 0.18)
        }
        .frame(width: w, height: h)
        .offset(y: size * 0.06)
    }
}

private struct FolderBack: Shape {
    let tabWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.width * 0.07
        let tab = rect.width * tabWidth
        let tabH = rect.height * 0.12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tab - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tab + r * 0.6, y: rect.minY + tabH), control: CGPoint(x: rect.minX + tab, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tabH + r), control: CGPoint(x: rect.maxX, y: rect.minY + tabH))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

extension TileIcon {
    /// The tile at 1024 points, as PNG data, for the Dock launcher.
    @MainActor
    static func pngData(for folder: Folder) -> Data? {
        let renderer = ImageRenderer(content: TileIcon(folder: folder, size: 1024))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
