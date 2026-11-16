// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Poster hub cell wrapping `TVPosterView` for native focus motion.
// Caption stays nil: a set caption reserves bottom space even while hidden and crops 2:3 posters.
// Overlays sit in a sibling `overlayContainer` that copies the poster's mask and focus scale,
// because subviews added to `posterView.imageView` do not render.

import UIKit
import TVUIKit

@MainActor
final class PosterCell: UICollectionViewCell {
    static let reuseID = "PosterCell"

    private let posterView = TVPosterView()

    /// Hosts the overlays; its transform follows the poster's focus zoom in `didUpdateFocus`.
    private let overlayContainer = UIView()

    // The server and edition badges, the failure icon and title, the progress bar and the spinner
    // are built on first use (the `ensure…` functions): most tiles never show them, and building
    // them in every cell was a measured part of `init` as rows scroll in.
    // Back to front: placeholder, spinner, blur band, bar, trailing badges, server badge,
    // failure icon, failure title, watched glyph.
    private let watchedBadge = PosterWatchedBadge()
    private var sourceBadge: SourceBadgeView?
    /// Plex edition ("Director's Cut"), so two editions sharing a poster tell apart.
    private var editionBadge: SourceBadgeView?
    /// Top-trailing column: unwatched count, then edition badge.
    private let trailingBadges = UIStackView()
    private var failureIcon: UIImageView?
    /// The title on the failure card, so an item with no artwork is still named.
    private var failureTitle: UILabel?
    private var progressInfoBar: MediaProgressInfoBar?
    /// The focus look a bar built later starts with: the last of `didUpdateFocus` and a bar reset.
    private var barFocusedState = false

    /// Apple-style watched glyph, bottom-left (the progress bar's slot).
    private let watchedGlyph = WatchedGlyphView()

    /// Glass card shown in place of the bare `TVPosterView` gray while the
    /// artwork loads (and on a genuine load failure, with the faint type icon
    /// on top). Plain view, not a blur — a UIVisualEffectView per cell is a
    /// measured perf cost (see `bottomInfoBlur`).
    private let placeholderPanel = UIView()
    private var loadingSpinner: UIActivityIndicatorView?
    /// Delays the spinner so a fast cache hit doesn't flash it on scroll.
    private var spinnerDelayTask: Task<Void, Never>?
    /// Bottom-quarter blur under the info bar, in-progress items only. Created lazily:
    /// a UIVisualEffectView per cell was a measured part of the launch snapshot apply.
    private var bottomInfoBlur: BottomInfoBlurView?

