import UIKit
import WidgetKit

/// Prepara i dati del widget (testi, copertina e colori) e chiede a iOS di ridisegnarlo.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private var lastTrackID: String?
    private var lastStyle: WidgetStyle?
    private var lastHadArtwork = false
    private var lastColors: (bg: [Double], accent: [Double]) = ([0.2, 0.2, 0.22], [1, 0.6, 0.2])
    private var lastJSON: Data?
    private var pending: Task<Void, Never>?

    var isAvailable: Bool { AppGroup.containerURL != nil }

    struct State {
        var track: Track?
        var artwork: UIImage?
        var isPlaying: Bool
        var isFavorite: Bool
        var queueName: String
        var position: String
        var upNext: [String]
        var style: WidgetStyle
        var accent: UIColor
    }

    func update(_ state: State) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.write(state)
        }
    }

    private func write(_ state: State) {
        guard isAvailable else { return }
        guard let track = state.track else {
            if lastTrackID != nil {
                lastTrackID = nil
                WidgetSnapshot.saveArtwork(nil)
                lastJSON = nil
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }

        let artworkArrived = state.artwork != nil && !lastHadArtwork
        if track.id != lastTrackID || state.style != lastStyle || artworkArrived {
            WidgetSnapshot.saveArtwork(state.artwork.map { Self.thumbnail($0, maxSide: 400) })
            lastColors = Self.colors(style: state.style, artwork: state.artwork, accent: state.accent)
            lastTrackID = track.id
            lastStyle = state.style
            lastHadArtwork = state.artwork != nil
            lastJSON = nil
        }

        let snap = WidgetSnapshot(trackID: track.id,
                                  title: track.displayTitle,
                                  artist: track.displayArtist,
                                  album: track.displayAlbum,
                                  queueName: state.queueName,
                                  position: state.position,
                                  isPlaying: state.isPlaying,
                                  isFavorite: state.isFavorite,
                                  upNext: state.upNext,
                                  background: lastColors.bg,
                                  accent: lastColors.accent,
                                  updated: Date())
        var comparable = snap
        comparable.updated = .distantPast
        let json = try? JSONEncoder().encode(comparable)
        guard json != lastJSON else { return }
        lastJSON = json
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Forza il ricalcolo dei colori (es. cambiato lo stile in Impostazioni).
    func invalidate() {
        lastTrackID = nil
        lastJSON = nil
    }

    // MARK: Immagine e colori

    private static func thumbnail(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func components(_ color: UIColor) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)]
    }

    static func colors(style: WidgetStyle, artwork: UIImage?, accent: UIColor) -> (bg: [Double], accent: [Double]) {
        switch style {
        case .dark:
            return ([0.11, 0.11, 0.13], components(accent))
        case .accent:
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            accent.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            let bg = UIColor(hue: h, saturation: min(s, 0.75), brightness: 0.34, alpha: 1)
            return (components(bg), components(UIColor(hue: h, saturation: min(s, 0.55), brightness: 1, alpha: 1)))
        case .artwork:
            guard let artwork, let dominant = dominantColor(artwork) else {
                return ([0.16, 0.16, 0.18], components(accent))
            }
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            dominant.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            let bg = UIColor(hue: h, saturation: min(s * 1.1, 0.8), brightness: 0.30 + 0.08 * v, alpha: 1)
            let light = UIColor(hue: h, saturation: max(0.25, min(s, 0.55)), brightness: 1, alpha: 1)
            return (components(bg), components(light))
        }
    }

    /// Colore "vivace" più presente nella copertina (simile alla tavolozza di Android).
    private static func dominantColor(_ image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var weight = [Double](repeating: 0, count: 12)
        var sumR = [Double](repeating: 0, count: 12)
        var sumG = [Double](repeating: 0, count: 12)
        var sumB = [Double](repeating: 0, count: 12)
        var avgR = 0.0, avgG = 0.0, avgB = 0.0

        for i in 0..<(side * side) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            avgR += r; avgG += g; avgB += b
            let maxC = max(r, g, b), minC = min(r, g, b)
            let v = maxC
            let s = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard s > 0.22, v > 0.18, v < 0.97 else { continue }
            var h: Double
            if maxC == minC {
                h = 0
            } else if maxC == r {
                h = (g - b) / (maxC - minC)
            } else if maxC == g {
                h = 2 + (b - r) / (maxC - minC)
            } else {
                h = 4 + (r - g) / (maxC - minC)
            }
            h = (h / 6).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
            let bucket = min(11, Int(h * 12))
            let w = s * v
            weight[bucket] += w
            sumR[bucket] += r * w
            sumG[bucket] += g * w
            sumB[bucket] += b * w
        }

        if let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 1.5 {
            let w = weight[best]
            return UIColor(red: sumR[best] / w, green: sumG[best] / w, blue: sumB[best] / w, alpha: 1)
        }
        let n = Double(side * side)
        return UIColor(red: avgR / n, green: avgG / n, blue: avgB / n, alpha: 1)
    }
}
