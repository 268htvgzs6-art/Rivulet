// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2026 Bain Gurley

//
//  OutsideLookupsTests.swift
//  RivuletTests
//
//  The outside lookups are off until switched on, and while the developer one is off
//  `attestedData` throws before any request is made. Every request here goes to the mock.
//

import XCTest
@testable import Rivulet

final class OutsideLookupsTests: XCTestCase {

    private let keys = [OutsideLookups.developerKey, OutsideLookups.plexAdvisoryKey, OutsideLookups.plexPeopleKey]

    override func setUp() {
        super.setUp()
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        TMDBMockURLProtocol.responses = [:]
        TMDBMockURLProtocol.hitCounts = [:]
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    func test_everyLookup_isOffUntilTurnedOn() {
        XCTAssertFalse(OutsideLookups.developer)
        XCTAssertFalse(OutsideLookups.plexAdvisory)
        XCTAssertFalse(OutsideLookups.plexPeople)
    }

    func test_developerOff_throwsBeforeAnyRequest() async {
        let request = URLRequest(url: URL(string: "https://example.invalid/v1/ratings/movie/1")!)
        do {
            _ = try await makeMockSession().attestedData(for: request)
            XCTFail("the request went out with the lookups off")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired)
        }
        XCTAssertTrue(TMDBMockURLProtocol.hitCounts.isEmpty)
    }

    func test_developerOn_requestGoesOut() async {
        OutsideLookups.developer = true
        TMDBMockURLProtocol.responses["v1/ratings/movie/1?"] = (200, Data("{}".utf8))
        let request = URLRequest(url: URL(string: "https://example.invalid/v1/ratings/movie/1")!)
        let result = try? await makeMockSession().attestedData(for: request)
        XCTAssertEqual((result?.1 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(TMDBMockURLProtocol.hitCounts["v1/ratings/movie/1?"], 1)
    }

    @MainActor
    func test_aboutPage_hasTheThreeSwitches_eachWithADescription() {
        let ids = SettingsContent.rows(for: .about).map(\.id)
        for id in ["outsideDeveloper", "outsidePlexAdvisory", "outsidePlexPeople"] {
            XCTAssertTrue(ids.contains(id), "\(id) is missing from About")
            XCTAssertNotNil(SettingsDescriptorStore.descriptor(for: id), "\(id) has no description panel entry")
        }
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TMDBMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
