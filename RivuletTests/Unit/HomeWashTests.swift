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
        let hold = HomeWash.holdDelay
        XCTAssertEqual(HomeWash.holdRemaining(now: 100, armedAt: 100, lastMotion: 0), hold, accuracy: 0.0001)
        XCTAssertEqual(HomeWash.holdRemaining(now: 100 + hold / 2, armedAt: 100, lastMotion: 0), hold / 2,
                       accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 0), 0.0001)
    }

    func test_holdRemaining_waitsForThePageToBeStill() {
        let hold = HomeWash.holdDelay
        // The hold has run out, but the page moved a moment ago: wait out the still period.
        let wait = HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 100 + hold - 0.1)
        XCTAssertEqual(wait, HomeWash.settleDelay - 0.1, accuracy: 0.0001)
        // Still for long enough: reveal now.
        XCTAssertLessThanOrEqual(
            HomeWash.holdRemaining(now: 100 + hold, armedAt: 100, lastMotion: 100 + hold - HomeWash.settleDelay),
            0.0001)
    }
}
