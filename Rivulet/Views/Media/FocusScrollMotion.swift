// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Motion of the driven focus scrolls: Home's vertical scroll, the shelf rows, the detail, season
// and person pages (FocusScrollControlledCollectionView) and the music queue. We drive them because
// the focus engine's own scroll animator races a CADisplayLink driver. Keep other timings
// (carousel morph, backdrop crossfade, detail slide) out of here.

import CoreGraphics
import Foundation

enum FocusScrollMotion {
    /// Duration, in seconds, of the eased settle (FocusScrollControlledCollectionView and the music queue).
    static let settleDuration: CFTimeInterval = 0.6

    /// Eased progress for the focus-scroll settle. Cubic ease-out: fast start,
    /// decelerating to a gentle stop. `t` is linear progress in 0...1.
    static func ease(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    // MARK: - Spring (Home's vertical scroll and the shelf rows)

    /// Spring periods, in seconds: Home's vertical focus-scroll and each shelf row.
    static let verticalResponse: Double = 0.46
    static let rowResponse: Double = 0.36
    /// Home's vertical damping: just under critical, so a move lands softly instead of creeping in.
    /// From rest it passes the target by at most 0.15% of the distance (0.7 pt on a 450 pt move).
    static let verticalDamping: Double = 0.9
    /// Speed multiplier for a press that retargets further in the direction of travel, so a run of
    /// presses builds momentum; capped at `maxVerticalSpeed` points per second.
    static let verticalMomentum: CGFloat = 1.2
    static let maxVerticalSpeed: CGFloat = 5000

    /// One frame of a damped spring, solved exactly. `damping` 1 is critical:
    /// x(t) = (x0 + (v0 + w x0) t) e^(-w t), a smooth start and stop with no overshoot from rest.
    /// Below 1 it is underdamped: x(t) = e^(-z w t) (x0 cos(wd t) + (v0 + z w x0) / wd sin(wd t)).
    /// A retarget keeps the current speed. `response` is the period (as in SwiftUI); motion looks
    /// done at about 0.8x it. A target more than two viewports away is first brought to two
    /// viewports. `velocity` is in points per second; feed the returned one back in.
    static func spring(from y: CGFloat, to target: CGFloat, velocity: CGFloat, dt: CFTimeInterval,
                       viewport: CGFloat, response: Double,
                       damping: Double = 1) -> (y: CGFloat, velocity: CGFloat, done: Bool) {
        let dt = min(max(dt, 1.0 / 240), 0.05)
        var y = Double(y)
        let target = Double(target)
        if viewport > 0, abs(target - y) > 2 * Double(viewport) {
            y = target - (target > y ? 2 : -2) * Double(viewport)
        }
        let w = 2 * Double.pi / response
        let x0 = y - target, v0 = Double(velocity)
        let x: Double, v: Double
        if damping < 1 {
            let z = damping
            let wd = w * (1 - z * z).squareRoot()
            let e = exp(-z * w * dt), c = cos(wd * dt), s = sin(wd * dt)
            x = e * (x0 * c + (v0 + z * w * x0) / wd * s)
            v = e * (v0 * c - (z * w * v0 + w * w * x0) / wd * s)
        } else {
            let e = exp(-w * dt)
            x = (x0 + (v0 + w * x0) * dt) * e
            v = (v0 - (v0 + w * x0) * w * dt) * e
        }
        if abs(x) < 0.5, abs(v) < 30 { return (CGFloat(target), 0, true) }
        return (CGFloat(target + x), CGFloat(v), false)
    }

    // MARK: - Reveal

    /// Edge margin the focused item keeps when a long list scrolls.
    static let edgeInset: CGFloat = 180

    /// Smallest offset change that keeps `frame` at least `edgeInset` inside a
    /// viewport of `height` resting at `offset`. An item too tall to fit is centred.
    static func minimalOffset(revealing frame: CGRect, from offset: CGFloat, height: CGFloat) -> CGFloat {
        let inset = height >= 2 * edgeInset ? edgeInset : 0
        if frame.height > height - 2 * inset { return frame.midY - height / 2 }
        if frame.minY < offset + inset { return frame.minY - inset }
        if frame.maxY > offset + height - inset { return frame.maxY - height + inset }
        return offset
    }
}
