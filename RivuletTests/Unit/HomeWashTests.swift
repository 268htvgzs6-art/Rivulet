import XCTest
@testable import Rivulet

final class HomeWashTests: XCTestCase {

    func test_alpha_followsTheHero_andIsDarkOnceItHasScrolledAway() {
        XCTAssertEqual(HomeWash.alpha(showcase: 1, hasHero: true, revealed: false), 1)
        XCTAssertEqual(HomeWash.alpha(showcase: 0.4, hasHero: true, revealed: false), 0.4)
        XCTAssertEqual(HomeWash.alpha(showcase: 0, hasHero: true, revealed: false), 0)
    }

    func test_alpha_aPageWithNoHeroRestsDark() {
        XCTAssertEqual(HomeWash.alpha(showcase: 1, hasHero: false, revealed: false), 0)
    }

    func test_alpha_aRevealedPictureShowsWhereverThePageIs() {
        XCTAssertEqual(HomeWash.alpha(showcase: 0, hasHero: true, revealed: true), HomeWash.revealAlpha)
        XCTAssertEqual(HomeWash.alpha(showcase: 1, hasHero: false, revealed: true), HomeWash.revealAlpha)
        XCTAssertEqual(HomeWash.alpha(showcase: 1, hasHero: true, revealed: true), 1)
    }

    func test_spotlightFloor_staysAboveTheAlphaUIKitTreatsAsInvisible() {
        // UIKit ignores a view for touches and focus below alpha 0.01.
        XCTAssertGreaterThan(HomeWash.spotlightFloor, 0.01)
        XCTAssertLessThan(HomeWash.spotlightFloor, 0.05)
    }

    func test_holdRemaining_countsTheHoldFromWhenFocusLanded() {
        let hold: TimeInterval = 2
        XCTAssertEqual(HomeWash.holdRemaining(now: 100, armedAt: 100, lastMotion: 0, holdDelay: hold), hold, accuracy: 0.0001)
        XCTAssertEqual(HomeWash.holdRemaining(now: 100 + hold / 2, armedAt: 100, lastMotion: 0, holdDelay: hold), hold / 2,
                       accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 0, holdDelay: hold), 0.0001)
    }

    func test_holdRemaining_waitsForThePageToBeStill() {
        let hold: TimeInterval = 2
        // The hold has run out, but the page moved a moment ago: wait out the still period.
        let wait = HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 100 + hold - 0.1, holdDelay: hold)
        XCTAssertEqual(wait, HomeWash.settleDelay - 0.1, accuracy: 0.0001)
        // Still for long enough: reveal now.
        XCTAssertLessThanOrEqual(
            HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 100 + hold - HomeWash.settleDelay,
                                  holdDelay: hold),
            0.0001)
    }

    func test_holdRemaining_aLongerHoldWaitsLonger() {
        XCTAssertEqual(HomeWash.holdRemaining(now: 101, armedAt: 100, lastMotion: 0, holdDelay: 5), 4, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HomeWash.holdRemaining(now: 101, armedAt: 100, lastMotion: 0, holdDelay: 1), 0.0001)
    }

    // MARK: Poster Spotlight setting

    func test_holdSettings_nextWalksTheOptionsAndWraps() {
        XCTAssertEqual(HomeHoldSettings.next(after: 0), 1)
        XCTAssertEqual(HomeHoldSettings.next(after: 1), 2)
        XCTAssertEqual(HomeHoldSettings.next(after: 2), 3)
        XCTAssertEqual(HomeHoldSettings.next(after: 3), 5)
        XCTAssertEqual(HomeHoldSettings.next(after: 5), 0)
        // Not an option: carries on from the default.
        XCTAssertEqual(HomeHoldSettings.next(after: 4), 3)
    }

    func test_holdSettings_offHasNoHold() {
        XCTAssertNil(HomeHoldSettings.holdDelay(seconds: 0))
        XCTAssertEqual(HomeHoldSettings.holdDelay(seconds: 3), 3)
    }

    func test_holdSettings_defaultAndClamp() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: HomeHoldSettings.secondsKey)
        defer { defaults.set(saved, forKey: HomeHoldSettings.secondsKey) }
        defaults.removeObject(forKey: HomeHoldSettings.secondsKey)
        XCTAssertEqual(HomeHoldSettings.seconds, 2)
        defaults.set(7, forKey: HomeHoldSettings.secondsKey)
        XCTAssertEqual(HomeHoldSettings.seconds, 2)
        HomeHoldSettings.seconds = 5
        XCTAssertEqual(HomeHoldSettings.seconds, 5)
    }
}
