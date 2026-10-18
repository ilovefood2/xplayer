// SPDX-License-Identifier: MIT
import XCTest

final class XPlayerUITests: XCTestCase {
    @MainActor private func selectTab(_ name: String, in app: XCUIApplication) {
        // iPad exposes floating tabs as cells instead of a TabBar.
        let tab = app.descendants(matching: .any).matching(identifier: name).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    @MainActor func testPrivacyAndLicenseAreReadableInApp() throws {
        let app = XCUIApplication()
        app.launch()
        selectTab("About", in: app)
        app.buttons["Privacy Policy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your video library"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Open Source License"].tap()
        XCTAssertTrue(app.navigationBars["MIT License"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MIT License"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Help & Supported Formats"].tap()
        XCTAssertTrue(app.staticTexts["Import videos and folders"].waitForExistence(timeout: 5))
    }

    @MainActor func testFoldersAndPlaylistsSurviveRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let suffix = String(UUID().uuidString.prefix(6))
        let folder = "Trips \(suffix)"
        let playlist = "Favorites \(suffix)"
        app.buttons["Library actions"].tap()
        app.buttons["New Folder"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(folder)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[folder].waitForExistence(timeout: 5))
        app.staticTexts[folder].tap()
        XCTAssertTrue(app.navigationBars[folder].waitForExistence(timeout: 5))
        app.buttons["Library actions"].tap()
        app.buttons["New Folder"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Day One")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Day One"].waitForExistence(timeout: 5))
        selectTab("Playlists", in: app)
        app.buttons["Create playlist"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(playlist)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[playlist].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[folder].waitForExistence(timeout: 5))
        app.staticTexts[folder].tap()
        XCTAssertTrue(app.staticTexts["Day One"].waitForExistence(timeout: 5))
        selectTab("Playlists", in: app)
        XCTAssertTrue(app.staticTexts[playlist].waitForExistence(timeout: 5))
        app.staticTexts[playlist].tap()
        XCTAssertTrue(app.buttons["Add Videos"].waitForExistence(timeout: 5))
    }
    @MainActor func testSelectMultipleItemsCancelThenDelete() throws {
        let app = XCUIApplication()
        app.launch()
        let prefix = "Batch-" + String(UUID().uuidString.prefix(6))
        let names = [prefix + "-one", prefix + "-two"]
        for folder in names {
            app.buttons["Library actions"].tap()
            app.buttons["New Folder"].tap()
            let field = app.textFields["nameField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(folder)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts[folder].waitForExistence(timeout: 5))
        }
        app.buttons["Select"].tap()
        for folder in names { app.buttons[folder].tap() }
        app.buttons["Delete Selected (2)"].tap()
        XCTAssertTrue(app.buttons["Delete from Library"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        for folder in names { XCTAssertTrue(app.buttons[folder].exists) }
        app.buttons["Delete Selected (2)"].tap()
        app.buttons["Delete from Library"].tap()
        for folder in names { XCTAssertFalse(app.staticTexts[folder].exists) }
        app.terminate()
        app.launch()
        for folder in names { XCTAssertFalse(app.staticTexts[folder].exists) }
    }

    @MainActor func testNetworkURLValidationPresentationAndFailure() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Open Network Video"].tap()
        let field = app.textFields["networkURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("file:///tmp/test.mp4")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.staticTexts["Enter a full HTTP or HTTPS video URL without an embedded username or password."].waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "file:///tmp/test.mp4".count))
        field.typeText("http://127.0.0.1:1/test.mp4")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.navigationBars["test.mp4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["playbackError"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        selectTab("Favorites", in: app)
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
    }

    @MainActor func testMatroskaNetworkPlaybackControls() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mkv"))
        let server = try VideoHTTPServer(files: ["/clip.mkv": Data(contentsOf: fixture)])
        defer { server.stop() }
        let ready = expectation(description: "MKV UI fixture server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Open Network Video"].tap()
        let field = app.textFields["networkURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:\(try XCTUnwrap(server.port))/clip.mkv")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.navigationBars["clip.mkv"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["vlcPlayPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Playback position"].exists)
        XCTAssertFalse(app.staticTexts["playbackError"].exists)
        let playPause = app.buttons["vlcPlayPause"]
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playPause)
        await fulfillment(of: [hidden], timeout: 6)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "MKV controls hidden"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["playerVideo"].tap()
        XCTAssertTrue(playPause.waitForExistence(timeout: 3))
        playPause.tap()
        let paused = expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: playPause)
        await fulfillment(of: [paused], timeout: 3)
        let staysVisible = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playPause)
        staysVisible.isInverted = true
        await fulfillment(of: [staysVisible], timeout: 4)
        XCTAssertTrue(app.buttons["Done"].exists)
        playPause.tap()
        let hidesAgain = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playPause)
        await fulfillment(of: [hidesAgain], timeout: 6)
        app.buttons["playerVideo"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    @MainActor func testNativePlaybackHidesAndRestoresAppControls() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "controls", withExtension: "mp4"))
        let server = try VideoHTTPServer(files: ["/controls.mp4": Data(contentsOf: fixture)])
        defer { server.stop() }
        let ready = expectation(description: "Native controls UI fixture ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Open Network Video"].tap()
        let field = app.textFields["networkURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:\(try XCTUnwrap(server.port))/controls.mp4")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Done"])
        await fulfillment(of: [hidden], timeout: 6)
        XCTAssertFalse(app.buttons["Next"].exists)
        let transportHidden = expectation(for: NSPredicate(format: "exists == false OR hittable == false"), evaluatedWith: app.buttons["Play/Pause"])
        await fulfillment(of: [transportHidden], timeout: 8)
        app.otherElements["nativeVideo"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        let pause = app.buttons["Play/Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        if pause.label.lowercased().contains("pause") { pause.tap() }
        let paused = expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: pause)
        await fulfillment(of: [paused], timeout: 3)
        let staysVisible = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Done"])
        staysVisible.isInverted = true
        await fulfillment(of: [staysVisible], timeout: 4)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native controls restored and paused"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

}