    @discardableResult
    private func ensureBottomInfoBlur() -> BottomInfoBlurView {
        if let existing = bottomInfoBlur { return existing }
        let blur = BottomInfoBlurView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        // Under the info bar in z-order.
        overlayContainer.insertSubview(blur, belowSubview: ensureProgressInfoBar())
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
            blur.heightAnchor.constraint(equalTo: overlayContainer.heightAnchor, multiplier: 0.25)
        ])
        bottomInfoBlur = blur
        return blur
    }

    @discardableResult
    private func ensureProgressInfoBar() -> MediaProgressInfoBar {
        if let progressInfoBar { return progressInfoBar }
        let bar = MediaProgressInfoBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        overlayContainer.insertSubview(bar, belowSubview: trailingBadges)
        NSLayoutConstraint.activate([
            // Same slot as ContinueWatchingCell's status row.
            bar.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor,
                                         constant: MediaProgressInfoBar.leadingInset),
            bar.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor,
                                          constant: -MediaProgressInfoBar.leadingInset),
            bar.centerYAnchor.constraint(equalTo: overlayContainer.bottomAnchor,
                                         constant: -MediaProgressInfoBar.centerFromBottom)
        ])
        bar.reset()
        bar.setFocused(barFocusedState)
        progressInfoBar = bar
        return bar
    }

    /// Hides the in-progress bar and its blur band, as a reset bar.
    private func hideProgressBar() {
        progressInfoBar?.isHidden = true; bottomInfoBlur?.isHidden = true
        progressInfoBar?.reset()
        barFocusedState = false
    }

    private func ensureLoadingSpinner() -> UIActivityIndicatorView {
        if let loadingSpinner { return loadingSpinner }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = UIColor.white.withAlphaComponent(0.7)
        spinner.hidesWhenStopped = true
        overlayContainer.insertSubview(spinner, aboveSubview: placeholderPanel)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: overlayContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlayContainer.centerYAnchor)
        ])
        loadingSpinner = spinner
        return spinner
    }

    /// Server badge: top-leading, 10pt inset.
    private func ensureSourceBadge() -> SourceBadgeView {
        if let sourceBadge { return sourceBadge }
        let badge = SourceBadgeView(style: .onArtwork)
        let stack = UIStackView(arrangedSubviews: [badge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        overlayContainer.insertSubview(stack, aboveSubview: trailingBadges)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: overlayContainer.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlayContainer.trailingAnchor, constant: -10)
        ])
        sourceBadge = badge
        return badge
    }

    /// Failure icon (centred) and the title under it; shown only when the image load fails or the
    /// source URL is missing.
    private func ensureFailureViews() -> (icon: UIImageView, title: UILabel) {
        if let failureIcon, let failureTitle { return (failureIcon, failureTitle) }
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = UIColor.white.withAlphaComponent(0.3)
        icon.isHidden = true
        overlayContainer.insertSubview(icon, belowSubview: watchedGlyph)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 24, weight: .medium)
        title.textColor = UIColor.white.withAlphaComponent(0.6)
        title.textAlignment = .center
        title.numberOfLines = 4
        title.isHidden = true
        overlayContainer.insertSubview(title, belowSubview: watchedGlyph)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: overlayContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: overlayContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor, constant: -16)
        ])
        failureIcon = icon
        failureTitle = title
        return (icon, title)
    }

    private var failureTitleText: String?
    /// The title showing on the failure card (tests).
    var failureTitleShown: String? {
        guard let failureTitle, !failureTitle.isHidden else { return nil }
        return failureTitle.text
    }

    private var imageLoadTask: Task<Void, Never>?
    private var currentURL: URL?
    /// True once real artwork is showing. `posterView.image` is never nil
    /// (see `blankArtwork`), so it cannot answer this.
    private var hasArtwork = false

    /// Stand-in for missing artwork. TVPosterView drops its focus-growth inset with a nil image,
    /// and keeps the geometry it derived from the stand-in when a cover of the same aspect replaces
    /// it, so a small square stand-in left square covers focusing as a sliver (#504). Tile-sized.
    static let blankArtwork = blank(for: MediaRowMetrics.poster)
    private static let blankMusicArtwork = blank(for: MediaRowMetrics.music)

    static func blank(for tile: MediaRowMetrics.Tile) -> UIImage {
        // Sized in points, stored at 0.1 px a point (26x39 px for a poster): TVPosterView scans the
        // alpha of every image it is given on the main thread, so a full-size stand-in cost a full scan.
        UIGraphicsImageRenderer(size: tile.art, format: .layeredArtwork(scale: 0.1)).image { _ in }
    }

    private var tileBlankArtwork: UIImage { tile.art == MediaRowMetrics.music.art ? Self.blankMusicArtwork : Self.blankArtwork }

    /// The poster corner, drawn into the artwork (`RoundedPoster`).
    private let cornerRadius = RoundedPoster.cornerRadius
    /// The tile the cell shows; the host view is TVUIKit's focused size (`hostSize`).
    private var tile = MediaRowMetrics.poster

    /// Swappable so music tiles render the 1:1 square lockup instead of the
    /// 2:3 poster one. Set per item in `configure(...)`.
    private var posterWidthConstraint: NSLayoutConstraint!
    private var posterHeightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setUp() {
        contentView.clipsToBounds = false
        clipsToBounds = false

        // Stable identifier for focus diagnostics / UI automation.
        accessibilityIdentifier = "hub.poster.cell.9f27c1"

        // No resting drop shadow, matching the Apple TV app.

        posterView.translatesAutoresizingMaskIntoConstraints = false
        posterView.image = Self.blankArtwork
        contentView.addSubview(posterView)

        // Overlay container clipped to the same rounded rect as the poster.
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.isUserInteractionEnabled = false
        overlayContainer.clipsToBounds = true
        overlayContainer.layer.cornerRadius = cornerRadius
        overlayContainer.layer.cornerCurve = .continuous
        contentView.addSubview(overlayContainer)

        // Placeholder (backmost): covers TVPosterView's bare gray while artwork loads.
        placeholderPanel.translatesAutoresizingMaskIntoConstraints = false
        placeholderPanel.isUserInteractionEnabled = false
        placeholderPanel.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        placeholderPanel.layer.cornerRadius = cornerRadius
        placeholderPanel.layer.cornerCurve = .continuous
        placeholderPanel.layer.borderWidth = 1
        placeholderPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        placeholderPanel.isHidden = true
        overlayContainer.addSubview(placeholderPanel)

        // (The spinner, blur band and progress bar are built on first use: see the ensure… functions.)

        // Unwatched count then edition badge: top-trailing, 10pt inset. Hidden badges collapse.
        // The edition badge joins on first use (setEdition), after the count.
        watchedBadge.isHidden = true
        trailingBadges.translatesAutoresizingMaskIntoConstraints = false
        trailingBadges.axis = .vertical
        trailingBadges.alignment = .trailing
        trailingBadges.spacing = 6
        trailingBadges.addArrangedSubview(watchedBadge)
        overlayContainer.addSubview(trailingBadges)

        // (The server badge and the failure icon and title are built on first use.)

        // Watched glyph: bottom-left, same slot as the progress bar / play icon.
        watchedGlyph.isHidden = true
        overlayContainer.addSubview(watchedGlyph)

        posterWidthConstraint = posterView.widthAnchor.constraint(equalToConstant: tile.hostSize.width)
        posterHeightConstraint = posterView.heightAnchor.constraint(equalToConstant: tile.hostSize.height)
        NSLayoutConstraint.activate([
            posterView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            posterView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            posterWidthConstraint,
            posterHeightConstraint,

            // Pin to TVPosterView's IMAGE surface, not its outer frame: the
            // frame reserves room for focus growth, so the resting picture is
            // smaller and an overlay on the outer frame hangs off it.
            overlayContainer.topAnchor.constraint(equalTo: posterView.imageView.topAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: posterView.imageView.bottomAnchor),
            overlayContainer.leadingAnchor.constraint(equalTo: posterView.imageView.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: posterView.imageView.trailingAnchor),

            trailingBadges.topAnchor.constraint(equalTo: overlayContainer.topAnchor, constant: 10),
            trailingBadges.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor, constant: -10),
            trailingBadges.leadingAnchor.constraint(greaterThanOrEqualTo: overlayContainer.leadingAnchor, constant: 10),

            // Glass placeholder fills the image surface.
            placeholderPanel.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            placeholderPanel.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
            placeholderPanel.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            placeholderPanel.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),

            // Watched glyph shares the progress bar's bottom-left anchor.
            watchedGlyph.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor,
                                                  constant: MediaProgressInfoBar.leadingInset),
            watchedGlyph.centerYAnchor.constraint(equalTo: overlayContainer.bottomAnchor,
                                                  constant: -MediaProgressInfoBar.centerFromBottom)
        ])
    }

    // MARK: - Focus zoom sync

    /// The overlay doesn't follow the poster's focus growth, so mirror the tile's
    /// here; the host's own growth is trimmed to the tile's by `focusScale`.
    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let nowFocused = context.nextFocusedView === self
                      || context.nextFocusedView?.isDescendant(of: self) == true
        let artSize = posterView.imageView.bounds.size
        let longSide = max(artSize.width, artSize.height)
        let scale = longSide > 0 ? 1 + tile.growth.height / longSide : 1.1
        barFocusedState = nowFocused
        coordinator.addCoordinatedAnimations({
            self.posterView.transform = nowFocused ? self.tile.focusScale : .identity
            self.progressInfoBar?.setFocused(nowFocused)
            self.overlayContainer.transform = nowFocused
                ? CGAffineTransform(scaleX: scale, y: scale)
                : .identity
        }, completion: { [weak self] in
            guard let self, !nowFocused else { return }
            // TVPosterView's own unfocus sometimes leaves the poster enlarged; enforce the end state.
            self.resetStaleFocusAppearance()
        })
    }

    /// Clears a focused look TVPosterView left behind: its unfocus animation sometimes never runs
    /// (focus left into a presented carousel), stranding the scale and parallax. No-op while focused,
    /// since the completion can fire after focus has returned.
    func resetStaleFocusAppearance() {
        guard !isFocused else { return }
        func clear(_ v: UIView) {
            if !v.transform.isIdentity { v.transform = .identity }
            if !CATransform3DIsIdentity(v.layer.transform) { v.layer.transform = CATransform3DIdentity }
            v.motionEffects.forEach { v.removeMotionEffect($0) }
            v.subviews.forEach(clear)
        }
        clear(posterView)
        overlayContainer.transform = .identity
    }

    // MARK: - Configure

    func configure(item: PlexMetadata) {
        sourceBadge?.text = nil
        setSquare(["artist", "album", "track"].contains(item.type ?? ""))
        let url = posterURL(for: item)
        failureTitleText = item.title
        setEdition(item.editionTitle)
        loadImage(from: url, item: item)
        configureProgressBar(item: item)
        configureWatchedBadge(item: item)
    }

    /// MediaItem path. All artwork URLs are already resolved — no serverURL/token needed.
    func configure(item: MediaItem) {
        sourceBadge?.text = nil
        setSquare(item.isMusic == true)
        // Episodes and seasons show the show's poster, matching the Plex path.
        let url = item.grandparentArtwork?.poster
            ?? (item.kind == .season ? item.parentArtwork?.poster : nil) ?? item.artwork.poster
        failureTitleText = item.title
        setEdition(item.editionTitle)
        loadImage(from: url, failureKind: item.kind)
        configureProgressBar(item: item)
        configureWatchedBadge(item: item)
    }

    /// Names the item's server; call after `configure` (which never adds one).
    func setSourceBadge(_ text: String?) {
        guard let text else { sourceBadge?.text = nil; return }
        ensureSourceBadge().text = text
    }

    /// The badge's text while it shows (tests).
    var sourceBadgeText: String? {
        guard let sourceBadge, !sourceBadge.isHidden else { return nil }
        return sourceBadge.text
    }

    private func setEdition(_ edition: String?) {
        let short = MediaItem.shortEdition(edition)
        if short != nil, editionBadge == nil {
            let badge = SourceBadgeView(style: .onArtwork)
            trailingBadges.addArrangedSubview(badge)   // after the unwatched count
            editionBadge = badge
        }
        editionBadge?.text = short
    }

    /// The edition badge's text while it shows (tests).
    var editionBadgeText: String? {
        guard let editionBadge, !editionBadge.isHidden else { return nil }
        return editionBadge.text
    }

    /// Music tiles are 1:1 square; everything else keeps the 2:3 poster ratio.
    private func setSquare(_ square: Bool) {
        tile = square ? MediaRowMetrics.music : MediaRowMetrics.poster
        let host = tile.hostSize
        let shapeChanged = posterHeightConstraint.constant != host.height
        if shapeChanged {
            posterWidthConstraint.constant = host.width
            posterHeightConstraint.constant = host.height
        }
        // Only when the aspect changes (#504): without art the image is already this aspect's
        // stand-in. Each `TVPosterView.image` set scans the image's alpha.
        if !hasArtwork, shapeChanged { posterView.image = tileBlankArtwork }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetContent()
        contentView.setReorderWiggle(false)
    }

    /// Blank glass card for a library-grid slot whose page has not loaded.
    /// A slot flips to a real item through `reconfigureItems` on the same
    /// cell, and back to this on a sort reset, so clear the previous
    /// occupant here rather than assume `prepareForReuse` ran.
    func configurePlaceholder() {
        resetContent()
        placeholderPanel.isHidden = false
    }

    private func resetContent() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        cancelSpinnerDelay()
        loadingSpinner?.stopAnimating()
        placeholderPanel.isHidden = true
        currentURL = nil
        clearArtwork()
        hideProgressBar()
        watchedBadge.isHidden = true
        sourceBadge?.text = nil
        editionBadge?.text = nil
        watchedGlyph.isHidden = true
        failureIcon?.isHidden = true
        failureIcon?.image = nil
        failureTitle?.isHidden = true
        failureTitle?.text = nil
        // A recycled cell must not inherit a prior occupant's stranded focus
        // (enlarged) appearance — clear any leftover scale transform.
        resetStaleFocusAppearance()
    }

    // MARK: - Image load

    /// PlexMetadata path: resolves the failure icon via the full Plex type
    /// switch (including music types) then delegates to the shared loader.
    private func loadImage(from url: URL?, item: PlexMetadata) {
        loadImage(from: url, failureIcon: failureIconImage(for: item))
    }

    /// MediaItem path: resolves the failure icon via MediaKind then delegates.
    private func loadImage(from url: URL?, failureKind: MediaKind) {
        loadImage(from: url, failureIcon: failureIconImage(for: failureKind))
    }

    private func loadImage(from url: URL?, failureIcon: UIImage?) {
        imageLoadTask?.cancel()
        guard let url else {
            clearArtwork()
            currentURL = nil
            showPlaceholderFailure(failureIcon)
            return
        }
        if currentURL == url, hasArtwork {
            hidePlaceholder()
            return
        }
        currentURL = url
        // Memory hit paints in this pass, so a tile realized for a carousel
        // exit has artwork to fly to.
        let shape = RoundedPoster.Shape(tile: tile, scale: traitCollection.displayScale)
        if let cached = RoundedPoster.cached(for: url, shape: shape) {
            posterView.image = cached
            hasArtwork = true
            hidePlaceholder()
            return
        }
        // Glass panel up immediately (covers the bare gray); the load now
        // retries transient failures internally, so the spinner simply rides
        // the single await until the artwork resolves or genuinely fails.
        showPlaceholderLoading()
        let key = url.absoluteString as AnyHashable
        imageLoadTask = Task { [weak self] in
            let image: UIImage? = await Perf.interval(.imageDecode, key: key) {
                await RoundedPoster.image(for: url, shape: shape)
            }
            await MainActor.run {
                guard let self, self.currentURL == url else { return }
                if let image {
                    self.posterView.image = image
                    self.hasArtwork = true
                    self.hidePlaceholder()
                } else {
                    self.clearArtwork()
                    self.showPlaceholderFailure(failureIcon)
                }
            }
        }
    }

    private func clearArtwork() {
        posterView.image = tileBlankArtwork
        hasArtwork = false
    }

    /// Glass panel + (delayed) spinner while the artwork loads/retries.
    private func showPlaceholderLoading() {
        placeholderPanel.isHidden = false
        failureIcon?.isHidden = true
        failureTitle?.isHidden = true
        // Delay the spinner so a fast cache hit doesn't flash it on scroll.
        cancelSpinnerDelay()
        spinnerDelayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            if !self.placeholderPanel.isHidden, !self.hasArtwork {
                self.ensureLoadingSpinner().startAnimating()
            }
        }
    }

    /// Glass panel + faint type icon after a genuine (post-retry) failure.
    private func showPlaceholderFailure(_ icon: UIImage?) {
        cancelSpinnerDelay()
        loadingSpinner?.stopAnimating()
        placeholderPanel.isHidden = false
        let failure = ensureFailureViews()
        failure.icon.image = icon
        failure.icon.isHidden = false
        failure.title.text = failureTitleText
        failure.title.isHidden = (failureTitleText ?? "").isEmpty
    }

    /// Artwork resolved — tear the placeholder down.
    private func hidePlaceholder() {
        cancelSpinnerDelay()
        loadingSpinner?.stopAnimating()
        placeholderPanel.isHidden = true
        failureIcon?.isHidden = true
        failureTitle?.isHidden = true
    }

    private func cancelSpinnerDelay() {
        spinnerDelayTask?.cancel()
        spinnerDelayTask = nil
    }

    /// Failure icon for every Plex type, music included.
    private func failureIconImage(for item: PlexMetadata) -> UIImage? {
        let name: String
        switch item.type {
        case "movie":   name = "film"
        case "show":    name = "tv"
        case "season":  name = "number.square"
        case "episode": name = "play.rectangle"
        case "artist":  name = "music.mic"
        case "album":   name = "square.stack"
        case "track":   name = "music.note"
        default:        name = "photo"
        }
        return TileSymbolIcon.image(name)
    }

    /// MediaItem failure icon — maps MediaKind to a system image name.
    private func failureIconImage(for kind: MediaKind) -> UIImage? {
        let name: String
        switch kind {
        case .movie:   name = "film"
        case .show:    name = "tv"
        case .season:  name = "number.square"
        case .episode: name = "play.rectangle"
        case .person:  name = "person"
        default:       name = "photo"
        }
        return TileSymbolIcon.image(name)
    }

    private func posterURL(for item: PlexMetadata) -> URL? {
        guard let serverURL = PlexAuthManager.shared.selectedServerURL,
              let token = PlexAuthManager.shared.selectedServerToken
        else { return nil }
        // Episodes and seasons show the show's poster, so Recently Added rows read as shows.
        let path: String?
        if item.type == "episode" {
            path = item.grandparentThumb ?? item.parentThumb ?? item.thumb
        } else if item.type == "season" {
            path = item.parentThumb ?? item.thumb
        } else {
            path = item.thumb
        }
        guard let path else { return nil }
        return URL(string: "\(serverURL)\(path)?X-Plex-Token=\(token)")
    }

    // MARK: - In-progress bar (CW-style)

    private func configureProgressBar(item: PlexMetadata) {
        // Show the CW-style info bar only when an item is in progress
        // (0 < watchProgress < 1). Audio items (album / artist / track)
        // suppress progress entirely.
        if isAudioItem(item) {
            hideProgressBar()
            return
        }
        if let progress = item.watchProgress, progress > 0, progress < 1 {
            let bar = ensureProgressInfoBar()
            bar.isHidden = false; ensureBottomInfoBlur().isHidden = false
            bar.configure(item: item)
        } else {
            hideProgressBar()
        }
    }

    private func isAudioItem(_ item: PlexMetadata) -> Bool {
        switch item.type {
        case "album", "artist", "track": return true
        default: return false
        }
    }

    // MARK: - Watched badge

    private func configureWatchedBadge(item: PlexMetadata) {
        // Ladder:
        //  1. Audio items: nothing.
        //  2. TV show with leafCount > 0 and unwatched > 0: blue count pill (top-right).
        //  3. Fully watched (show / movie / episode): rewatch glyph (bottom-left).
        if isAudioItem(item) {
            hideWatchedIndicators()
            return
        }
        if item.type == "show", let leafCount = item.leafCount, leafCount > 0 {
            let viewed = item.viewedLeafCount ?? 0
            let unwatched = leafCount - viewed
            if unwatched > 0 {
                showUnwatchedCount(unwatched)
                return
            }
            if viewed >= leafCount {
                showWatchedGlyph()
                return
            }
        }
        if isFullyWatched(item) {
            showWatchedGlyph()
            return
        }
        hideWatchedIndicators()
    }

    private func isFullyWatched(_ item: PlexMetadata) -> Bool {
        guard let viewCount = item.viewCount, viewCount > 0 else { return false }
        if let progress = item.watchProgress, progress > 0, progress < 1 {
            return false
        }
        if let viewOffset = item.viewOffset, let duration = item.duration {
            let remaining = duration - viewOffset
            if remaining > 60_000 { return false }   // >1 minute left
        }
        return true
    }

    // MARK: - MediaItem progress bar

    private func configureProgressBar(item: MediaItem) {
        // MediaItem has no audio kind equivalent; only person/collection/playlist are
        // "no progress" -- treat anything without a runtime as suppressed.
        guard item.kind != .person, item.kind != .collection, item.kind != .playlist else {
            hideProgressBar()
            return
        }
        let offset = item.userState.viewOffset
        let fraction: Double
        if let rt = item.runtime, rt > 0 {
            fraction = offset / rt
        } else {
            fraction = 0
        }
        if fraction > 0 && fraction < 1 {
            let bar = ensureProgressInfoBar()
            bar.isHidden = false; ensureBottomInfoBlur().isHidden = false
            bar.configure(item: item)
        } else {
            hideProgressBar()
        }
    }

    // MARK: - MediaItem watched badge

    private func configureWatchedBadge(item: MediaItem) {
        // Watched is a video concept only. Music (artist/album/track map to
        // .unknown), people, and collections never get a watched indicator.
        switch item.kind {
        case .movie, .show, .season, .episode: break
        default:
            hideWatchedIndicators()
            return
        }
        // Shows: unwatched count pill (top-right), or fully-watched glyph.
        if item.kind == .show, let cp = item.childProgress, cp.total > 0 {
            let unwatched = cp.total - cp.played
            if unwatched > 0 {
                showUnwatchedCount(unwatched)
                return
            }
            showWatchedGlyph()   // all episodes played
            return
        }
        // Movies/episodes: the glyph shows only when watched AND not in progress.
        // An item with an active resume point shows the progress bar instead —
        // Plex shows one or the other, never both.
        if isFullyWatched(item) {
            showWatchedGlyph()
            return
        }
        hideWatchedIndicators()
    }

    /// MediaItem twin of the PlexMetadata `isFullyWatched`. Uses the same
    /// `0 < fraction < 1` in-progress test as `configureProgressBar(item:)`, so
    /// the watched glyph and the progress bar are mutually exclusive.
    private func isFullyWatched(_ item: MediaItem) -> Bool {
        guard item.userState.isPlayed else { return false }
        if let rt = item.runtime, rt > 0 {
            let fraction = item.userState.viewOffset / rt
            if fraction > 0, fraction < 1 { return false }   // in progress → bar wins
        }
        return true
    }

    // MARK: - Watched indicators

    /// Fully watched → Apple-style rewatch glyph, bottom-left (same slot as the
    /// play icon + progress bar). The top-right pill is for *unwatched* shows
    /// only, so it's hidden here. No legibility band — the glyph relies on its
    /// own soft shadow.
    private func showWatchedGlyph() {
        watchedGlyph.isHidden = false
        watchedBadge.isHidden = true
    }

    /// Unwatched TV show → blue count pill, top-right.
    private func showUnwatchedCount(_ count: Int) {
        watchedBadge.setStyle(.unwatchedCount(count))
        watchedBadge.isHidden = false
        watchedGlyph.isHidden = true
    }

    private func hideWatchedIndicators() {
        watchedBadge.isHidden = true
        watchedGlyph.isHidden = true
    }
}

