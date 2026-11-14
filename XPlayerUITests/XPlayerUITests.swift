// SPDX-License-Identifier: MIT
import XCTest

final class XPlayerUITests: XCTestCase {
    @MainActor private func selectTab(_ name: String, in app: XCUIApplication) {
        // iPad exposes floating tabs as cells instead of a TabBar.
        let tab = app.descendants(matching: .any).matching(identifier: name).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    @MainActor func testLibraryAndFavoritesLayout() {
        let app = XCUIApplication()
        app.launch()
        let library = XCTAttachment(screenshot: app.screenshot())
        library.name = "Library layout"
        library.lifetime = .keepAlways
        add(library)
        selectTab("Favorites", in: app)
        let favorites = XCTAttachment(screenshot: app.screenshot())
        favorites.name = "Favorites layout"
        favorites.lifetime = .keepAlways
        add(favorites)
        selectTab("Playlists", in: app)
        let playlists = XCTAttachment(screenshot: app.screenshot())
        playlists.name = "Playlists layout"
        playlists.lifetime = .keepAlways
        add(playlists)
    }

    @MainActor func testPrivacyAndLicenseAreReadableInApp() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Help & About"].tap()
        let help = XCTAttachment(screenshot: app.screenshot())
        help.name = "Help and licenses"
        help.lifetime = .keepAlways
        add(help)
        app.buttons["Privacy Policy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your video library"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Open Source License"].tap()
        XCTAssertTrue(app.navigationBars["MIT License"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MIT License"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Third-Party Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Third-Party Licenses"].waitForExistence(timeout: 5))
        app.buttons["Acknowledgements"].tap()
        XCTAssertTrue(app.staticTexts["Third-party copyright and license notices"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
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
        let visibleControls = XCTAttachment(screenshot: app.screenshot())
        visibleControls.name = "Compact MKV controls"
        visibleControls.lifetime = .keepAlways
        add(visibleControls)
        XCTAssertTrue(app.buttons["Done"].exists)
        playPause.tap()
        let hidesAgain = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playPause)
        await fulfillment(of: [hidesAgain], timeout: 6)
        app.buttons["playerVideo"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    @MainActor func testNativeDoubleTapSeekingAndSpeedSlider() async throws {
        try await checkSeekingAndSpeed(extension: "mp4")
    }

    @MainActor func testVLCDoubleTapSeekingAndSpeedSlider() async throws {
        try await checkSeekingAndSpeed(extension: "mkv")
    }

    @MainActor private func checkSeekingAndSpeed(extension ext: String) async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek", withExtension: ext))
        let server = try VideoHTTPServer(files: ["/seek.\(ext)": Data(contentsOf: fixture)])
        defer { server.stop() }
        let ready = expectation(description: "Seek/speed fixture ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Open Network Video"].tap()
        let field = app.textFields["networkURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:\(try XCTUnwrap(server.port))/seek.\(ext)")
        app.buttons["Play"].tap()
        let speedButton = app.buttons["playbackSpeed"]
        XCTAssertTrue(speedButton.waitForExistence(timeout: 5))
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Done"])
        await fulfillment(of: [hidden], timeout: 8)
        let video = ext == "mkv" ? app.buttons["playerVideo"] : app.otherElements["nativeVideo"]
        XCTAssertTrue(video.exists)
        let feedback = app.descendants(matching: .any).matching(identifier: "seekFeedback").firstMatch
        for (x, label) in [(0.75, "Forward 15 seconds"), (0.25, "Back 15 seconds")] {
            video.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.4)).doubleTap()
            XCTAssertTrue(feedback.exists)
            XCTAssertEqual(feedback.label, label)
            XCTAssertFalse(app.buttons["Done"].exists)
        }
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(speedButton.waitForExistence(timeout: 3))
        speedButton.tap()
        let slider = app.sliders["Playback speed"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(slider.value as? String, "0.25×")
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(slider.value as? String, "2×")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(ext.uppercased()) speed slider"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let remainsVisible = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: slider)
        remainsVisible.isInverted = true
        await fulfillment(of: [remainsVisible], timeout: 4)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(speedButton.label.contains("2×"))
        XCTAssertFalse(app.staticTexts["playbackError"].exists)
        app.buttons["Done"].tap()
    }

    /// Taps once the element is on screen and not mid-transition, dismissing
    /// iOS's optional "Save Password?" prompt if it covers the screen.
    @MainActor private func tapWhenReady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        for _ in 0..<40 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
            if element.exists && element.isHittable { element.tap(); return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("\(element) never became tappable", file: file, line: line)
    }

    /// Picture in Picture adds an empty window, so measure the largest one.
    @MainActor private func largestWindow(_ app: XCUIApplication) -> CGRect {
        app.windows.allElementsBoundByIndex.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
    }

    @MainActor private func capture(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Every tab and both players (Apple and VLC) in landscape, on iPhone and iPad.
    @MainActor func testLandscapeLibraryAndPlayback() async throws {
        let server = try VideoHTTPServer(files: [
            "/seek.mp4": Data(contentsOf: try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek", withExtension: "mp4"))),
            "/clip.mkv": Data(contentsOf: try XCTUnwrap(Bundle(for: Self.self).url(forResource: "clip", withExtension: "mkv"))),
        ])
        defer { server.stop() }
        let ready = expectation(description: "Landscape fixture server ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let actions = app.buttons["Library actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isHittable)
        let window = largestWindow(app)
        XCTAssertGreaterThan(window.width, window.height, "The interface did not rotate to landscape: \(window)")
        capture("Landscape library", from: app)
        selectTab("Favorites", in: app)
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
        capture("Landscape favorites", from: app)
        selectTab("Playlists", in: app)
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        capture("Landscape playlists", from: app)
        selectTab("Library", in: app)

        for (file, vlc) in [("seek.mp4", false), ("clip.mkv", true)] {
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            app.buttons["Open Network Video"].tap()
            let field = app.textFields["networkURL"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("http://127.0.0.1:\(try XCTUnwrap(server.port))/\(file)")
            app.buttons["Play"].tap()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            XCTAssertTrue(done.isHittable, "\(file): Done must be reachable in landscape")
            let playerWindow = largestWindow(app)
            XCTAssertGreaterThan(playerWindow.width, playerWindow.height, "\(file): player did not rotate: \(playerWindow)")
            XCTAssertTrue(app.buttons["playbackSpeed"].isHittable, "\(file): speed must be reachable in landscape")
            if vlc {
                XCTAssertTrue(app.buttons["vlcPlayPause"].isHittable)
                XCTAssertTrue(app.sliders["Playback position"].isHittable)
            }
            try await Task.sleep(for: .seconds(1))
            XCTAssertFalse(app.staticTexts["playbackError"].exists, "\(file) failed to play in landscape")
            capture("Landscape \(file) player", from: app)
            // Controls auto-hide after 3 seconds; reveal them again if they did.
            let video = vlc ? app.buttons["playerVideo"] : app.otherElements["nativeVideo"]
            for _ in 0..<3 where !(done.waitForExistence(timeout: 1) && done.isHittable) { video.tap() }
            XCTAssertTrue(done.isHittable)
            done.tap()
            XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        }
    }

    private static func davListing(_ base: String, _ entries: [(String, Bool)]) -> String {
        let responses = ([(base, true)] + entries).map { href, folder in
            "<d:response><d:href>\(href)</d:href><d:propstat><d:prop>\(folder ? "<d:resourcetype><d:collection/></d:resourcetype>" : "<d:resourcetype/>")</d:prop></d:propstat></d:response>"
        }.joined()
        return #"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">"# + responses + "</d:multistatus>"
    }

    @MainActor func testWebDAVShareBrowseAndPlay() async throws {
        let header = "Basic " + Data("kai:pw".utf8).base64EncodedString()
        let video = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek", withExtension: "mp4")))
        let server = try VideoHTTPServer(
            files: ["/dav/Show/episode.mp4": video],
            listings: ["/dav/": Self.davListing("/dav/", [("/dav/Show/", true)]),
                       "/dav/Show/": Self.davListing("/dav/Show/", [("/dav/Show/episode.mp4", false)])],
            authorization: header)
        defer { server.stop() }
        let ready = expectation(description: "WebDAV UI fixture ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        selectTab("Network", in: app)
        if app.buttons["addShareEmpty"].waitForExistence(timeout: 2) {
            app.buttons["addShareEmpty"].tap()
        } else {
            app.buttons["Network actions"].tap()
            app.buttons["Add Share"].firstMatch.tap()
        }
        let name = "DAV " + String(UUID().uuidString.prefix(6))
        app.buttons["shareKind"].tap()
        app.buttons["WebDAV (HTTP/HTTPS)"].tap()
        for (field, text) in [("shareAddress", "http://127.0.0.1:\(try XCTUnwrap(server.port))/dav"), ("shareName", name), ("shareUser", "kai")] {
            let element = app.textFields[field]
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            element.tap()
            element.typeText(text)
        }
        app.secureTextFields["sharePassword"].tap()
        app.secureTextFields["sharePassword"].typeText("pw")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        capture("Network shares", from: app)
        tapWhenReady(app.staticTexts[name])
        tapWhenReady(app.staticTexts["Show"])
        tapWhenReady(app.staticTexts["episode.mp4"])
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(app.staticTexts["playbackError"].exists)
        capture("Share playback", from: app)
        for _ in 0..<3 where !(done.waitForExistence(timeout: 1) && done.isHittable) { app.otherElements["nativeVideo"].tap() }
        done.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
        app.staticTexts[name].press(forDuration: 1.2)
        app.buttons["Remove"].tap()
        app.alerts.buttons["Remove"].tap()
        XCTAssertFalse(app.staticTexts[name].waitForExistence(timeout: 2))
    }

    @MainActor func testAudioAndSubtitleChoicesInPlayer() async throws {
        let video = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "tracks", withExtension: "mp4")))
        let server = try VideoHTTPServer(files: ["/tracks.mp4": video])
        defer { server.stop() }
        let ready = expectation(description: "Track fixture ready")
        server.start { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launch()
        app.buttons["Library actions"].tap()
        app.buttons["Open Network Video"].tap()
        let field = app.textFields["networkURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:\(try XCTUnwrap(server.port))/tracks.mp4")
        app.buttons["Play"].tap()
        let options = app.buttons["playerOptions"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        options.tap()
        let japanese = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Japan' OR label CONTAINS[c] '日本'")).firstMatch
        XCTAssertTrue(japanese.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Subtitles"].exists || app.otherElements["Subtitles"].exists)
        japanese.tap()
        XCTAssertTrue(japanese.isSelected)
        // The panel stays open while choosing, even though playback continues.
        try await Task.sleep(for: .seconds(4))
        XCTAssertTrue(japanese.exists, "The options panel closed while it was in use")
        capture("Audio and subtitle choices", from: app)
        let english = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'English' OR label CONTAINS[c] '英'")).element(boundBy: 1)
        if english.exists { english.tap() }
        XCTAssertFalse(app.staticTexts["playbackError"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        let done = app.buttons["Done"]
        for _ in 0..<3 where !(done.waitForExistence(timeout: 1) && done.isHittable) { app.otherElements["nativeVideo"].tap() }
        done.tap()
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
