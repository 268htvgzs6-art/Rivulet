// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Subtitle Font and Subtitle Brightness, layered on top of the system caption
// style (CaptionAppearance). The font applies to plain captions only; brightness
// dims the text colour (not its opacity) for plain, libass and picture captions.

import CoreGraphics
import CoreText
import Foundation
import os

nonisolated enum SubtitleAppearance {

    // MARK: Keys

    /// Family name as CoreText reports it ("Geeza Pro", ".SF Arabic"). Empty or absent = System.
    static let fontFamilyKey = "subtitleFontFamily"
    /// Double in 0.4...1.0; absent = 1.0.
    static let brightnessKey = "subtitleBrightness"

    /// Posts the caption-change notification, so every caption surface that
    /// already restyles on a system caption change picks either setting up.
    static func notifyChanged() {
        NotificationCenter.default.post(name: CaptionAppearance.changedNotification, object: nil)
    }

    // MARK: Brightness

    static let minimumBrightness = 0.4
    static let brightnessOptions: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4]

    static func clampBrightness(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumBrightness), 1)
    }

    static var brightness: Double {
        get {
            guard let stored = UserDefaults.standard.object(forKey: brightnessKey) as? Double else { return 1 }
            return clampBrightness(stored)
        }
        set {
            UserDefaults.standard.set(clampBrightness(newValue), forKey: brightnessKey)
            notifyChanged()
        }
    }

    /// The option after `current`, wrapping 40% back to 100% (the Settings row).
    static func nextBrightness(after current: Double) -> Double {
        let index = brightnessOptions.firstIndex { abs($0 - current) < 0.001 } ?? 0
        return brightnessOptions[(index + 1) % brightnessOptions.count]
    }

    /// The player's stepper: Right (+1) is 10% brighter, Left (-1) 10% dimmer,
    /// stopping at 100% and 40%.
    static func steppedBrightness(_ current: Double, by step: Int) -> Double {
        let index = brightnessOptions.firstIndex { abs($0 - current) < 0.001 }
            ?? brightnessOptions.indices.min { abs(brightnessOptions[$0] - current) < abs(brightnessOptions[$1] - current) }
            ?? 0
        // The options run 100% down to 40%, so brighter is a lower index.
        let next = min(max(index - step, 0), brightnessOptions.count - 1)
        return brightnessOptions[next]
    }

    static func brightnessLabel(_ value: Double) -> String {
        "\(Int((clampBrightness(value) * 100).rounded()))%"
    }

    /// Multiplies a colour's RGB by `factor` and keeps its alpha: white at 0.4
    /// becomes opaque 40% grey, not 40%-transparent white.
    static func dim(_ color: CGColor, by factor: Double) -> CGColor {
        let f = CGFloat(clampBrightness(factor))
        guard f < 1 else { return color }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 4
        else { return color }
        return CGColor(srgbRed: c[0] * f, green: c[1] * f, blue: c[2] * f, alpha: c[3])
    }

    /// Picture subtitles (PGS, VobSub): the same RGB scaling, applied to the drawn pixels only
    /// (black over them with source-atop), alpha unchanged. nil if drawing fails.
    static func dimmedImage(_ image: CGImage, by factor: Double) -> CGImage? {
        let f = clampBrightness(factor)
        guard f < 1,
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1 - f))
        ctx.fill(rect)
        return ctx.makeImage()
    }

    /// Same as `dim` for a libass `0xRRGGBBTT` colour (TT is transparency, kept).
    static func dimASSColor(_ color: UInt32, by factor: Double) -> UInt32 {
        let f = clampBrightness(factor)
        guard f < 1 else { return color }
        func scale(_ shift: UInt32) -> UInt32 {
            UInt32((Double((color >> shift) & 0xFF) * f).rounded()) << shift
        }
        return scale(24) | scale(16) | scale(8) | (color & 0xFF)
    }

    // MARK: Font

    /// Arabic families Apple ships on some OS, each with the spellings it may go by.
    /// Filtered at runtime against what this device can load.
    static let arabicFontCandidates: [[String]] = [
        ["Geeza Pro"], ["SF Arabic"], ["SF Arabic Rounded"],
        ["Al Nile"], ["Al Tarikh"], ["Al Bayan", "AlBayan"], ["Baghdad"], ["Damascus"],
        ["DecoType Naskh"], ["Diwan Kufi"], ["Diwan Thuluth"], ["Farah"],
        ["Kufi Standard GK", "KufiStandardGK"], ["Mishafi"], ["Mishafi Gold"], ["Muna"],
        ["Nadeem"], ["Sana"], ["Waseem"],
        ["Noto Naskh Arabic"], ["Noto Kufi Arabic"], ["Noto Sans Arabic"],
        ["Noto Nastaliq Urdu"], ["DecoType Nastaleeq Urdu"]
    ]

    static var fontFamily: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: fontFamilyKey) ?? ""
            return stored.isEmpty ? nil : stored
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: fontFamilyKey)
            notifyChanged()
        }
    }

    /// Case, spaces and the leading "." of hidden system families do not distinguish a family.
    static func normalized(_ family: String) -> String {
        var name = family.lowercased().replacingOccurrences(of: " ", with: "")
        while name.hasPrefix(".") { name.removeFirst() }
        return name
    }

    static func displayName(_ family: String) -> String {
        var name = family
        while name.hasPrefix(".") { name.removeFirst() }
        return name
    }

    /// The family CoreText actually loads for `name`, or nil when it falls back to another.
    static func loadedFamily(_ name: String) -> String? {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: name] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let family = CTFontCopyFamilyName(font) as String
        return normalized(family) == normalized(name) ? family : nil
    }

    /// The stored family, or nil (System) when unset or not loadable here.
    /// `load` is injectable for tests.
    static func resolvedFamily(_ stored: String?, load: (String) -> String? = loadedFamily) -> String? {
        guard let stored, !stored.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let family = load(stored) { return family }
        // Stored as shown ("SF Arabic") but installed hidden (".SF Arabic"), or the reverse.
        let alternate = stored.hasPrefix(".") ? displayName(stored) : "." + stored
        return load(alternate)
    }

    /// The Arabic families this device can load, candidates first in list order,
    /// then any other visible family that covers Arabic. Computed once.
    static let availableArabicFamilies: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ family: String) {
            guard seen.insert(normalized(family)).inserted else { return }
            result.append(family)
        }
        for spellings in arabicFontCandidates {
            if let family = spellings.lazy.compactMap({ resolvedFamily($0) }).first { add(family) }
        }
        let visible = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        for family in visible.sorted() where !seen.contains(normalized(family)) {
            let font = CTFontCreateWithFontDescriptor(
                CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary), 12, nil)
            let languages = (CTFontCopySupportedLanguages(font) as? [String]) ?? []
            if languages.contains("ar") { add(family) }
        }
        return result
    }()

    /// A descriptor for the chosen family at medium weight when it has one near
    /// it, else its regular face. nil = use the system caption font.
    static func fontDescriptor(forFamily stored: String?) -> CTFontDescriptor? {
        guard let family = resolvedFamily(stored) else { return nil }
        let medium = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]
        ] as CFDictionary)
        var font = CTFontCreateWithFontDescriptor(medium, 12, nil)
        let traits = CTFontCopyTraits(font) as NSDictionary
        if let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue, weight > 0.3 {
            // Nearest to medium was a bold face; the regular one reads better.
            font = CTFontCreateWithFontDescriptor(
                CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary), 12, nil)
        }
        guard normalized(CTFontCopyFamilyName(font) as String) == normalized(family) else { return nil }
        return CTFontCopyFontDescriptor(font)
    }

    /// Selection by family; nil is System. Matches the stored name, so a downloadable font that
    /// is still on its way shows as chosen.
    static func isFontSelected(_ family: String?) -> Bool {
        guard let family else { return fontFamily == nil }
        return fontFamily.map(normalized) == normalized(family)
    }

    /// The Subtitle Font value, in Settings and in the player's Font row: a stored family that
    /// does not load here yet shows its download state.
    static var fontValueLabel: String {
        guard let stored = fontFamily else { return String(localized: "System") }
        if let family = resolvedFamily(stored) { return displayName(family) }
        return fontLabel(FontEntry(family: stored, availability: .downloadable), state: fontDownloadState(stored))
    }

    /// At launch, off the main thread: lists the installed Arabic families once, so the first
    /// Settings or player font list does not wait for the scan, and re-activates a downloaded
    /// font chosen on an earlier launch (a downloaded font is not loaded into a new process until
    /// it is matched again, and its request needs no catalog). The downloadable catalog is read
    /// only when a font list first opens.
    static func prepareFontsAtLaunch() {
        DispatchQueue.global(qos: .utility).async {
            _ = availableArabicFamilies
            if let stored = fontFamily, resolvedFamily(stored) == nil { downloadFont(stored) }
        }
    }
}

