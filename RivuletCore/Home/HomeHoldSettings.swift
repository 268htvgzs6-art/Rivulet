// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2026 Bain Gurley

// Poster Spotlight (Settings > Appearance): how long focus rests on a poster before the page
// fades out for that title's wide picture. The hold itself is the tvOS Home page's (HomeWash).

import Foundation

nonisolated enum HomeHoldSettings {

    /// Int seconds, one of `options`; 0 = off; absent = `defaultSeconds`. Per device, not synced.
    static let secondsKey = "homeHoldSeconds"
    static let options = [0, 1, 2, 3, 5]
    static let defaultSeconds = 2

    /// A stored value that is not an option reads as the default.
    static func clamp(_ seconds: Int) -> Int { options.contains(seconds) ? seconds : defaultSeconds }

    static var seconds: Int {
        get { clamp(UserDefaults.standard.object(forKey: secondsKey) as? Int ?? defaultSeconds) }
        set { UserDefaults.standard.set(clamp(newValue), forKey: secondsKey) }
    }

    /// The hold in seconds; nil when the picture is turned off.
    static func holdDelay(seconds: Int) -> TimeInterval? { seconds > 0 ? TimeInterval(seconds) : nil }
    static var holdDelay: TimeInterval? { holdDelay(seconds: seconds) }

    /// The option after `current`, wrapping 5 back to Off (the Settings row).
    static func next(after current: Int) -> Int {
        let index = options.firstIndex(of: clamp(current)) ?? 0
        return options[(index + 1) % options.count]
    }
}
