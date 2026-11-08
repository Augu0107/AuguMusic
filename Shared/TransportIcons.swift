import SwiftUI

// Icone dei tasti di riproduzione disegnate a mano, con angoli vivi (come Musicolet).

enum TransportGlyph {
    case play, pause, next, previous
}

private struct PlayShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = min(r.height, r.width / 0.88)
        let w = h * 0.88
        let x = r.midX - w / 2 + w * 0.06
        let y = r.midY - h / 2
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y + h / 2))
        p.addLine(to: CGPoint(x: x, y: y + h))
        p.closeSubpath()
        return p
    }
}

private struct PauseShape: Shape {
    func path(in r: CGRect) -> Path {
        let side = min(r.width, r.height)
        let barW = side * 0.3
        let gap = side * 0.22
        let total = barW * 2 + gap
        let x = r.midX - total / 2
        let y = r.midY - side / 2
        var p = Path()
        p.addRect(CGRect(x: x, y: y, width: barW, height: side))
        p.addRect(CGRect(x: x + barW + gap, y: y, width: barW, height: side))
        return p
    }
}

/// ▶| (verso destra) oppure |◀ (verso sinistra).
private struct SkipShape: Shape {
    let forward: Bool

    func path(in r: CGRect) -> Path {
        let side = min(r.width, r.height)
        let triW = side * 0.72
        let barW = side * 0.16
        let x = r.midX - side / 2
        let y = r.midY - side / 2
        var p = Path()
        if forward {
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + triW, y: y + side / 2))
            p.addLine(to: CGPoint(x: x, y: y + side))
            p.closeSubpath()
            p.addRect(CGRect(x: x + side - barW, y: y, width: barW, height: side))
        } else {
            p.addRect(CGRect(x: x, y: y, width: barW, height: side))
            p.move(to: CGPoint(x: x + side, y: y))
            p.addLine(to: CGPoint(x: x + side - triW, y: y + side / 2))
            p.addLine(to: CGPoint(x: x + side, y: y + side))
            p.closeSubpath()
        }
        return p
    }
}

/// Una sola forma che cambia disegno: così play ↔ pausa cambia di colpo, senza dissolvenza.
private struct GlyphShape: Shape {
    let glyph: TransportGlyph

    func path(in rect: CGRect) -> Path {
        switch glyph {
        case .play: PlayShape().path(in: rect)
        case .pause: PauseShape().path(in: rect)
        case .next: SkipShape(forward: true).path(in: rect)
        case .previous: SkipShape(forward: false).path(in: rect)
        }
    }
}

struct TransportIcon: View {
    let glyph: TransportGlyph
    var size: CGFloat = 24

    var body: some View {
        GlyphShape(glyph: glyph)
            .fill(.foreground)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .transaction { t in
                t.animation = nil
                t.disablesAnimations = true
            }
    }
}
