// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2026 Bain Gurley

// Lookups that tell an outside service which title or person is on screen. Each is off unless
// its switch is turned on (Settings > About > Privacy), and each is read at the one place its
// request is made, so nothing is built or sent while it is off. Per device, never synced.

import Foundation

nonisolated enum OutsideLookups {

    /// Bool; absent = off. The app developer's servers: everything sent through `attestedData`
    /// (extra ratings, the TMDB proxy, trivia, scores, the error-report pass, diagnostics upload)
    /// and the App Attest enrollment that goes with it.
    static let developerKey = "outsideLookupsDeveloper"
    /// Bool; absent = off. Plex's online age guidance (Common Sense Media) for a title.
    static let plexAdvisoryKey = "outsideLookupsPlexAdvisory"
    /// Bool; absent = off. Plex's online biography and Known For titles on a person's page.
    static let plexPeopleKey = "outsideLookupsPlexPeople"

    static var developer: Bool {
        get { UserDefaults.standard.bool(forKey: developerKey) }
        set { UserDefaults.standard.set(newValue, forKey: developerKey) }
    }

    static var plexAdvisory: Bool {
        get { UserDefaults.standard.bool(forKey: plexAdvisoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: plexAdvisoryKey) }
    }

    static var plexPeople: Bool {
        get { UserDefaults.standard.bool(forKey: plexPeopleKey) }
        set { UserDefaults.standard.set(newValue, forKey: plexPeopleKey) }
    }
}
