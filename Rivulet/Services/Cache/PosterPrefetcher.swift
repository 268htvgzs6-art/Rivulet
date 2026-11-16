// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Background poster download. Puts the posters of Home's rows and of the open library into
// ImageCacheManager's disk cache before they scroll on screen, so a tile decodes from disk instead
// of waiting on the server's photo transcoder.
//
// - URLs are the ones the tiles load (`PosterCell.posterURL(for:)`, and a watchlist entry's
//   `posterURL`, which WatchlistPosterCell loads) and go through `ImageCacheManager.prefetchToDisk`,
//   which applies the same `.thumb` rewrite, trust and cache key as the tile's load, on its own
//   one-connection session so it never holds a tile's connection.
// - Three lanes, drained in order: Home's rows (column by column, so every row's next tiles come
//   first), the open library's full item list (walked in pages of 100), that library's own rows.
// - Two workers, off the main actor, on a session with one connection per host (so over HTTP/1.1,
//   one download at a time per server). On-screen loads win: nothing new starts while a tile's own
//   load is on the network, or until 0.4 s after the last scroll frame (`noteMotion`, called by
//   Home's and the shelves' scroll drivers); a download already running finishes.
// - Everything pauses while no Home or library page is on screen, while a video plays, and while
//   the app is in the background; it carries on where it was when one of those ends.
// - A library walk pauses while its page is only covered (the player, a full-screen page). Leaving
//   the page (tab switch, dismissal) stops it and drops its queued posters, but its position is kept:
//   showing the library again continues from there. The Plex server or profile token changing drops
//   everything. A walk is capped at 5000 items, and nothing is fetched once the disk cache is at 90%
//   of its 5 GB budget. A poster that failed is retried by a later walk (rows: after 2 minutes).

import Combine
import Foundation
import os
import UIKit

