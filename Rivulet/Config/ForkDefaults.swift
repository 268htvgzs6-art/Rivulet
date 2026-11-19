// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import Foundation

/// The fork's 1.6 defaults, applied once over whatever was saved before, so an existing
/// install gets them too: 15 s skips both ways, Arabic subtitles over audio that is not English,
/// and IMDb on the detail page's rating row. Settings changes them back as usual afterwards.
/// Fresh installs read the same values as the code defaults.
enum ForkDefaults {
    private static let appliedKey = "fork.defaults.v1_6"

    static func applyOnce(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(true, forKey: appliedKey)
        defaults.set(SkipInterval.fifteenSeconds.rawValue, forKey: SkipInterval.storageKey)
        // Unset Skip Back follows Skip Forward.
        defaults.removeObject(forKey: SkipInterval.backStorageKey)
        defaults.set(MediaRating.Source.imdb.rawValue, forKey: MediaRating.detailSourceKey)
        // The current profile's subtitle choice (a single-user install has only the one).
        TrackIntentStore.subtitleIntent = .foreignAudio(language: TrackIntentStore.defaultSubtitleLanguage,
                                                        hearingImpaired: false)
    }
}
