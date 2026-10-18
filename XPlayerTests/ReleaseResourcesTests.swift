// SPDX-License-Identifier: MIT
import XCTest
import UniformTypeIdentifiers
@testable import XPlayer

final class ReleaseResourcesTests: XCTestCase {
    func testPrivacyLicenseAndSupportShipWithTheApplication() throws {
        XCTAssertTrue(try AppInformation.document("PrivacyPolicy").contains("does not upload"))
        XCTAssertTrue(try AppInformation.document("Support").contains("MP4, M4V, and MOV"))
        XCTAssertTrue(try AppInformation.document("License", extension: "txt").contains("MIT License"))
        XCTAssertTrue(try AppInformation.document("ThirdPartyNotices").contains("MobileVLCKit 3.7.3"))
        XCTAssertTrue(try AppInformation.document("MobileVLCKit-LGPL", extension: "txt").contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        for ext in ["mkv", "avi", "webm", "ts", "mts", "m2ts"] {
            XCTAssertTrue(UTType(filenameExtension: ext)?.conforms(to: .movie) == true, ext)
        }
        for ext in ["ts", "mts", "m2ts"] {
            XCTAssertTrue(UTType(filenameExtension: ext)?.conforms(to: .mpeg2TransportStream) == true, ext)
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ilovefood2.xplayer")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "xplayer")
    }
}
