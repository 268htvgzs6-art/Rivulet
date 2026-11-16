// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Subtitle Font and Subtitle Brightness, layered on top of the system caption
// style (CaptionAppearance). The font applies to plain captions only; brightness
// dims the text colour (not its opacity) for plain, libass and picture captions.

import CoreGraphics
import CoreText
import Foundation

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

    /// Selection by family; nil is System. Matches the stored name.
    static func isFontSelected(_ family: String?) -> Bool {
        guard let family else { return fontFamily == nil }
        return fontFamily.map(normalized) == normalized(family)
    }

    /// The Subtitle Font value, in Settings: System when unset or when the stored
    /// family does not load here (the captions then use System too).
    static var fontValueLabel: String {
        resolvedFamily(fontFamily).map(displayName) ?? String(localized: "System")
    }

    /// Lists the installed Arabic families once, off the main thread, so the first
    /// Settings or player font list does not wait for the scan.
    static func prepareFontsAtLaunch() {
        DispatchQueue.global(qos: .utility).async { _ = availableArabicFamilies }
    }
}
