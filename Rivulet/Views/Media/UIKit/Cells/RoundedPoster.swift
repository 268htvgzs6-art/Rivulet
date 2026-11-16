// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Poster artwork with the Apple TV app's 20 pt corner drawn into the image (#581).
// TVPosterView ignores a corner radius set on it and clips to the system corner,
// which is 20 pt on tvOS 27 but about 6 pt on tvOS 26; the Apple TV app is 20 pt on both.
// An opaque `Shape` draws solid artwork with no alpha channel and no corner instead, for a
// cell that clips the corner itself (`PosterCell.solidArt`).

import UIKit

nonisolated enum RoundedPoster {
    /// The resting corner, in points. Overlays on a poster use the same value.
    static let cornerRadius: CGFloat = 20

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private static let queue = DispatchQueue(label: "rivulet.rounded-poster", qos: .userInitiated)

    /// The rounded poster, without waiting: from this cache, or drawn here from the image
    /// cache's decoded copy. Nil when the source isn't decoded yet.
    static func cached(for url: URL, shape: Shape) -> UIImage? {
        let key = shape.key(url)
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = ImageCacheManager.shared.cachedImage(for: url)?.cgImage else { return nil }
        return store(render(source, shape: shape), key)
    }

    /// The rounded poster, loading the source through the image cache and drawing off the main thread.
    static func image(for url: URL, shape: Shape) async -> UIImage? {
        let key = shape.key(url)
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = await ImageCacheManager.shared.image(for: url)?.cgImage else { return nil }
        let rendered = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: render(source, shape: shape)) }
        }
        return store(rendered, key)
    }

    /// Image size, corner and scale for one tile.
    struct Shape: Sendable {
        let size: CGSize
        let radius: CGFloat
        let scale: CGFloat
        /// A bitmap with no alpha channel and square corners. TVPosterView scans the alpha of every
        /// image it is given on the main thread (about 1.2 ms a poster in the simulator); an image
        /// without an alpha channel skips the scan (about 0.06 ms).
        let opaque: Bool

        /// Fills the host size (the focused size TVPosterView scales the image to), so the
        /// corner reads `cornerRadius` at rest and grows with the poster on focus.
        @MainActor init(tile: MediaRowMetrics.Tile, scale: CGFloat, opaque: Bool = false) {
            size = tile.hostSize
            radius = RoundedPoster.cornerRadius * tile.hostSize.width / tile.art.width
            self.scale = scale
            self.opaque = opaque
        }

        fileprivate func key(_ url: URL) -> NSString {
            "\(Int(size.width * scale))x\(Int(size.height * scale))\(opaque ? "o" : "")#\(url.absoluteString)" as NSString
        }
    }

    static func render(_ source: CGImage, shape: Shape) -> UIImage {
        // Sources with their own transparency (PNG/WebP from Jellyfin or Emby, unsized originals) keep
        // baked corners: drawn without alpha, their see-through parts would turn black.
        if shape.opaque, !source.hasAlpha, let solid = renderOpaque(source, shape: shape) { return solid }
        let size = shape.size, radius = shape.radius
        return UIGraphicsImageRenderer(size: size, format: .layeredArtwork(scale: shape.scale)).image { context in
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).addClip()
            let srcW = CGFloat(source.width), srcH = CGFloat(source.height)
            let fill = max(size.width / srcW, size.height / srcH)
            let drawSize = CGSize(width: srcW * fill, height: srcH * fill)
            UIImage(cgImage: source).draw(in: CGRect(x: (size.width - drawSize.width) / 2,
                                                     y: (size.height - drawSize.height) / 2,
                                                     width: drawSize.width, height: drawSize.height))
        }
    }

    /// The same aspect-fill as `render`, into a bitmap with no alpha channel and no corner.
    private static func renderOpaque(_ source: CGImage, shape: Shape) -> UIImage? {
        let pw = Int((shape.size.width * shape.scale).rounded()), ph = Int((shape.size.height * shape.scale).rounded())
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let srcW = CGFloat(source.width), srcH = CGFloat(source.height)
        let fill = max(CGFloat(pw) / srcW, CGFloat(ph) / srcH)
        let drawW = srcW * fill, drawH = srcH * fill
        ctx.draw(source, in: CGRect(x: (CGFloat(pw) - drawW) / 2, y: (CGFloat(ph) - drawH) / 2, width: drawW, height: drawH))
        guard let image = ctx.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: shape.scale, orientation: .up)
    }

    private static func store(_ image: UIImage, _ key: NSString) -> UIImage {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

extension UIGraphicsImageRendererFormat {
    /// For artwork drawn with transparency that a focus-layered view shows (TVPosterView,
    /// `adjustsImageWhenAncestorFocused`). Standard range always: a wide-colour display's default is
    /// 16-bit float, and UIKit's shadow check reads past the end of such an image (SIGSEGV in vImage).
    nonisolated static func layeredArtwork(scale: CGFloat? = nil) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        if let scale { format.scale = scale }
        format.preferredRange = .standard
        return format
    }
}

private extension CGImage {
    nonisolated var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }
}
