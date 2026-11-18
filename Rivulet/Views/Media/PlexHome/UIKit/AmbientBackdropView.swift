// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// The page's ambient color wash: one artwork stretched full screen (frosted over on Settings and
// Photos), plus a vignette that keeps the lower half dark. It follows the hero with a slow 0.6s
// crossfade, since a hard cut reads as the whole background flickering.

import UIKit

@MainActor
final class AmbientBackdropView: UIView {

    private let currentImageView = UIImageView()
    private let previousImageView = UIImageView()
    private let vignette = VignetteView()
    private var loadTask: Task<Void, Never>?
    private var clearPreviousTask: Task<Void, Never>?
    private var currentURL: URL?
    /// The URL of the picture actually on screen (currentURL may still be loading).
    private var appliedURL: URL?
    /// Called once when the requested picture is in place (see setAmbient).
    private var onApplied: (() -> Void)?

    /// True once any artwork has been shown. The no-hero fallback uses this to
    /// avoid overwriting a wash the hero already established.
    var hasAmbient: Bool { currentURL != nil }

    /// Music's Now Playing shows the wash at full brightness, as Apple Music does,
    /// and reduces the artwork to its colours first.
    var showsVignette = true {
        didSet { vignette.isHidden = !showsVignette }
    }
    var imageTransform: (@Sendable (UIImage) -> UIImage)?

    /// The artwork any page washed last; Settings borrows it for its own background.
    static private(set) var lastURL: URL?

    private let crossfadeDuration: TimeInterval = 0.6
    private let imageAlpha: CGFloat = 0.85

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear

        for iv in [previousImageView, currentImageView] {
            iv.contentMode = .scaleAspectFill
            iv.alpha = 0   // fades in when the artwork lands
            iv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iv)
            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: topAnchor),
                iv.bottomAnchor.constraint(equalTo: bottomAnchor),
                iv.leadingAnchor.constraint(equalTo: leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        vignette.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vignette)

        NSLayoutConstraint.activate([
            vignette.topAnchor.constraint(equalTo: topAnchor),
            vignette.bottomAnchor.constraint(equalTo: bottomAnchor),
            vignette.leadingAnchor.constraint(equalTo: leadingAnchor),
            vignette.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        loadTask?.cancel()
        clearPreviousTask?.cancel()
    }

    /// Set the ambient artwork. Crossfades from whatever is on screen. A nil URL
    /// or a repeat of the current URL is a no-op — the existing wash stays put
    /// rather than flashing to black between hero items that lack artwork.
    ///
    /// `crossfade: false` swaps the picture with no fade, for a wash that is hidden (alpha 0)
    /// and is about to be faded in by its owner. `onApplied` runs once the picture is in place:
    /// straight away for a picture already showing, never if it fails to load.
    func setAmbient(url: URL?, crossfade: Bool = true, onApplied: (() -> Void)? = nil) {
        guard let url else { return }
        guard url != currentURL else {
            if appliedURL == url { onApplied?() } else if onApplied != nil { self.onApplied = onApplied }
            return
        }
        currentURL = url
        Self.lastURL = url
        self.onApplied = onApplied
        loadTask?.cancel()
        clearPreviousTask?.cancel()

        let oldImage = crossfade ? currentImageView.image : nil
        loadTask = Task { [weak self] in
            var image = await ImageCacheManager.shared.image(for: url)
            // Off the main actor: Now Playing's transform resamples and redraws the cover.
            if let source = image, let transform = self?.imageTransform {
                image = await Task.detached { transform(source) }.value
            }
            guard let self, !Task.isCancelled, let image, self.currentURL == url else { return }
            self.appliedURL = url
            if crossfade {
                self.applyImage(image, replacing: oldImage)
            } else {
                self.showImage(image)
            }
            let applied = self.onApplied
            self.onApplied = nil
            applied?()
        }
    }

    /// Puts a picture in place with no fade of its own.
    private func showImage(_ image: UIImage) {
        previousImageView.layer.removeAllAnimations()
        currentImageView.layer.removeAllAnimations()
        previousImageView.image = nil
        previousImageView.alpha = 0
        currentImageView.image = image
        currentImageView.alpha = imageAlpha
    }

    private func applyImage(_ image: UIImage, replacing oldImage: UIImage?) {
        if let oldImage {
            previousImageView.image = oldImage
            previousImageView.alpha = imageAlpha
        } else {
            previousImageView.image = nil
            previousImageView.alpha = 0
        }
        currentImageView.image = image
        currentImageView.alpha = 0

        UIView.animate(withDuration: crossfadeDuration, delay: 0, options: [.curveEaseInOut]) {
            self.currentImageView.alpha = self.imageAlpha
            self.previousImageView.alpha = 0
        }

        guard oldImage != nil else { return }
        // Hold the outgoing image until the fade has fully settled, then drop it.
        let totalNs = UInt64(crossfadeDuration * 1_000_000_000) + 50_000_000
        clearPreviousTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: totalNs)
            guard let self, !Task.isCancelled else { return }
            self.previousImageView.image = nil
        }
    }

    /// Vertical scrim over the wash: brightest up top, dark behind the
    /// shelves — matches both reference shots. Plain gradient-backed UIView
    /// (layerClass) so it lays out via Auto Layout like everything else.
    private final class VignetteView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            let gradient = layer as! CAGradientLayer
            gradient.colors = [
                UIColor.black.withAlphaComponent(0.10).cgColor,
                UIColor.black.withAlphaComponent(0.25).cgColor,
                UIColor.black.withAlphaComponent(0.50).cgColor
            ]
            gradient.locations = [0, 0.55, 1]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    }
}

/// When Home's wash (the full-screen picture behind the rows) shows, and the numbers to tune it.
/// Pure, so it can be unit tested.
enum HomeWash {
    /// Seconds focus must rest on one tile before its wide picture fades in.
    static let holdDelay: TimeInterval = 2.0
    /// Seconds the page must have been still before a picture may fade in.
    static let settleDelay: TimeInterval = 0.3
    /// Fade-in time of a held tile's picture, and fade-out time when focus moves on.
    static let revealDuration: TimeInterval = 0.6
    static let concealDuration: TimeInterval = 0.25
    /// How strongly a held tile's picture shows: 1 is the same as behind the hero, lower is darker.
    static let revealAlpha: CGFloat = 1.0
    /// The page colour under the wash: what a scrolled-down page rests on.
    static let pageBaseColor: UIColor = .black

    /// The wash's alpha. `showcase` is 1 with the hero at rest and 0 once it has scrolled away;
    /// a page with no hero rests dark. A revealed picture shows wherever the page is.
    static func alpha(showcase: CGFloat, hasHero: Bool, revealed: Bool) -> CGFloat {
        let hero = hasHero ? min(1, max(0, showcase)) : 0
        return revealed ? max(hero, revealAlpha) : hero
    }

    /// Seconds still to wait before a hold may reveal: the hold itself, counted from when focus
    /// landed, and a short still period after the page last moved. Zero or less means reveal now.
    static func holdRemaining(now: TimeInterval, armedAt: TimeInterval, lastMotion: TimeInterval) -> TimeInterval {
        max(holdDelay - (now - armedAt), settleDelay - (now - lastMotion))
    }
}