// MARK: - Apple-hosted downloadable fonts

// tvOS ships only a handful of Arabic families (Geeza Pro, SF Arabic, SF Arabic Rounded and two
// Urdu Nastaliq faces). The rest of Apple's Arabic families are downloadable system fonts: CoreText
// fetches them from Apple on request (CTFontDescriptorMatchFontDescriptorsWithProgressHandler) and
// the OS keeps the files. The catalog query may be slow or answer nothing, so nothing waits on it:
// the list shows Apple's families until it answers, and a download that makes no progress times out.
// Nothing is bundled, and nothing is stored beyond the chosen family name.
nonisolated extension SubtitleAppearance {

    enum FontAvailability: Equatable, Sendable { case installed, downloadable }

    struct FontEntry: Equatable, Sendable {
        let family: String
        let availability: FontAvailability
    }

    enum FontDownloadState: Equatable, Sendable { case idle, waiting, downloading(Int), failed }

    /// Posted on the main queue when the downloadable list loads or a download moves on.
    static let fontCatalogDidChange = Notification.Name("SubtitleAppearance.fontCatalogDidChange")

    /// Apple's Arabic families that are not on Apple TV but are offered as downloadable system
    /// fonts on Apple's other platforms. Listed even when the catalog query confirms none of them;
    /// a failed download hides the unconfirmed ones for the session. Each is spelled the way its
    /// font file and the catalog spell it ("KufiStandardGK", not "Kufi Standard GK"): a pick made
    /// before the catalog answers is saved as written, and CoreText loads only that spelling.
    static let appleDownloadableArabicFamilies = [
        "Al Bayan", "Al Nile", "Al Tarikh", "Baghdad", "Damascus", "DecoType Naskh", "Diwan Kufi",
        "Diwan Thuluth", "Farah", "KufiStandardGK", "Mishafi", "Mishafi Gold", "Muna", "Nadeem",
        "Sana", "Waseem"
    ]

    /// The PostScript names of each family's faces, as Apple's font files name them. A download
    /// asks for these by name when the catalog lists no faces for the family.
    static let appleDownloadableArabicFaces: [String: [String]] = [
        "Al Bayan": ["AlBayan", "AlBayan-Bold"],
        "Al Nile": ["AlNile", "AlNile-Bold"],
        "Al Tarikh": ["AlTarikh"],
        "Baghdad": ["Baghdad"],
        "Damascus": ["Damascus", "DamascusLight", "DamascusMedium", "DamascusSemiBold", "DamascusBold"],
        "DecoType Naskh": ["DecoTypeNaskh"],
        "Diwan Kufi": ["DiwanKufi"],
        "Diwan Thuluth": ["DiwanThuluth"],
        "Farah": ["Farah"],
        "KufiStandardGK": ["KufiStandardGK"],
        "Mishafi": ["DiwanMishafi"],
        "Mishafi Gold": ["DiwanMishafiGold"],
        "Muna": ["Muna", "MunaBold", "MunaBlack"],
        "Nadeem": ["Nadeem"],
        "Sana": ["Sana"],
        "Waseem": ["Waseem", "WaseemLight"]
    ]

    /// Seconds a download may go without progress (and without finishing) before it counts as
    /// failed. Each window with progress re-arms the next.
    static let fontDownloadTimeout: TimeInterval = 45

    // MARK: Pure list logic

    /// Installed families first in their order, then downloadable ones that are not installed;
    /// one entry per family (case, spaces and a leading "." do not distinguish one).
    static func fontEntries(installed: [String], downloadable: [String]) -> [FontEntry] {
        var seen = Set<String>()
        var result: [FontEntry] = []
        for family in installed where seen.insert(normalized(family)).inserted {
            result.append(FontEntry(family: family, availability: .installed))
        }
        for family in downloadable where seen.insert(normalized(family)).inserted {
            result.append(FontEntry(family: family, availability: .downloadable))
        }
        return result
    }

    /// Apple's downloadable families that are not installed here, in list order.
    static func fallbackDownloadableFamilies(installed: [String]) -> [String] {
        let local = Set(installed.map(normalized))
        return appleDownloadableArabicFamilies.filter { !local.contains(normalized($0)) }
    }

    /// The downloadable part of the picker. Until the catalog has loaded (or if it never does)
    /// that is every Apple family not installed, so the list never shrinks to the installed ones;
    /// once loaded, the catalog's families plus the unconfirmed Apple ones. After a failed
    /// download of an unconfirmed family, only catalog-confirmed families stay.
    static func downloadableFamilies(installed: [String], catalogLoaded: Bool, catalogFamilies: [String],
                                     unconfirmed: [String], unconfirmedFailed: Bool) -> [String] {
        guard catalogLoaded else { return unconfirmedFailed ? [] : fallbackDownloadableFamilies(installed: installed) }
        return catalogFamilies + (unconfirmedFailed ? [] : unconfirmed)
    }

    /// What a download asks CoreText for: the catalog's faces when it listed some, otherwise the
    /// family's known PostScript names plus a family-name descriptor for each spelling.
    static func downloadRequest(for family: String, catalogFaces: [String]) -> (postScriptNames: [String], families: [String]) {
        guard catalogFaces.isEmpty else { return (catalogFaces, []) }
        let key = normalized(family)
        let names = appleDownloadableArabicFaces.first { normalized($0.key) == key }?.value ?? []
        var families = [family]
        for spelling in arabicFontCandidates.first(where: { $0.contains { normalized($0) == key } }) ?? []
        where !families.contains(spelling) {
            families.append(spelling)
        }
        return (names, families)
    }

    /// A picker row's text: an installed font by name, a downloadable one with its state.
    static func fontLabel(_ entry: FontEntry, state: FontDownloadState) -> String {
        let name = displayName(entry.family)
        guard entry.availability == .downloadable else { return name }
        switch state {
        case .idle: return String(localized: "\(name) (Download)")
        case .waiting: return String(localized: "\(name) (Waiting…)")
        case .downloading(let percent): return String(localized: "\(name) (Downloading \(percent)%)")
        case .failed: return String(localized: "\(name) (Unavailable)")
        }
    }

    // MARK: State

    private struct FontCatalogState: Sendable {
        /// Set when the one catalog read begins (it runs once per process).
        var catalogQueryStarted = false
        var catalogLoaded = false
        /// Arabic families the OS catalog offers for download (not installed).
        var catalogFamilies: [String] = []
        /// normalized family -> the PostScript names of its downloadable faces.
        var catalogFaces: [String: [String]] = [:]
        /// Apple families the catalog did not confirm, listed on trust.
        var unconfirmed: [String] = []
        var unconfirmedFailed = false
        /// Families downloaded and activated in this process.
        var activated: [String] = []
        var states: [String: FontDownloadState] = [:]
        /// normalized family -> its running download attempt. A callback from any other
        /// attempt (timed out, finished, superseded) is ignored.
        var attempts: [String: Int] = [:]
        var nextAttempt = 0
        /// normalized family -> the running attempt reported progress since the watchdog last looked.
        var progressed: [String: Bool] = [:]
    }

    private static let catalogState = OSAllocatedUnfairLock(initialState: FontCatalogState())

    static func fontDownloadState(_ family: String) -> FontDownloadState {
        catalogState.withLock { $0.states[normalized(family)] } ?? .idle
    }

    /// The picker list (Settings and the player): installed Arabic families, then downloadable ones.
    /// A stored choice that is neither stays listed so its checkmark shows. Until the catalog has
    /// been read (`startFontCatalog`), the downloadable part is Apple's families.
    static func fontPickerEntries() -> [FontEntry] {
        let state = catalogState.withLock { $0 }
        // The order never changes under an open list: a font downloaded in this process stays
        // where it was (only its "(Download)" goes), and the downloadable ones keep Apple's
        // order whether or not the catalog has answered yet.
        let installed = availableArabicFamilies
        var downloadable = downloadableFamilies(
            installed: installed, catalogLoaded: state.catalogLoaded, catalogFamilies: state.catalogFamilies,
            unconfirmed: state.unconfirmed, unconfirmedFailed: state.unconfirmedFailed)
        downloadable += state.activated
        if let stored = fontFamily, resolvedFamily(stored) == nil { downloadable.append(stored) }
        let activated = Set(state.activated.map(normalized))
        return fontEntries(installed: installed, downloadable: stableDownloadOrder(downloadable)).map { entry in
            activated.contains(normalized(entry.family)) ? FontEntry(family: entry.family, availability: .installed) : entry
        }
    }

    /// Apple's families in their listed order, then any others by name (duplicates are left for
    /// `fontEntries` to drop).
    static func stableDownloadOrder(_ families: [String]) -> [String] {
        let rank = Dictionary(appleDownloadableArabicFamilies.enumerated().map { (normalized($1), $0) },
                              uniquingKeysWith: { first, _ in first })
        return families.enumerated().sorted { a, b in
            let ra = rank[normalized(a.element)] ?? Int.max, rb = rank[normalized(b.element)] ?? Int.max
            if ra != rb { return ra < rb }
            if ra == Int.max, normalized(a.element) != normalized(b.element) {
                return displayName(a.element).localizedStandardCompare(displayName(b.element)) == .orderedAscending
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// These families' row texts as the list shows them now, for a list kept open while a font
    /// downloads. One read of the list for all of them.
    static func pickerLabels(for families: [String]) -> [String] {
        let current = Dictionary(fontPickerEntries().map { (normalized($0.family), $0) }, uniquingKeysWith: { first, _ in first })
        return families.map { family in
            fontLabel(current[normalized(family)] ?? FontEntry(family: family, availability: .downloadable))
        }
    }

    static func fontLabel(_ entry: FontEntry) -> String {
        fontLabel(entry, state: fontDownloadState(entry.family))
    }

    /// Saves the choice (captions restyle at once) and, for a font this device cannot load yet,
    /// starts its download; captions stay System until it is ready.
    static func selectFont(_ family: String?) {
        fontFamily = family
        if let family, resolvedFamily(family) == nil { downloadFont(family) }
    }

    // MARK: Catalog

    /// Starts reading the downloadable catalog off the main thread if it has not been read yet.
    /// The player's font list calls this when it opens; Settings awaits `loadFontCatalog()`.
    static func startFontCatalog() {
        DispatchQueue.global(qos: .utility).async { loadFontCatalogNow() }
    }

    /// Reads the catalog off the main thread if it has not been read yet. Returns when it has been
    /// read, when another caller is already reading it, or after 10 s, whichever is first; the
    /// catalog notification reports a late load.
    static func loadFontCatalog() async {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume() }
            }
            DispatchQueue.global(qos: .utility).async {
                loadFontCatalogNow()
                resumeOnce()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: resumeOnce)
        }
    }

    private static func loadFontCatalogNow() {
        let start = catalogState.withLock { state -> Bool in
            guard !state.catalogQueryStarted else { return false }
            state.catalogQueryStarted = true
            return true
        }
        guard start else { return }
        let installed = availableArabicFamilies
        // Logged before the query, so the installed list reaches the log even if it never returns.
        DiagLog.notice(.playback, "Subtitle fonts: catalog query start installed_arabic=\(installed.count) [\(installed.map(displayName).joined(separator: ", "))]")
        let clock = ContinuousClock()
        let began = clock.now
        let query = queryDownloadableCatalog(installed: installed)
        let milliseconds = Int(((clock.now - began) / .milliseconds(1)).rounded())
        catalogState.withLock { state in
            state.catalogLoaded = true
            state.catalogFamilies = query.families
            state.catalogFaces = query.faces
            state.unconfirmed = query.unconfirmed
        }
        DiagLog.notice(.playback, "Subtitle fonts: catalog query done duration_ms=\(milliseconds) catalog_downloadable_total=\(query.total) catalog_arabic=\(query.families.count) [\(query.families.joined(separator: ", "))] unconfirmed_listed=\(query.unconfirmed.count)")
        postFontCatalogChange()
    }

    private struct CatalogQuery: Sendable {
        var families: [String] = []
        var faces: [String: [String]] = [:]
        var total = 0
        var unconfirmed: [String] = []
    }

    /// The downloadable Arabic families the OS knows of, from ONE catalog-wide enumeration: every
    /// descriptor marked downloadable that covers Arabic or is a known Arabic family. Installed
    /// families are skipped. No per-name queries (those may download or block); Apple families the
    /// catalog does not confirm are listed as unconfirmed anyway.
    private static func queryDownloadableCatalog(installed: [String]) -> CatalogQuery {
        let visible = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let local = Set((installed + visible).map(normalized))
        let known = arabicFontCandidates.flatMap { $0 } + appleDownloadableArabicFamilies
        let knownKeys = Set(known.map(normalized))
        var query = CatalogQuery()
        var seen = Set<String>()

        let request = CTFontDescriptorCreateWithAttributes([kCTFontDownloadableAttribute: true] as CFDictionary)
        let mandatory = NSSet(array: [kCTFontDownloadableAttribute]) as CFSet
        let all = (CTFontDescriptorCreateMatchingFontDescriptors(request, mandatory) as? [CTFontDescriptor]) ?? []
        query.total = all.count
        for descriptor in all {
            guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            else { continue }
            let key = normalized(family)
            guard !local.contains(key) else { continue }
            if !knownKeys.contains(key) {
                let languages = (CTFontDescriptorCopyAttribute(descriptor, kCTFontLanguagesAttribute) as? [String]) ?? []
                guard languages.contains(where: { $0 == "ar" || $0.hasPrefix("ar-") || $0.hasPrefix("ar_") })
                else { continue }
            }
            if let face = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
               !(query.faces[key]?.contains(face) ?? false) {
                query.faces[key, default: []].append(face)
            }
            if seen.insert(key).inserted { query.families.append(family) }
        }
        query.unconfirmed = appleDownloadableArabicFamilies.filter {
            !local.contains(normalized($0)) && !seen.contains(normalized($0))
        }
        return query
    }

    // MARK: Download

    /// Asks CoreText to fetch (or, once fetched, re-activate) `family`. Progress moves the picker
    /// rows; when it is ready and still the chosen font, the captions restyle with it. With no
    /// progress for `fontDownloadTimeout` it is marked failed, and a later pick tries again.
    static func downloadFont(_ family: String) {
        let key = normalized(family)
        let begun = catalogState.withLock { state -> (attempt: Int, faces: [String])? in
            switch state.states[key] {
            case .waiting?, .downloading?: return nil
            default: break
            }
            state.nextAttempt += 1
            state.attempts[key] = state.nextAttempt
            state.progressed[key] = false
            state.states[key] = .waiting
            return (state.nextAttempt, state.catalogFaces[key] ?? [])
        }
        guard let begun else { return }
        let attempt = begun.attempt
        postFontCatalogChange()
        let request = downloadRequest(for: family, catalogFaces: begun.faces)
        let descriptors = request.postScriptNames.map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } + request.families.map {
            CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: $0] as CFDictionary)
        }
        DiagLog.notice(.playback, "Subtitle font download start family=\(family) attempt=\(attempt) catalog_faces=\(begun.faces.count) postscript=[\(request.postScriptNames.joined(separator: ", "))] families=[\(request.families.joined(separator: ", "))]")
        armDownloadWatchdog(family, attempt: attempt)
        let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, nil) { state, parameters in
            // Returning false cancels the request: done for an attempt that timed out or was replaced.
            let info = parameters as NSDictionary
            switch state {
            case .willBeginQuerying, .stalled:
                return updateDownloadState(key, attempt: attempt, progressed: false) { current in
                    if case .downloading = current { return current }
                    return .waiting
                }
            case .willBeginDownloading:
                return updateDownloadState(key, attempt: attempt, progressed: true) { current in
                    if case .downloading = current { return current }
                    return .waiting
                }
            case .downloading:
                let percent = (info[kCTFontDescriptorMatchingPercentage as String] as? NSNumber)?.intValue ?? 0
                return updateDownloadState(key, attempt: attempt, progressed: true) { _ in
                    .downloading(min(max(percent, 0), 100))
                }
            case .didFailWithError:
                guard isCurrentAttempt(key, attempt) else { return false }
                let detail = (info[kCTFontDescriptorMatchingError as String] as? NSError).map { DiagLog.describe($0) } ?? "unknown"
                DiagLog.error(.playback, "Subtitle font download error family=\(family): \(detail)")
                return true
            case .didFinish:
                return finishDownload(family, attempt: attempt)
            default:
                return isCurrentAttempt(key, attempt)
            }
        }
        if !started {
            DiagLog.error(.playback, "Subtitle font download could not start family=\(family)")
            finishDownload(family, attempt: attempt)
        }
    }

    private static func isCurrentAttempt(_ key: String, _ attempt: Int) -> Bool {
        catalogState.withLock { $0.attempts[key] == attempt }
    }

    /// Applies `change` if `attempt` is still the family's running one; false (ignored) otherwise.
    private static func updateDownloadState(_ key: String, attempt: Int, progressed: Bool,
                                            _ change: @Sendable (FontDownloadState) -> FontDownloadState) -> Bool {
        let outcome = catalogState.withLock { state -> (current: Bool, changed: Bool) in
            guard state.attempts[key] == attempt else { return (false, false) }
            if progressed { state.progressed[key] = true }
            let current = state.states[key] ?? .idle
            let next = change(current)
            state.states[key] = next
            return (true, next != current)
        }
        if outcome.changed { postFontCatalogChange() }
        return outcome.current
    }

    /// An Apple family the catalog did not confirm (all of them until it loads): a failed download
    /// of one hides the unconfirmed families for the session.
    private static func isUnconfirmedFamily(_ key: String, in state: FontCatalogState) -> Bool {
        appleDownloadableArabicFamilies.contains { normalized($0) == key }
            && !state.catalogFamilies.contains { normalized($0) == key }
    }

    private enum WatchdogVerdict: Sendable { case stale, rearm, timedOut }

    /// After `fontDownloadTimeout`, a still-running attempt with no progress in that window is
    /// marked failed; one that progressed gets another window. Later callbacks from a timed-out
    /// attempt are ignored, and a re-pick starts a new attempt.
    private static func armDownloadWatchdog(_ family: String, attempt: Int) {
        let key = normalized(family)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + fontDownloadTimeout) {
            let verdict = catalogState.withLock { state -> WatchdogVerdict in
                guard state.attempts[key] == attempt else { return .stale }
                if state.progressed[key] == true {
                    state.progressed[key] = false
                    return .rearm
                }
                state.attempts[key] = nil
                state.progressed[key] = nil
                state.states[key] = .failed
                if isUnconfirmedFamily(key, in: state) { state.unconfirmedFailed = true }
                return .timedOut
            }
            switch verdict {
            case .stale:
                break
            case .rearm:
                armDownloadWatchdog(family, attempt: attempt)
            case .timedOut:
                DiagLog.error(.playback, "Subtitle font download timeout family=\(family) attempt=\(attempt) after=\(Int(fontDownloadTimeout))s")
                postFontCatalogChange()
            }
        }
    }

    /// Ends `attempt`: ready when CoreText now loads the family, else failed. False (ignored) when
    /// the attempt already ended (timed out or replaced).
    @discardableResult
    private static func finishDownload(_ family: String, attempt: Int) -> Bool {
        let key = normalized(family)
        let loaded = loadedFamily(family)
        let current = catalogState.withLock { state -> Bool in
            guard state.attempts[key] == attempt else { return false }
            state.attempts[key] = nil
            state.progressed[key] = nil
            if let loaded {
                state.states[key] = .idle
                if !state.activated.contains(where: { normalized($0) == key }) { state.activated.append(loaded) }
            } else {
                state.states[key] = .failed
                if isUnconfirmedFamily(key, in: state) { state.unconfirmedFailed = true }
            }
            return true
        }
        guard current else { return false }
        DiagLog.notice(.playback, "Subtitle font download \(loaded != nil ? "ready" : "failed") family=\(family) attempt=\(attempt)")
        DispatchQueue.main.async {
            if loaded != nil, let stored = fontFamily, normalized(stored) == key { notifyChanged() }
            NotificationCenter.default.post(name: fontCatalogDidChange, object: nil)
        }
        return true
    }

    private static func postFontCatalogChange() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: fontCatalogDidChange, object: nil) }
    }
}
