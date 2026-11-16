// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import os
import XCTest
@testable import Rivulet

/// PosterPrefetcher's queue: lane order, pausing, and a stopped library walk carrying on where it got
/// to. The disk and the downloads are fakes; nothing reaches the network or ImageCacheManager.
final class PosterPrefetcherTests: XCTestCase {

    private func url(_ n: Int) -> URL {
        URL(string: "https://server.test/poster/\(n)")!
    }

    private func item(_ n: Int) -> MediaItem {
        MediaItem(
            ref: MediaItemRef(providerID: "test", itemID: "\(n)"),
            kind: .movie, title: "\(n)", sortTitle: nil, overview: nil,
            year: nil, runtime: nil, parentRef: nil, grandparentRef: nil,
            episodeNumber: nil, seasonNumber: nil, childProgress: nil,
            userState: MediaUserState(isPlayed: false, viewOffset: 0, isFavorite: false, lastViewedAt: nil),
            artwork: MediaArtwork(poster: url(n), backdrop: nil, thumbnail: nil, logo: nil),
            parentArtwork: nil, grandparentArtwork: nil
        )
    }

    /// A store whose downloads land on its disk at once, recorded in `downloads`.
    private func store(_ downloads: OSAllocatedUnfairLock<[URL]>) -> PosterPrefetcher.Store {
        PosterPrefetcher.Store(
            isOnDisk: { url in downloads.withLock { $0.contains(url) } },
            hasRoom: { true },
            download: { url in
                downloads.withLock { $0.append(url) }
                return .downloaded
            },
            waitForQuiet: {})
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "timed out")
    }

    func test_queue_homeRowsComeFirst_columnByColumn() async {
        let prefetcher = PosterPrefetcher(store: store(.init(initialState: [])))
        await prefetcher.setPause(.background, true, seq: 1)   // nothing starts
        await prefetcher.enqueueRows([[item(20), item(21)]], watchlist: [], lane: .libraryRows)
        await prefetcher.enqueueRows([[item(1), item(2), item(3)], [item(4)], [item(5), item(6)]],
                                     watchlist: [], lane: .homeRows)
        // A row snapshot sent again queues nothing twice.
        await prefetcher.enqueueRows([[item(1), item(2)]], watchlist: [], lane: .homeRows)

        let queued = await prefetcher.queuedURLs
        XCTAssertEqual(queued, [1, 4, 5, 2, 6, 3, 20, 21].map(url))
    }

    func test_pause_holdsDownloadsUntilEveryReasonClears() async throws {
        let downloads = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let prefetcher = PosterPrefetcher(store: store(downloads))
        await prefetcher.setPause(.background, true, seq: 1)
        await prefetcher.setPause(.playback, true, seq: 2)
        await prefetcher.enqueueRows([[item(1), item(2), item(3)]], watchlist: [], lane: .homeRows)

        await prefetcher.setPause(.background, false, seq: 3)   // playback still pauses
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(downloads.withLock { $0 }.isEmpty)
        let held = await prefetcher.queuedURLs
        XCTAssertEqual(held, [1, 2, 3].map(url))

        await prefetcher.setPause(.playback, false, seq: 4)
        try await waitUntil { downloads.withLock { $0.count } == 3 }
        XCTAssertEqual(Set(downloads.withLock { $0 }), Set([1, 2, 3].map(url)))
        let left = await prefetcher.queuedURLs
        XCTAssertTrue(left.isEmpty)
    }

    /// First visit to a 250-item library: page 0 downloads, then the page is left while page 100
    /// is still loading. Returns the prefetcher and its downloads for the second visit.
    private func walkStoppedAfterFirstPage(items: [MediaItem])
        async throws -> (PosterPrefetcher, OSAllocatedUnfairLock<[URL]>) {
        let downloads = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let prefetcher = PosterPrefetcher(store: store(downloads))
        let starts = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let fetch: PosterPrefetcher.PageFetch = { start, size in
            starts.withLock { $0.append(start) }
            if start > 0 { try await Task.sleep(for: .seconds(30)) }   // cancelled by the stop
            return (Array(items[start..<min(start + size, items.count)]), items.count)
        }
        await prefetcher.libraryAppeared(id: "lib", order: "titleSort", rows: [], fetch: fetch)
        try await waitUntil {
            downloads.withLock { $0.count } == 100 && starts.withLock { $0 } == [0, 100]
        }
        await prefetcher.libraryLeft(id: "lib")
        return (prefetcher, downloads)
    }

    func test_libraryWalk_leftAndShownAgain_carriesOnFromItsPosition() async throws {
        let items = (0..<250).map(item)
        let (prefetcher, downloads) = try await walkStoppedAfterFirstPage(items: items)

        let starts = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let fetch: PosterPrefetcher.PageFetch = { start, size in
            starts.withLock { $0.append(start) }
            return (Array(items[start..<min(start + size, items.count)]), items.count)
        }
        await prefetcher.libraryAppeared(id: "lib", order: "titleSort", rows: [], fetch: fetch)
        try await waitUntil { downloads.withLock { $0.count } == 250 }

        // A poster still finishing when the page was left rewinds the position to it, so the walk
        // carries on from item 98, 99 or 100 (two workers), never from the start.
        let first = try XCTUnwrap(starts.withLock { $0 }.first)
        XCTAssertTrue((98...100).contains(first), "resumed at \(first)")
        XCTAssertEqual(Set(downloads.withLock { $0 }), Set((0..<250).map(url)))
        XCTAssertEqual(downloads.withLock { $0.count }, 250, "each poster downloads once")
    }

    func test_libraryWalk_underAnotherSort_startsOver() async throws {
        let items = (0..<250).map(item)
        let (prefetcher, _) = try await walkStoppedAfterFirstPage(items: items)

        let starts = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let fetch: PosterPrefetcher.PageFetch = { start, size in
            starts.withLock { $0.append(start) }
            return (Array(items[start..<min(start + size, items.count)]), items.count)
        }
        await prefetcher.libraryAppeared(id: "lib", order: "addedAt", rows: [], fetch: fetch)
        try await waitUntil { !starts.withLock { $0 }.isEmpty }
        XCTAssertEqual(starts.withLock { $0 }.first, 0)
    }
}
