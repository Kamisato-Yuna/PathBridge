import Foundation
import XCTest
@testable import PathBridgeCore

final class PathBridgeCoreTests: XCTestCase {
    func testUnmappedUNCBecomesSMBWithoutLosingLiteralCharacters() throws {
        let resolver = PathResolver(mappings: [])
        let input = #""\\other-server\共享 #100%\中文 空格\a%20.hip""#
        let url = try resolver.smbURL(for: input)
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.host, "other-server")
        XCTAssertEqual(url.path, "/共享 #100%/中文 空格/a%20.hip")
        XCTAssertTrue(url.absoluteString.contains("%2520.hip"))
        XCTAssertEqual(try resolver.smbURL(for: "//other-server/share/").absoluteString, "smb://other-server/share")
    }

    func testUnmappedSMBAndRemoteFileURLsDecodeOnce() throws {
        let resolver = PathResolver(mappings: [])
        for scheme in ["smb", "file"] {
            let url = try resolver.smbURL(for: "\(scheme)://server/share/中文%20项目/a%2520.hip")
            XCTAssertEqual(url.absoluteString, "smb://server/share/%E4%B8%AD%E6%96%87%20%E9%A1%B9%E7%9B%AE/a%2520.hip")
        }
    }

    func testUnmappedPathsDoNotInventServerOrBypassValidation() throws {
        let resolver = PathResolver(mappings: [])
        for input in [#"R:\Project"#, "/Volumes/unknown/Project", "storage://unknown/Project", "file:///Volumes/unknown/Project"] {
            XCTAssertThrowsError(try resolver.smbURL(for: input)) { error in
                XCTAssertEqual(error as? PathResolverError, .networkLocationUnknown)
            }
        }
        for input in [#"\\server\share\..\secret"#, #"\\user@server\share\file"#,
                      "smb://user:secret@server/share", "smb://server/share/a%2Fb",
                      "smb://server/share/a%ZZ", "smb://server/share/a?query=1",
                      "https://server/share", #"\\server"#] {
            XCTAssertThrowsError(try resolver.smbURL(for: input), input)
        }
    }

    func testConfiguredSMBRenderingKeepsStorageSubdirectory() throws {
        let mapping = StorageMapping(id: "render", name: "Render", windowsDrive: "R:", server: "server",
            share: "production", mountPath: "/Volumes/production/RenderOutput", subpath: "RenderOutput")
        let resolver = PathResolver(mappings: [mapping])
        let resolved = try resolver.resolve(#"R:\shot one\a.hip"#)
        XCTAssertEqual(try resolver.render(resolved, as: .smb), "smb://server/production/RenderOutput/shot%20one/a.hip")
        XCTAssertThrowsError(try resolver.resolve(#"\\other-server\production\a.hip"#))
        XCTAssertEqual(try resolver.smbURL(for: #"\\other-server\production\a.hip"#).host, "other-server")
    }

    private let share = StorageMapping(
        id: "share",
        name: "Shared files",
        windowsDrive: "O:",
        server: "files.example.com",
        share: "share",
        mountPath: "/Volumes/share"
    )

    func testDriveUNCAndMacRoundTrip() throws {
        let resolver = PathResolver(mappings: [share])
        let expected = ResolvedPath(storageID: "share", components: ["Project", "file.hip"])

        XCTAssertEqual(try resolver.resolve(#"O:\Project\file.hip"#), expected)
        XCTAssertEqual(try resolver.resolve(#"\\FILES.EXAMPLE.COM\SHARE\Project\file.hip"#), expected)
        XCTAssertEqual(try resolver.resolve("/Volumes/share/Project/file.hip"), expected)
        XCTAssertEqual(try resolver.render(expected, as: .macOS), "/Volumes/share/Project/file.hip")
        XCTAssertEqual(try resolver.render(expected, as: .windowsDrive), #"O:\Project\file.hip"#)
        XCTAssertEqual(try resolver.render(expected, as: .unc), "\\\\files.example.com\\share\\Project\\file.hip")
    }

    func testUNCAndSMBSubpathUseLongestPrefix() throws {
        let root = StorageMapping(
            id: "all",
            name: "All",
            windowsDrive: "O:",
            server: "files.example.com",
            share: "Production",
            mountPath: "/Volumes/Production"
        )
        let render = StorageMapping(
            id: "render-output",
            name: "Render output",
            server: "files.example.com",
            share: "Production",
            mountPath: "/Volumes/Production/RenderOutput",
            subpath: "RenderOutput"
        )
        let resolver = PathResolver(mappings: [root, render])

        XCTAssertEqual(
            try resolver.resolve(#"\\files.example.com\Production\RenderOutput\shot\image.exr"#),
            ResolvedPath(storageID: "render-output", components: ["shot", "image.exr"])
        )
        XCTAssertEqual(
            try resolver.resolve("smb://files.example.com/Production/RenderOutput/shot/image.exr"),
            ResolvedPath(storageID: "render-output", components: ["shot", "image.exr"])
        )
        XCTAssertEqual(
            try resolver.resolve("/Volumes/Production/RenderOutput/shot/image.exr"),
            ResolvedPath(storageID: "render-output", components: ["shot", "image.exr"])
        )
        XCTAssertEqual(
            try resolver.resolve(#"\\files.example.com\Production\Editorial\cut.hip"#),
            ResolvedPath(storageID: "all", components: ["Editorial", "cut.hip"])
        )
        XCTAssertEqual(
            try resolver.render(ResolvedPath(storageID: "render-output", components: ["shot"]), as: .unc),
            "\\\\files.example.com\\Production\\RenderOutput\\shot"
        )
    }

    func testURLsDecodeOnlyURLPercentEscapes() throws {
        let resolver = PathResolver(mappings: [share])
        XCTAssertEqual(
            try resolver.resolve("smb://files.example.com/share/Project%20%E4%B8%AD%E6%96%87.hip"),
            ResolvedPath(storageID: "share", components: ["Project 中文.hip"])
        )
        XCTAssertEqual(try resolver.resolve("smb://files.example.com/share/"), ResolvedPath(storageID: "share", components: []))
        XCTAssertEqual(
            try resolver.resolve("file:///Volumes/share/Project%20%E4%B8%AD%E6%96%87.hip"),
            ResolvedPath(storageID: "share", components: ["Project 中文.hip"])
        )
        XCTAssertEqual(try resolver.resolve("file:///Volumes/share/"), ResolvedPath(storageID: "share", components: []))
        XCTAssertEqual(
            try resolver.resolve("storage://share/Project%20%E4%B8%AD%E6%96%87.hip"),
            ResolvedPath(storageID: "share", components: ["Project 中文.hip"])
        )
        XCTAssertEqual(
            try resolver.resolve("/Volumes/share/Project%20%E4%B8%AD%E6%96%87.hip"),
            ResolvedPath(storageID: "share", components: ["Project%20%E4%B8%AD%E6%96%87.hip"])
        )
        XCTAssertEqual(
            try resolver.render(ResolvedPath(storageID: "share", components: ["Project 中文.hip"]), as: .storage),
            "storage://share/Project%20%E4%B8%AD%E6%96%87.hip"
        )
    }

    func testClipboardParserAcceptsQuotesAndRejectsProse() throws {
        XCTAssertEqual(try ClipboardParser.parse(#"  "O:\Project\file.hip"  "#), #"O:\Project\file.hip"#)
        XCTAssertEqual(try ClipboardParser.parse("'/Volumes/share/中文 文件.hip'"), "/Volumes/share/中文 文件.hip")
        XCTAssertThrowsError(try ClipboardParser.parse("O:\\Project\\file.hip\nnext"))
        XCTAssertThrowsError(try ClipboardParser.parse("Please open O:\\Project\\file.hip"))
        XCTAssertThrowsError(try ClipboardParser.parse("https://example.com/file"))
    }

    func testClipboardCandidatesExtractNaturalLanguagePathsInOrder() throws {
        let text = #"""
        请打开 \\files.example.com\共享目录\镜头 一\最终 文件.hip，然后查看 smb://files.example.com/share/Project%20%E4%B8%AD%E6%96%87.hip；最后打开 /Volumes/share/中文 项目/shot 01.hip。
        下一行是 file:///Volumes/share/文件%20二.hip 和 storage://share/项目%20三。
        """#

        XCTAssertEqual(
            try ClipboardParser.candidates(in: text),
            [
                #"\\files.example.com\共享目录\镜头 一\最终 文件.hip"#,
                "smb://files.example.com/share/Project%20%E4%B8%AD%E6%96%87.hip",
                "/Volumes/share/中文 项目/shot 01.hip",
                "file:///Volumes/share/文件%20二.hip",
                "storage://share/项目%20三"
            ]
        )
    }

    func testClipboardCandidatesSupportQuotesAdjacentSymbolsAndDeduplicate() throws {
        let text = #"【'/Volumes/共享目录/镜头 01/最终 文件.hip'】、("C:\Project\shot one.hip")；'/Volumes/共享目录/镜头 01/最终 文件.hip'。"#

        XCTAssertEqual(
            try ClipboardParser.candidates(in: text),
            [
                "/Volumes/共享目录/镜头 01/最终 文件.hip",
                #"C:\Project\shot one.hip"#
            ]
        )
    }

    func testClipboardCandidatesKeepPunctuationInsideQuotes() throws {
        XCTAssertEqual(
            try ClipboardParser.candidates(in: #""/Volumes/share/shot;v2 (final).hip""#),
            ["/Volumes/share/shot;v2 (final).hip"]
        )
    }

    func testClipboardCandidatesKeepAmbiguousUnquotedSpacesIntact() throws {
        XCTAssertEqual(
            try ClipboardParser.candidates(in: "请打开 /Volumes/share/项目 文件/shot 01.hip 之后确认"),
            ["/Volumes/share/项目 文件/shot 01.hip 之后确认"]
        )
    }

    func testClipboardCandidatesPreserveSinglePathPunctuationAndSeparateMultipleRoots() throws {
        let completePath = #"/Volumes/share/foo,bar (final).hip?draft"#
        XCTAssertEqual(try ClipboardParser.candidates(in: completePath), [completePath])
        XCTAssertEqual(
            try ClipboardParser.candidates(in: "请处理 /Volumes/share/foo,bar.hip 和 /Volumes/share/next.hip"),
            ["/Volumes/share/foo,bar.hip", "/Volumes/share/next.hip"]
        )
        XCTAssertEqual(
            try ClipboardParser.candidates(in: "smb://server/share/file?download=1"),
            ["smb://server/share/file?download=1"]
        )
        XCTAssertThrowsError(try ClipboardParser.candidates(in: "https://example.com/a")) { error in
            XCTAssertEqual(error as? PathResolverError, .invalidClipboardText)
        }
    }

    func testClipboardCandidatesRejectNoCandidateAndPreserveCompletePath() throws {
        XCTAssertEqual(
            try ClipboardParser.candidates(in: #"/Volumes/share/中文 文件.hip"#),
            [#"/Volumes/share/中文 文件.hip"#]
        )
        XCTAssertThrowsError(try ClipboardParser.candidates(in: "请打开网页 https://example.com/file")) { error in
            XCTAssertEqual(error as? PathResolverError, .invalidClipboardText)
        }
        XCTAssertThrowsError(try ClipboardParser.candidates(in: "   \n\t  ")) { error in
            XCTAssertEqual(error as? PathResolverError, .emptyInput)
        }
    }

    func testMappingValidationRejectsAmbiguityAndUnsafeRoots() {
        XCTAssertThrowsError(try MappingValidator.validate([share, share]))
        XCTAssertThrowsError(try MappingValidator.validate([
            share,
            StorageMapping(id: "other", name: "Other", windowsDrive: "o:", server: "other", share: "x", mountPath: "/Volumes/other")
        ]))
        XCTAssertThrowsError(try MappingValidator.validate([
            share,
            StorageMapping(id: "other", name: "Other", server: "files.example.com", share: "share", mountPath: "/Volumes/other")
        ]))
        XCTAssertThrowsError(try MappingValidator.validate([
            StorageMapping(id: "bad", name: "Bad", server: "files.example.com", share: "share", mountPath: "/tmp/share")
        ]))
        XCTAssertThrowsError(try MappingValidator.validate([
            StorageMapping(id: "bad", name: "Bad", server: "files.example.com", share: "share", mountPath: "/Volumes/a/b/../c")
        ]))
        XCTAssertThrowsError(try MappingValidator.validate([
            StorageMapping(id: "bad", name: "Bad", server: "files.example.com", share: "share", mountPath: "/Volumes/share", subpath: "Render/../Output")
        ]))
    }

    func testBoundariesTraversalAndWindowsRepresentation() throws {
        let share2 = StorageMapping(
            id: "share-two",
            name: "Share two",
            windowsDrive: "P:",
            server: "files.example.com",
            share: "share2",
            mountPath: "/Volumes/share2"
        )
        let resolver = PathResolver(mappings: [share, share2])
        XCTAssertThrowsError(try resolver.resolve("/Volumes/share2x/file"))
        XCTAssertThrowsError(try resolver.resolve(#"O:\Project\..\secret"#))
        XCTAssertThrowsError(try resolver.resolve(#"O:\bad:name"#))
        XCTAssertThrowsError(try resolver.render(ResolvedPath(storageID: "share", components: ["bad:name"]), as: .windowsDrive))
        XCTAssertThrowsError(try resolver.render(ResolvedPath(storageID: "share", components: [".."]), as: .macOS))
    }

    func testSMBURLRejectsCredentialsQueriesAndEncodedSeparators() throws {
        let resolver = PathResolver(mappings: [share])
        XCTAssertThrowsError(try resolver.resolve("smb://user:secret@files.example.com/share/file"))
        XCTAssertThrowsError(try resolver.resolve("smb://files.example.com/share/file?download=1"))
        XCTAssertThrowsError(try resolver.resolve("smb://files.example.com/share/a%2Fb"))
        XCTAssertThrowsError(try resolver.resolve("smb://files.example.com/share/a%ZZ"))
    }

    func testStorageMappingDecodesLegacyConfigWithoutSubpath() throws {
        let data = Data(#"{"id":"share","name":"Shared files","windowsDrive":"O:","server":"files.example.com","share":"share","mountPath":"/Volumes/share"}"#.utf8)
        let mapping = try JSONDecoder().decode(StorageMapping.self, from: data)
        XCTAssertEqual(mapping.subpath, "")
        XCTAssertEqual(mapping, share)
    }

    func testSharedSubdirectoryDriveAndEscapedShareName() throws {
        let mapping = StorageMapping(id: "render", name: "渲染", windowsDrive: "R:", server: "files.example.com",
            share: "共享 #100%", mountPath: "/Volumes/共享 #100%/RenderOutput", subpath: "RenderOutput")
        let resolver = PathResolver(mappings: [mapping])
        let path = try resolver.resolve(#"R:\镜头 一\v%20.exr"#)
        XCTAssertEqual(try resolver.render(path, as: .macOS), "/Volumes/共享 #100%/RenderOutput/镜头 一/v%20.exr")
        XCTAssertEqual(try resolver.resolve(resolver.render(path, as: .unc)), path)
        XCTAssertEqual(try resolver.resolve(resolver.render(path, as: .storage)), path)
        XCTAssertEqual(try resolver.resolve("smb://files.example.com/%E5%85%B1%E4%BA%AB%20%23100%25/RenderOutput/镜头%20一/v%2520.exr"), path)
    }
}
