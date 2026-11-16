// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

// Subtitle Font and Subtitle Brightness.

import CoreGraphics
import XCTest
@testable import Rivulet

final class SubtitleAppearanceTests: XCTestCase {

    // MARK: Brightness

    private func rgba(_ color: CGColor) throws -> [CGFloat] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(color.converted(to: space, intent: .defaultIntent, options: nil)?.components)
    }

    func test_dim_whiteAtFortyPercent_isOpaqueGrey() throws {
        let c = try rgba(SubtitleAppearance.dim(CGColor(gray: 1, alpha: 1), by: 0.4))
        XCTAssertEqual(c[0], 0.4, accuracy: 0.001)
        XCTAssertEqual(c[1], 0.4, accuracy: 0.001)
        XCTAssertEqual(c[2], 0.4, accuracy: 0.001)
        XCTAssertEqual(c[3], 1, accuracy: 0.001)
    }

    func test_dim_keepsAlpha() throws {
        let c = try rgba(SubtitleAppearance.dim(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.6), by: 0.5))
        XCTAssertEqual(c[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(c[1], 0.25, accuracy: 0.001)
        XCTAssertEqual(c[2], 0, accuracy: 0.001)
        XCTAssertEqual(c[3], 0.6, accuracy: 0.001)
    }

    func test_dim_fullBrightness_returnsColourUnchanged() {
        let white = CGColor(gray: 1, alpha: 1)
        XCTAssertEqual(SubtitleAppearance.dim(white, by: 1), white)
    }

    func test_clamp_holdsToFortyThroughHundred() {
        XCTAssertEqual(SubtitleAppearance.clampBrightness(0.1), 0.4)
        XCTAssertEqual(SubtitleAppearance.clampBrightness(1.5), 1)
        XCTAssertEqual(SubtitleAppearance.clampBrightness(.nan), 1)
        XCTAssertEqual(SubtitleAppearance.clampBrightness(0.7), 0.7)
    }

    func test_dim_belowMinimum_clampsToForty() throws {
        let c = try rgba(SubtitleAppearance.dim(CGColor(gray: 1, alpha: 1), by: 0.1))
        XCTAssertEqual(c[0], 0.4, accuracy: 0.001)
    }

    func test_nextBrightness_stepsDownThenWraps() {
        XCTAssertEqual(SubtitleAppearance.nextBrightness(after: 1), 0.9)
        XCTAssertEqual(SubtitleAppearance.nextBrightness(after: 0.5), 0.4)
        XCTAssertEqual(SubtitleAppearance.nextBrightness(after: 0.4), 1)
    }

    /// The in-player stepper: Right brighter, Left dimmer, stopping at 100% and 40%.
    func test_steppedBrightness_stepsTenPercent_andStopsAtTheEnds() {
        XCTAssertEqual(SubtitleAppearance.steppedBrightness(0.7, by: 1), 0.8)
        XCTAssertEqual(SubtitleAppearance.steppedBrightness(0.7, by: -1), 0.6)
        XCTAssertEqual(SubtitleAppearance.steppedBrightness(1, by: 1), 1)
        XCTAssertEqual(SubtitleAppearance.steppedBrightness(0.4, by: -1), 0.4)
        // An off-grid stored value steps from its nearest option.
        XCTAssertEqual(SubtitleAppearance.steppedBrightness(0.72, by: 1), 0.8)
    }

    /// Caption surfaces restyle on the caption-change notification, so a change must post it.
    func test_settingBrightness_postsTheCaptionChangeNotification() {
        let saved = UserDefaults.standard.object(forKey: SubtitleAppearance.brightnessKey)
        defer { UserDefaults.standard.set(saved, forKey: SubtitleAppearance.brightnessKey) }
        let posted = expectation(forNotification: CaptionAppearance.changedNotification, object: nil)
        SubtitleAppearance.brightness = 0.7
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(SubtitleAppearance.brightness, 0.7)
    }

    func test_dimASSColor_scalesRGB_keepsTransparency() {
        XCTAssertEqual(SubtitleAppearance.dimASSColor(0xFFFFFF00, by: 0.4), 0x66666600)
        XCTAssertEqual(SubtitleAppearance.dimASSColor(0xFF0000_80, by: 0.5), 0x80000080)
        XCTAssertEqual(SubtitleAppearance.dimASSColor(0x12345678, by: 1), 0x12345678)
    }

    // MARK: Font

    func test_resolvedFamily_unsetOrEmpty_isSystem() {
        XCTAssertNil(SubtitleAppearance.resolvedFamily(nil, load: { $0 }))
        XCTAssertNil(SubtitleAppearance.resolvedFamily("", load: { $0 }))
        XCTAssertNil(SubtitleAppearance.resolvedFamily("  ", load: { $0 }))
    }

    func test_resolvedFamily_missingFont_fallsBackToSystem() {
        XCTAssertNil(SubtitleAppearance.resolvedFamily("Diwan Kufi", load: { _ in nil }))
    }

    func test_resolvedFamily_findsHiddenSystemSpelling() {
        let installed = [".SF Arabic"]
        let load: (String) -> String? = { name in installed.first { $0 == name } }
        XCTAssertEqual(SubtitleAppearance.resolvedFamily("SF Arabic", load: load), ".SF Arabic")
        XCTAssertEqual(SubtitleAppearance.resolvedFamily(".SF Arabic", load: load), ".SF Arabic")
    }

    func test_normalized_ignoresCaseSpacesAndHiddenDot() {
        XCTAssertEqual(SubtitleAppearance.normalized("Al Bayan"), SubtitleAppearance.normalized("albayan"))
        XCTAssertEqual(SubtitleAppearance.normalized(".SF Arabic"), SubtitleAppearance.normalized("SF Arabic"))
        XCTAssertEqual(SubtitleAppearance.displayName(".SF Arabic"), "SF Arabic")
    }

    /// Geeza Pro ships on every tvOS; an unknown family gives no descriptor (System).
    func test_fontDescriptor_resolvesInstalledFamily_andNotAMissingOne() {
        XCTAssertNotNil(SubtitleAppearance.fontDescriptor(forFamily: "Geeza Pro"))
        XCTAssertNil(SubtitleAppearance.fontDescriptor(forFamily: "No Such Font Family"))
        XCTAssertNil(SubtitleAppearance.fontDescriptor(forFamily: nil))
    }

    /// The list holds only families that load here, each once.
    func test_availableArabicFamilies_loadHere_withoutDuplicates() {
        let families = SubtitleAppearance.availableArabicFamilies
        XCTAssertTrue(families.contains { SubtitleAppearance.normalized($0) == "geezapro" })
        XCTAssertEqual(Set(families.map(SubtitleAppearance.normalized)).count, families.count)
        for family in families {
            XCTAssertNotNil(SubtitleAppearance.resolvedFamily(family), family)
        }
    }

    // MARK: Downloadable fonts

    func test_fontEntries_installedFirst_thenDownloadable_withoutDuplicates() {
        let entries = SubtitleAppearance.fontEntries(installed: ["Geeza Pro", ".SF Arabic"],
                                                     downloadable: ["Diwan Kufi", "geezapro", "SF Arabic", "Al Nile"])
        XCTAssertEqual(entries.map(\.family), ["Geeza Pro", ".SF Arabic", "Diwan Kufi", "Al Nile"])
        XCTAssertEqual(entries.map(\.availability), [.installed, .installed, .downloadable, .downloadable])
    }

    func test_fontLabel_installedIsItsName_downloadableShowsItsState() {
        let installed = SubtitleAppearance.FontEntry(family: ".SF Arabic", availability: .installed)
        XCTAssertEqual(SubtitleAppearance.fontLabel(installed, state: .idle), "SF Arabic")
        let remote = SubtitleAppearance.FontEntry(family: "Diwan Kufi", availability: .downloadable)
        let idle = SubtitleAppearance.fontLabel(remote, state: .idle)
        XCTAssertTrue(idle.hasPrefix("Diwan Kufi"))
        XCTAssertNotEqual(idle, "Diwan Kufi")
        XCTAssertTrue(SubtitleAppearance.fontLabel(remote, state: .downloading(40)).contains("40"))
        XCTAssertNotEqual(SubtitleAppearance.fontLabel(remote, state: .failed), idle)
    }

    /// Until the catalog loads (or if it never does), Apple's families are listed.
    func test_downloadableFamilies_beforeCatalog_listsAppleFamiliesNotInstalled() {
        let installed = ["Geeza Pro", ".SF Arabic", "al nile"]
        let fallback = SubtitleAppearance.downloadableFamilies(
            installed: installed, catalogLoaded: false, catalogFamilies: [], unconfirmed: [], unconfirmedFailed: false)
        XCTAssertEqual(fallback, SubtitleAppearance.appleDownloadableArabicFamilies.filter { $0 != "Al Nile" })
        XCTAssertEqual(SubtitleAppearance.fallbackDownloadableFamilies(installed: installed), fallback)
        let loaded = SubtitleAppearance.downloadableFamilies(
            installed: installed, catalogLoaded: true, catalogFamilies: ["Muna"], unconfirmed: ["Farah"],
            unconfirmedFailed: false)
        XCTAssertEqual(loaded, ["Muna", "Farah"])
        let afterFailure = SubtitleAppearance.downloadableFamilies(
            installed: installed, catalogLoaded: true, catalogFamilies: ["Muna"], unconfirmed: ["Farah"],
            unconfirmedFailed: true)
        XCTAssertEqual(afterFailure, ["Muna"])
    }

    /// With no catalog faces, a download names the family's PostScript faces and each spelling.
    func test_downloadRequest_usesStaticFacesAndSpellings_whenCatalogHasNone() {
        let kufi = SubtitleAppearance.downloadRequest(for: "Kufi Standard GK", catalogFaces: [])
        XCTAssertEqual(kufi.postScriptNames, ["KufiStandardGK"])
        XCTAssertEqual(kufi.families, ["Kufi Standard GK", "KufiStandardGK"])
        let fromCatalog = SubtitleAppearance.downloadRequest(for: "Muna", catalogFaces: ["Muna"])
        XCTAssertEqual(fromCatalog.postScriptNames, ["Muna"])
        XCTAssertTrue(fromCatalog.families.isEmpty)
    }

    func test_stableDownloadOrder_keepsApplesOrder_whateverTheCatalogOrder() {
        let catalog = ["Muna", "KufiStandardGK", "Al Tarikh", "Zeta Extra", "Baghdad", "Alpha Extra"]
        XCTAssertEqual(SubtitleAppearance.stableDownloadOrder(catalog),
                       ["Al Tarikh", "Baghdad", "KufiStandardGK", "Muna", "Alpha Extra", "Zeta Extra"])
        XCTAssertEqual(SubtitleAppearance.stableDownloadOrder(catalog.reversed()),
                       SubtitleAppearance.stableDownloadOrder(catalog))
    }

    /// A pick from the list shown before the catalog answers is saved as written, and CoreText
    /// loads Kufi Standard GK only by its file's family name.
    func test_fallbackList_spellsKufiAsItsFontFileDoes() {
        let fallback = SubtitleAppearance.fallbackDownloadableFamilies(installed: [])
        XCTAssertTrue(fallback.contains("KufiStandardGK"))
        XCTAssertFalse(fallback.contains("Kufi Standard GK"))
        XCTAssertEqual(SubtitleAppearance.downloadRequest(for: "KufiStandardGK", catalogFaces: []).postScriptNames,
                       ["KufiStandardGK"])
    }
}
