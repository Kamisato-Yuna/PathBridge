import Foundation
import XCTest
@testable import PathBridgeCore

final class ReleaseUpdateTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false,
                         url: String = "https://github.com/Kamisato-Yuna/PathBridge/releases/tag/v0.2.0") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft,
            "prerelease": prerelease, "html_url": url])
    }

    func testNumericVersionOrderingAndValidation() throws {
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v0.9.0")), try XCTUnwrap(ReleaseVersion("0.10.0")))
        XCTAssertEqual(ReleaseVersion("v0.1.0"), ReleaseVersion("0.1.0"))
        for value in ["0.1", "0.1.0.1", "0.01.0", "0.1.-1", "0.2.0-beta", "release-1.0.0", "999999999999999999999.0.0"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testOnlyNewerStableReleaseIsOffered() throws {
        XCTAssertEqual(try ReleaseUpdate.evaluate(data: release("v0.2.0"), statusCode: 200, currentVersion: "0.1.0")?.version, "v0.2.0")
        for tag in ["v0.1.0", "v0.0.9"] {
            XCTAssertNil(try ReleaseUpdate.evaluate(data: release(tag), statusCode: 200, currentVersion: "0.1.0"))
        }
        XCTAssertNil(try ReleaseUpdate.evaluate(data: release("v0.2.0", draft: true), statusCode: 200, currentVersion: "0.1.0"))
        XCTAssertNil(try ReleaseUpdate.evaluate(data: release("v0.2.0-beta", prerelease: true), statusCode: 200, currentVersion: "0.1.0"))
    }

    func testNoReleaseAndServerFailures() throws {
        XCTAssertNil(try ReleaseUpdate.evaluate(data: Data(), statusCode: 404, currentVersion: "0.1.0"))
        for status in [403, 429, 500] {
            XCTAssertThrowsError(try ReleaseUpdate.evaluate(data: Data(), statusCode: status, currentVersion: "0.1.0"))
        }
        XCTAssertThrowsError(try ReleaseUpdate.evaluate(data: Data("{}".utf8), statusCode: 200, currentVersion: "0.1.0"))
        XCTAssertThrowsError(try ReleaseUpdate.evaluate(data: release("nightly"), statusCode: 200, currentVersion: "0.1.0"))
    }

    func testRejectsDownloadLinksOutsideRepository() throws {
        for url in ["http://github.com/Kamisato-Yuna/PathBridge/releases/tag/v0.2.0",
                    "https://example.com/releases/tag/v0.2.0",
                    "https://github.com/other/PathBridge/releases/tag/v0.2.0",
                    "https://github.com@evil.example/Kamisato-Yuna/PathBridge/releases/tag/v0.2.0"] {
            XCTAssertThrowsError(try ReleaseUpdate.evaluate(data: release("v0.2.0", url: url), statusCode: 200, currentVersion: "0.1.0"))
        }
    }
}