// MARK: - Unwatched-count badge

/// Top-trailing blue pill with an in-progress show's unwatched-episode count.
@MainActor
final class PosterWatchedBadge: UIView {
    enum Style {
        case unwatchedCount(Int)
    }

    private let pillLabel = UILabel()
    private let pillBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // Blue capsule with N text.
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.backgroundColor = .systemBlue
        pillBackground.layer.cornerRadius = 10
        pillBackground.layer.cornerCurve = .continuous
        pillBackground.layer.shadowColor = UIColor.black.cgColor
        pillBackground.layer.shadowOpacity = 0.3
        pillBackground.layer.shadowRadius = 4
        pillBackground.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(pillBackground)

        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillLabel.font = .systemFont(ofSize: 12, weight: .bold)
        pillLabel.textColor = .white
        pillBackground.addSubview(pillLabel)

        NSLayoutConstraint.activate([
            pillLabel.topAnchor.constraint(equalTo: pillBackground.topAnchor, constant: 4),
            pillLabel.bottomAnchor.constraint(equalTo: pillBackground.bottomAnchor, constant: -4),
            pillLabel.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 8),
            pillLabel.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -8),

            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setStyle(_ style: Style) {
        switch style {
        case .unwatchedCount(let count):
            pillLabel.text = "\(count)"
        }
    }
}

extension PosterCell: PreviewSourceTile {
    var previewArtworkView: UIView { overlayContainer }
    var previewCornerRadius: CGFloat { cornerRadius }
    var previewArtworkLoaded: Bool { hasArtwork }
}

/// Placeholder and failure symbols, built once per name. Each tile configure used to rebuild its
/// symbol image even on an artwork cache hit, inside row-scroll commits.
@MainActor
enum TileSymbolIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let image = UIImage(systemName: name)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 32, weight: .light))
        if let image { cache[name] = image }
        return image
    }
}