actor PosterPrefetcher {
    static let shared = PosterPrefetcher(store: .live)

    /// The disk cache and network the prefetcher works through; tests pass their own.
    nonisolated struct Store: Sendable {
        var isOnDisk: @Sendable (URL) -> Bool
        var hasRoom: @Sendable () async -> Bool
        var download: @Sendable (URL) async -> ImageCacheManager.DiskPrefetchOutcome
        /// Returns once the screen is still and no on-screen load is on the network.
        var waitForQuiet: @Sendable () async -> Void

        static let live = Store(
            isOnDisk: { ImageCacheManager.shared.isOnDisk($0) },
            hasRoom: { await ImageCacheManager.shared.prefetchHasRoom() },
            download: { await ImageCacheManager.shared.prefetchToDisk($0) },
            waitForQuiet: { await PosterPrefetcher.waitForQuiet() })
    }

    private let store: Store

    init(store: Store) {
        self.store = store
    }

    /// Where a poster came from. A lower lane always downloads first.
    nonisolated enum Lane: Int, Sendable, CaseIterable {
        case homeRows = 0
        case libraryWalk = 1
        case libraryRows = 2
    }

    /// Why the whole prefetcher is paused. Any one of them pauses every lane.
    nonisolated enum PauseReason: Int, Sendable, CaseIterable {
        case background
        /// No Home or library page is in the window (another tab, or a full-screen page covers it).
        case noBrowsePage
        /// A video is playing.
        case playback
    }

    /// One page of the open library, mapped exactly as its grid maps it, so each item's poster URL is
    /// the one its grid tile will request. Runs on the main actor (the grid's mapper lives there).
    typealias PageFetch = @MainActor @Sendable (_ start: Int, _ size: Int) async throws -> (items: [MediaItem], total: Int?)

    // MARK: - Tuning

    nonisolated private static let maxConcurrent = 2
    nonisolated private static let quietAfterMotion: TimeInterval = 0.4
    /// How often a waiting worker looks again while a tile's own load is on the network.
    nonisolated private static let foregroundPoll: TimeInterval = 0.1
    nonisolated private static let walkPageSize = 100
    nonisolated private static let walkItemCap = 5000
    /// The walk fetches no further page while this many of its posters still wait to download.
    nonisolated private static let walkBacklog = 300
    /// A library walked to the end is not walked again for this long (its new items arrive through the rows).
    nonisolated private static let rewalkAfter: TimeInterval = 30 * 60
    /// A row poster that failed is not queued again for this long (rows re-send on every snapshot).
    nonisolated private static let retryRowAfter: TimeInterval = 120

    // MARK: - Scroll and foreground gate

    nonisolated private static let lastMotion = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    /// Records that the screen is scrolling. One uptime read and an unfair lock: safe per display frame.
    nonisolated static func noteMotion() {
        let now = ProcessInfo.processInfo.systemUptime
        lastMotion.withLock { $0 = now }
    }

    /// Returns once nothing has scrolled for `quietAfterMotion` and no on-screen image load is on the
    /// network (or the task is cancelled).
    nonisolated private static func waitForQuiet() async {
        while !Task.isCancelled {
            let still = ProcessInfo.processInfo.systemUptime - lastMotion.withLock { $0 }
            if still < quietAfterMotion {
                try? await Task.sleep(for: .seconds(quietAfterMotion - still + 0.02))
                continue
            }
            // A tile's own load is downloading: let it have the server.
            if ImageCacheManager.foregroundFetchesInFlight > 0 {
                try? await Task.sleep(for: .seconds(foregroundPoll))
                continue
            }
            return
        }
    }

    // MARK: - Queue state

    nonisolated private struct Entry: Sendable {
        let url: URL
        let lane: Lane
        /// The walk that queued it; 0 for a row poster.
        let walk: Int
        /// The item's position in its walk (0 for a row poster), so a stopped walk can continue
        /// from its first poster that never downloaded.
        let offset: Int
    }

    nonisolated private struct WalkState {
        let id: String
        /// The grid order the walk pages in; saved progress only resumes under the same order.
        let order: String
        let serial: Int
        let fetch: PageFetch
        var task: Task<Void, Never>?
        /// Next item offset to fetch, kept across a pause and (through `walkProgress`) a stop.
        var nextStart = 0
        var enumerated = false
        var pageFailed = false
        var items = 0, queued = 0, onDisk = 0, downloaded = 0, failed = 0
        /// Queued posters not yet finished.
        var outstanding = 0
        /// Offsets of this walk's posters downloading right now (a stop rewinds to before them).
        var running: Set<Int> = []
    }

    /// Where a stopped walk got to, so showing its library again continues from there.
    nonisolated private struct WalkProgress {
        let order: String
        let nextStart: Int
        let items: Int, queued: Int, onDisk: Int, downloaded: Int, failed: Int
    }

    /// FIFO per lane; `heads` index the next entry so a pop is O(1).
    private var lanes: [[Entry]] = Array(repeating: [], count: Lane.allCases.count)
    private var heads: [Int] = Array(repeating: 0, count: Lane.allCases.count)
    private var inFlight: [Int] = Array(repeating: 0, count: Lane.allCases.count)
    /// Every URL queued, running, done or found on disk this session (until a reset). A failed one
    /// leaves it again, so a later walk retries it.
    private var known: Set<URL> = []
    /// Row posters that failed, and when; not queued again until `retryRowAfter` has passed.
    private var rowFailures: [URL: TimeInterval] = [:]
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var suspended = false
    private var pauseReasons: Set<PauseReason> = []
    /// The newest main-actor sequence number applied per reason; an older, late-arriving change is dropped.
    private var pauseSeen: [PauseReason: Int] = [:]
    /// Bumped by `reset`: a worker or walk from an older epoch stops.
    private var epoch = 0
    private var walk: WalkState?
    private var walkSerial = 0
    private var finishedWalks: [String: TimeInterval] = [:]
    private var walkProgress: [String: WalkProgress] = [:]
    /// The library page on screen; its rows fill `.libraryRows`.
    private var libraryOnScreenID: String?
    private var rowStats = (downloaded: 0, failed: 0)

    // MARK: - Main-actor entry points

    @MainActor private static var observers: [AnyCancellable] = []
    /// The Home and library pages in the window (weak, so a page that never
    /// reported leaving cannot hold the prefetcher open).
    @MainActor private static let browsePages = NSHashTable<AnyObject>.weakObjects()
    @MainActor private static var playersActive = 0
    @MainActor private static var pauseSequence = 0

    /// Home's poster rows, in screen order, plus its Watchlist row.
    @MainActor static func homeRowsChanged(_ rows: [[MediaItem]], watchlist: [PlexWatchlistItem]) {
        installObserversIfNeeded()
        Task { await shared.enqueueRows(rows, watchlist: watchlist, lane: .homeRows) }
    }

    /// A library page is on screen: walk its whole list (`id` names the library, `order` the grid
    /// sort the walk pages in) and queue its rows.
    @MainActor static func libraryOnScreen(id: String, order: String, rows: [[MediaItem]], fetch: @escaping PageFetch) {
        installObserversIfNeeded()
        Task { await shared.libraryAppeared(id: id, order: order, rows: rows, fetch: fetch) }
    }

    /// The library page was left (not merely covered): stop its walk, keeping its position, and drop
    /// its queued posters.
    @MainActor static func libraryOffScreen(id: String) {
        Task { await shared.libraryLeft(id: id) }
    }

    /// A Home or library page appeared. The prefetcher runs only while one is in the window.
    @MainActor static func browsePageAppeared(_ page: AnyObject) {
        installObserversIfNeeded()
        browsePages.add(page)
        setPause(.noBrowsePage, false)
    }

    /// A Home or library page left the window (covered or gone). The last one pauses everything.
    @MainActor static func browsePageDisappeared(_ page: AnyObject) {
        browsePages.remove(page)
        setPause(.noBrowsePage, browsePages.allObjects.isEmpty)
    }

    /// Sequenced, because the actor may receive two quick changes out of order.
    @MainActor private static func setPause(_ reason: PauseReason, _ on: Bool) {
        pauseSequence += 1
        let seq = pauseSequence
        Task { await shared.setPause(reason, on, seq: seq) }
    }

    @MainActor private static func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { setPause(.background, true) } })
        observers.append(center.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { setPause(.background, false) } })
        // The VOD player posts these as it starts and leaves (UniversalPlayerView).
        // A leave can arrive without a start (the player closed before it began), so the count floors at 0.
        observers.append(center.publisher(for: .plexPlaybackStarted)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    playersActive += 1
                    setPause(.playback, true)
                }
            })
        observers.append(center.publisher(for: .plexPlaybackStopped)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    playersActive = max(0, playersActive - 1)
                    setPause(.playback, playersActive > 0)
                }
            })
        // A server or profile switch changes the token: everything queued belongs to the old one.
        let auth = PlexAuthManager.shared
        observers.append(auth.$selectedServerToken.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in Task { await shared.reset() } })
        observers.append(auth.$selectedServerURL.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in Task { await shared.reset() } })
    }

    // MARK: - Enqueue

    func enqueueRows(_ rows: [[MediaItem]], watchlist: [PlexWatchlistItem], lane: Lane) {
        // Column by column: every row's next few tiles before any row's tail.
        var urls: [URL] = []
        let width = rows.map(\.count).max() ?? 0
        for column in 0..<width {
            for row in rows where column < row.count {
                if let url = PosterCell.posterURL(for: row[column]) { urls.append(url) }
            }
        }
        urls += watchlist.compactMap(\.posterURL)   // what WatchlistPosterCell loads
        let now = ProcessInfo.processInfo.systemUptime
        for url in urls {
            if let failedAt = rowFailures[url] {
                if now - failedAt < Self.retryRowAfter { continue }
                rowFailures[url] = nil
            }
            guard known.insert(url).inserted else { continue }
            if store.isOnDisk(url) { continue }
            push(Entry(url: url, lane: lane, walk: 0, offset: 0))
        }
        pump()
    }

    private func enqueueWalkItems(_ items: [MediaItem], start: Int, serial: Int) {
        guard var state = walk, state.serial == serial else { return }
        for (index, item) in items.enumerated() {
            state.items += 1
            guard let url = PosterCell.posterURL(for: item) else { continue }
            // Disk first, so only a poster really on disk counts as "on disk".
            if store.isOnDisk(url) {
                known.insert(url)
                state.onDisk += 1
                continue
            }
            // Already queued or running for Home's rows: it is coming, just not through this walk.
            guard known.insert(url).inserted else {
                state.queued += 1
                continue
            }
            state.queued += 1
            state.outstanding += 1
            push(Entry(url: url, lane: .libraryWalk, walk: serial, offset: start + index))
        }
        walk = state
        pump()
    }

    private func push(_ entry: Entry) {
        lanes[entry.lane.rawValue].append(entry)
    }

    private func pending(_ lane: Lane) -> Int {
        lanes[lane.rawValue].count - heads[lane.rawValue]
    }

    /// The posters waiting to start, in the order they will start (tests).
    var queuedURLs: [URL] {
        Lane.allCases.flatMap { lane in lanes[lane.rawValue][heads[lane.rawValue]...].map(\.url) }
    }

    private func popNext() -> Entry? {
        for lane in Lane.allCases where pending(lane) > 0 {
            let index = lane.rawValue
            let entry = lanes[index][heads[index]]
            heads[index] += 1
            if heads[index] == lanes[index].count {
                lanes[index].removeAll(keepingCapacity: true)
                heads[index] = 0
            }
            inFlight[index] += 1
            if entry.walk != 0, walk?.serial == entry.walk { walk?.running.insert(entry.offset) }
            return entry
        }
        return nil
    }

    /// Puts an entry that never started back at the head of its lane.
    private func requeue(_ entry: Entry) {
        let index = entry.lane.rawValue
        inFlight[index] -= 1
        if entry.walk != 0, walk?.serial == entry.walk { walk?.running.remove(entry.offset) }
        let orphaned = entry.walk != 0 ? walk?.serial != entry.walk
            : entry.lane == .libraryRows && libraryOnScreenID == nil
        if orphaned {
            known.remove(entry.url)   // its walk or library page is gone: a later visit may queue it again
            return
        }
        if heads[index] > 0 {
            heads[index] -= 1
            lanes[index][heads[index]] = entry
        } else {
            lanes[index].insert(entry, at: 0)
        }
    }

    /// Drops what has not started in `lane`; those URLs may be queued again later.
    private func clear(_ lane: Lane) {
        let index = lane.rawValue
        for entry in lanes[index][heads[index]...] { known.remove(entry.url) }
        lanes[index].removeAll()
        heads[index] = 0
    }

    // MARK: - Workers

    private func pump() {
        guard !suspended else { return }
        while workers.count < Self.maxConcurrent, Lane.allCases.contains(where: { pending($0) > 0 }) {
            let id = UUID()
            let epoch = self.epoch
            workers[id] = Task.detached(priority: .utility) { [weak self] in
                await self?.work(id: id, epoch: epoch)
            }
        }
    }

    private func work(id: UUID, epoch: Int) async {
        while !Task.isCancelled, !suspended, epoch == self.epoch, let entry = popNext() {
            await store.waitForQuiet()
            guard !Task.isCancelled, !suspended, epoch == self.epoch else {
                if epoch == self.epoch { requeue(entry) }
                break
            }
            let outcome = await store.download(entry.url)
            guard epoch == self.epoch else { break }
            if Task.isCancelled, case .failed = outcome {
                requeue(entry)   // cancelled by a suspend, not a real failure
                break
            }
            finish(entry, outcome)
            if case .noRoom = outcome {
                // Disk budget reached: stop everything; a later page visit checks again.
                if let current = walk { endWalk(current, stopped: true) }
                for lane in Lane.allCases { clear(lane) }
                break
            }
        }
        workers[id] = nil
        pump()
    }

    private func finish(_ entry: Entry, _ outcome: ImageCacheManager.DiskPrefetchOutcome) {
        let index = entry.lane.rawValue
        inFlight[index] -= 1
        if case .noRoom = outcome { known.remove(entry.url) }
        // A real failure (not a cancel) forgets the URL, so a later walk or row pass
        // tries it again. A 4xx never reaches the network twice: ImageCacheManager remembers it.
        if case .failed = outcome, !Task.isCancelled {
            known.remove(entry.url)
            if entry.walk == 0 { rowFailures[entry.url] = ProcessInfo.processInfo.systemUptime }
        }
        if entry.walk != 0 {
            guard var state = walk, state.serial == entry.walk else { return }
            switch outcome {
            case .onDisk: state.onDisk += 1; state.queued -= 1
            case .downloaded: state.downloaded += 1
            case .failed, .noRoom: state.failed += 1
            }
            state.outstanding -= 1
            state.running.remove(entry.offset)
            walk = state
            finishWalkIfDone()
            return
        }
        switch outcome {
        case .downloaded: rowStats.downloaded += 1
        case .failed: rowStats.failed += 1
        case .onDisk, .noRoom: break
        }
        // One line each time the row lanes drain after real work.
        let rowsIdle = pending(.homeRows) + pending(.libraryRows) + inFlight[Lane.homeRows.rawValue]
            + inFlight[Lane.libraryRows.rawValue] == 0
        if rowsIdle, rowStats.downloaded + rowStats.failed > 0 {
            DiagLog.notice(.home, "Poster prefetch rows: \(rowStats.downloaded) downloaded, \(rowStats.failed) failed")
            rowStats = (0, 0)
        }
    }

    // MARK: - Library walk

    func libraryAppeared(id: String, order: String, rows: [[MediaItem]], fetch: @escaping PageFetch) {
        if libraryOnScreenID != id { clear(.libraryRows) }
        libraryOnScreenID = id
        startWalk(id: id, order: order, fetch: fetch)
        enqueueRows(rows, watchlist: [], lane: .libraryRows)
    }

    func libraryLeft(id: String) {
        guard libraryOnScreenID == id else { return }
        libraryOnScreenID = nil
        clear(.libraryRows)
        stopWalk(id: id)
    }

    private func startWalk(id: String, order: String, fetch: @escaping PageFetch) {
        // The same library coming back from a pause (covered, not left): its walk simply carries on.
        if walk?.id == id { return }
        if let done = finishedWalks[id], ProcessInfo.processInfo.systemUptime - done < Self.rewalkAfter { return }
        if let current = walk { endWalk(current, stopped: true) }
        walkSerial += 1
        var state = WalkState(id: id, order: order, serial: walkSerial, fetch: fetch)
        // A walk stopped earlier continues where it got to, under the same sort only.
        if let saved = walkProgress.removeValue(forKey: id), saved.order == order {
            state.nextStart = saved.nextStart
            state.items = saved.items
            state.queued = saved.queued
            state.onDisk = saved.onDisk
            state.downloaded = saved.downloaded
            state.failed = saved.failed
            DiagLog.notice(.home, "Poster prefetch library walk resumed at item \(saved.nextStart)")
        }
        walk = state
        launchWalk()
    }

    private func stopWalk(id: String) {
        guard let current = walk, current.id == id else { return }
        endWalk(current, stopped: true)
    }

    private func launchWalk() {
        guard !suspended, let state = walk, state.task == nil, !state.enumerated else { return }
        let serial = state.serial, epoch = self.epoch
        walk?.task = Task.detached(priority: .utility) { [weak self] in
            await self?.enumerate(serial: serial, epoch: epoch)
        }
    }

    private func enumerate(serial: Int, epoch: Int) async {
        while !Task.isCancelled, epoch == self.epoch, let state = walk, state.serial == serial,
              state.nextStart < Self.walkItemCap {
            // Never run far ahead of the downloads.
            if pending(.libraryWalk) > Self.walkBacklog {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            await store.waitForQuiet()
            guard !Task.isCancelled, walk?.serial == serial else { return }
            guard await store.hasRoom() else { break }
            let start = state.nextStart
            let page: (items: [MediaItem], total: Int?)
            do {
                page = try await state.fetch(start, min(Self.walkPageSize, Self.walkItemCap - start))
            } catch {
                if Task.isCancelled { return }
                if error is CancellationError {
                    // The page's own check: the library page is gone or the server changed.
                    if let current = walk, current.serial == serial { endWalk(current, stopped: true) }
                    return
                }
                walk?.pageFailed = true
                break
            }
            guard !Task.isCancelled, epoch == self.epoch, walk?.serial == serial else { return }
            walk?.nextStart = start + page.items.count
            enqueueWalkItems(page.items, start: start, serial: serial)
            if page.items.isEmpty { break }
            if let total = page.total, start + page.items.count >= total { break }
        }
        guard !Task.isCancelled, epoch == self.epoch, walk?.serial == serial else { return }
        walk?.enumerated = true
        walk?.task = nil
        finishWalkIfDone()
    }

    private func finishWalkIfDone() {
        guard let state = walk, state.enumerated, state.outstanding <= 0 else { return }
        endWalk(state, stopped: false)
    }

    /// Logs the walk once (counts only) and forgets it. A stopped walk drops its unstarted posters and
    /// keeps its position (`walkProgress`), rewound to its first poster that never started.
    private func endWalk(_ state: WalkState, stopped: Bool) {
        state.task?.cancel()
        if stopped {
            // The lane is FIFO, so its first entry of this walk is the lowest unstarted
            // offset; one still downloading may be lower. Counts are rewound with it (posters already on
            // disk in the rewound span are counted again: the log's "on disk" is approximate after a resume).
            let index = Lane.libraryWalk.rawValue
            let unstarted = lanes[index][heads[index]...].filter { $0.walk == state.serial }
            let resumeAt = [unstarted.first?.offset, state.running.min(), state.nextStart].compactMap { $0 }.min()
                ?? state.nextStart
            walkProgress[state.id] = WalkProgress(
                order: state.order, nextStart: resumeAt, items: min(state.items, resumeAt),
                queued: max(0, state.queued - unstarted.count - state.running.count), onDisk: state.onDisk,
                downloaded: state.downloaded, failed: state.failed)
            clear(.libraryWalk)
        } else {
            walkProgress[state.id] = nil
            // A walk cut short by a failed page tries again in 2 minutes, a full one in 30.
            let now = ProcessInfo.processInfo.systemUptime
            finishedWalks[state.id] = state.pageFailed ? now - Self.rewalkAfter + 120 : now
        }
        walk = nil
        let how = stopped ? "stopped" : (state.pageFailed ? "ended on a failed page" : "done")
        DiagLog.notice(.home, "Poster prefetch library walk \(how): \(state.items) items, \(state.queued) queued, "
            + "\(state.onDisk) already on disk, \(state.downloaded) downloaded, \(state.failed) failed")
    }

    // MARK: - Lifecycle

    /// Applies one pause reason; the prefetcher runs only while none is set.
    func setPause(_ reason: PauseReason, _ on: Bool, seq: Int) {
        guard seq > pauseSeen[reason, default: 0] else { return }
        pauseSeen[reason] = seq
        if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        if pauseReasons.isEmpty { resume() } else { suspend() }
    }

    private func suspend() {
        guard !suspended else { return }
        suspended = true
        workers.values.forEach { $0.cancel() }
        walk?.task?.cancel()
        walk?.task = nil
    }

    private func resume() {
        guard suspended else { return }
        suspended = false
        launchWalk()
        pump()
    }

    /// Server or profile changed: drop everything, including what this session already knows.
    private func reset() {
        epoch += 1
        // Cancelled workers leave `workers` as they exit, so no more than `maxConcurrent` ever run.
        workers.values.forEach { $0.cancel() }
        if let current = walk { endWalk(current, stopped: true) }
        for lane in Lane.allCases { clear(lane) }
        inFlight = Array(repeating: 0, count: Lane.allCases.count)
        known.removeAll()
        rowFailures.removeAll()
        finishedWalks.removeAll()
        walkProgress.removeAll()
        libraryOnScreenID = nil
        rowStats = (0, 0)
    }
}
