import Foundation
import XCTest
@testable import PathBridgeCore

final class FinderCommandTests: XCTestCase {
    func testEveryActionRoundTripsSpecialCharacters() throws {
        let path = "/Volumes/项目 共享/中文 空格%#?&=+文件\\名称.hip"
        for action in FinderAction.allCases {
            let command = try FinderCommand(action: action, paths: [path])
            let url = try command.url()
            XCTAssertEqual(url.scheme, "pathbridge")
            XCTAssertEqual(url.host, "finder")
            XCTAssertNil(url.fragment)
            XCTAssertEqual(try FinderCommand(url: url), command)
        }
    }

    func testRepeatedPathsPreserveOrderAndDuplicates() throws {
        let paths = ["/Volumes/share/a", "/Volumes/share/b", "/Volumes/share/a"]
        let command = try FinderCommand(action: .copyUNC, paths: paths)
        XCTAssertEqual(try FinderCommand(url: command.url()).paths, paths)
    }

    func testVolumeRootAndDirectoryTrailingSlashAreAccepted() throws {
        for path in ["/Volumes/share", "/Volumes/share/", "/Volumes/share/folder/"] {
            let command = try FinderCommand(action: .open, paths: [path])
            XCTAssertEqual(try FinderCommand(url: command.url()).paths, [path])
        }
    }

    func testSelectionLimits() throws {
        for action in FinderAction.allCases {
            XCTAssertThrowsError(try FinderCommand(action: action, paths: []))
            XCTAssertThrowsError(try FinderCommand(action: action, paths: Array(repeating: "/Volumes/share/a", count: 101)))
            if action != .open {
                let command = try FinderCommand(action: action, paths: Array(repeating: "/Volumes/share/a", count: 100))
                XCTAssertEqual(try FinderCommand(url: command.url()), command)
            }
        }
        XCTAssertThrowsError(try FinderCommand(action: .open, paths: ["/Volumes/share/a", "/Volumes/share/b"]))
    }

    func testRejectsNonVolumePathsTraversalAndControlCharacters() {
        let invalid = ["", "relative", "/Volumes", "/Volumes/", "/Volumes//", "/Volumes//share",
                       "/Volumes/share//file", "/Volumes/share/.", "/Volumes/share/../file", "/Volumes/../file",
                       "/Volumes/./file", "/Volumes/share/./file", "/Volumes/share/file//", "/volumes/share/a",
                       "/Users/name/a", "file:///Volumes/share/a", "file://remote/share/a", "smb://server/share/a",
                       "\\\\server\\share\\a", "R:\\a", "//Volumes/share/a", "/Volumes/share/line\nfile",
                       "/Volumes/share/\u{0}", "/Volumes/share/\t", "/Volumes/share/\u{7f}"]
        for path in invalid {
            XCTAssertThrowsError(try FinderCommand(action: .open, paths: [path]), path)
        }
    }

    func testRejectsInvalidURLStructureAndQuery() throws {
        let invalid = [
            "https://finder?action=open&path=/Volumes/share/a",
            "pathbridge://other?action=open&path=/Volumes/share/a",
            "pathbridge://finder/?action=open&path=/Volumes/share/a",
            "pathbridge://finder/open?action=open&path=/Volumes/share/a",
            "pathbridge://user@finder?action=open&path=/Volumes/share/a",
            "pathbridge://user:pass@finder?action=open&path=/Volumes/share/a",
            "pathbridge://finder:123?action=open&path=/Volumes/share/a",
            "pathbridge://finder?action=open&path=/Volumes/share/a#",
            "pathbridge://finder?action=open&path=/Volumes/share/a#fragment",
            "pathbridge://finder?action=delete&path=/Volumes/share/a",
            "pathbridge://finder?action=Open&path=/Volumes/share/a",
            "pathbridge://finder?action=open&action=open&path=/Volumes/share/a",
            "pathbridge://finder?action=open&%61ction=copyUNC&path=/Volumes/share/a",
            "pathbridge://finder?action=open&path=/Volumes/share/a&unknown=value",
            "pathbridge://finder?action&path=/Volumes/share/a",
            "pathbridge://finder?action=&path=/Volumes/share/a",
            "pathbridge://finder?action=open&path",
            "pathbridge://finder?action=open&path=",
            "pathbridge://finder?path=/Volumes/share/a",
            "pathbridge://finder?action=open",
            "pathbridge://finder",
            "pathbridge://finder?action=open&path=/Volumes/share/%2e%2e/file",
            "pathbridge://finder?action=open&path=/Volumes/share/%00file",
            "pathbridge://finder?action=open&path=smb%3A%2F%2Fserver%2Fshare",
            "pathbridge://finder?action=open&path=/Volumes/share/a&path=/Volumes/share/b"
        ]
        for string in invalid {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertThrowsError(try FinderCommand(url: url), string)
        }
        let relative = try XCTUnwrap(URL(string: "?action=open&path=/Volumes/share/a", relativeTo: URL(string: "pathbridge://finder")!))
        XCTAssertThrowsError(try FinderCommand(url: relative))
    }

    func testPercentEncodedFilenameIsDecodedExactlyOnce() throws {
        let url = try XCTUnwrap(URL(string: "pathbridge://finder?action=copyMacOS&path=%2FVolumes%2Fshare%2F%252e%252e%252Fname%253F"))
        let command = try FinderCommand(url: url)
        XCTAssertEqual(command.paths, ["/Volumes/share/%2e%2e%2Fname%3F"])
        XCTAssertEqual(try FinderCommand(url: command.url()), command)
    }

    func testURLSizeBoundaryUsesEncodedBytes() throws {
        let prefix = "pathbridge://finder?action=open&path=/Volumes/share/"
        let maximum = 128 * 1024
        let exact = prefix + String(repeating: "a", count: maximum - prefix.utf8.count)
        let command = try FinderCommand(url: XCTUnwrap(URL(string: exact)))
        XCTAssertEqual(try command.url().absoluteString.utf8.count, maximum)
        XCTAssertThrowsError(try FinderCommand(url: XCTUnwrap(URL(string: exact + "a"))))
        XCTAssertThrowsError(try FinderCommand(action: .open, paths: ["/Volumes/share/" + String(repeating: "a", count: maximum)]))
        // 中文的 URL 编码为九个 ASCII 字节，不能只检查原始字符数或 UTF-8 大小。
        XCTAssertThrowsError(try FinderCommand(action: .copySMB, paths: ["/Volumes/share/" + String(repeating: "中", count: 15_000)]))
    }
}
