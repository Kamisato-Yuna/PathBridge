import Foundation

public struct PathResolver: Sendable {
    private let mappings: [StorageMapping]

    public init(mappings: [StorageMapping]) {
        self.mappings = mappings
    }

    /// 将包含服务器和共享的路径转换为 SMB URL，无需配置 Storage。
    public func smbURL(for input: String) throws -> URL {
        let text = try ClipboardParser.parse(input)
        let server: String
        let components: [String]
        if isUNCPath(text) {
            let pieces = try parseSeparatedComponents(String(text.dropFirst(2)), separators: ["\\", "/"], windowsSyntax: false)
            guard pieces.count >= 2 else { throw PathResolverError.malformedPath }
            server = pieces[0]
            components = Array(pieces.dropFirst())
            for component in components.dropFirst() { try validateWindowsComponent(component) }
        } else if hasURLScheme(text.lowercased(), "smb") || hasURLScheme(text.lowercased(), "file") {
            let scheme = hasURLScheme(text.lowercased(), "smb") ? "smb" : "file"
            let url = try parseURL(text, scheme: scheme)
            guard let host = url.host, !host.isEmpty,
                  scheme != "file" || host.lowercased() != "localhost" else {
                throw PathResolverError.networkLocationUnknown
            }
            server = host
            components = try decodedURLPathComponents(url.percentEncodedPath)
        } else {
            throw PathResolverError.networkLocationUnknown
        }
        guard let share = components.first else { throw PathResolverError.malformedPath }
        _ = try MappingValidator.validateServer(server)
        _ = try MappingValidator.validateShare(share)
        return try makeSMBURL(server: server, components: components)
    }

    private func makeSMBURL(server: String, components: [String]) throws -> URL {
        var url = URLComponents()
        url.scheme = "smb"
        url.host = MappingValidator.canonicalServer(server)
        url.percentEncodedPath = "/" + components.map(encodeStorageComponent).joined(separator: "/")
        guard let result = url.url else { throw PathResolverError.invalidURL }
        return result
    }

    /// Resolve a Windows, UNC, mounted macOS, SMB/file URL, or storage URL path.
    public func resolve(_ input: String) throws -> ResolvedPath {
        let parsedInput = try ClipboardParser.parse(input)
        let validated = try MappingValidator.validatedMappings(mappings)
        let lowercased = parsedInput.lowercased()

        if hasURLScheme(lowercased, "storage") {
            return try resolveStorageURL(parsedInput, mappings: validated)
        }
        if hasURLScheme(lowercased, "smb") {
            return try resolveSMBURL(parsedInput, mappings: validated)
        }
        if hasURLScheme(lowercased, "file") {
            return try resolveFileURL(parsedInput, mappings: validated)
        }
        if isDrivePath(parsedInput) {
            return try resolveDrivePath(parsedInput, mappings: validated)
        }
        if isUNCPath(parsedInput) {
            return try resolveUNCPath(parsedInput, mappings: validated)
        }
        if parsedInput.hasPrefix("/") {
            return try resolveMacPath(parsedInput, mappings: validated)
        }
        throw PathResolverError.unsupportedPathFormat
    }

    /// Render a resolved storage path in a user-facing path format.
    public func render(_ path: ResolvedPath, as format: PathFormat) throws -> String {
        let validated = try MappingValidator.validatedMappings(mappings)
        guard let storage = findStorage(path.storageID, in: validated) else {
            throw PathResolverError.mappingNotFound(path.storageID)
        }
        let components = try validateResolvedComponents(
            path.components,
            windowsSyntax: format == .windowsDrive || format == .unc
        )

        switch format {
        case .macOS:
            return joinPOSIX(storage.canonicalMountPath, components)
        case .windowsDrive:
            guard let drive = storage.canonicalDrive else {
                throw PathResolverError.missingWindowsDrive(storage.mapping.id)
            }
            return joinWindows("\(drive)\\", components)
        case .unc:
            var root = "\\\\\(storage.mapping.server)\\\(storage.mapping.share)"
            if !storage.subpathComponents.isEmpty {
                root += "\\" + storage.subpathComponents.joined(separator: "\\")
            }
            return joinWindows(root, components)
        case .storage:
            let root = "storage://\(storage.mapping.id)"
            guard !components.isEmpty else { return root }
            return root + "/" + components.map(encodeStorageComponent).joined(separator: "/")
        case .smb:
            return try makeSMBURL(server: storage.mapping.server,
                components: [storage.mapping.share] + storage.subpathComponents + components).absoluteString
        }
    }

    private func resolveDrivePath(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let scalars = Array(input.unicodeScalars)
        guard scalars.count >= 3 else { throw PathResolverError.malformedPath }
        let drive = String(scalars[0...1].map { Character(String($0)) }).uppercased()
        guard scalars[2] == "\\" || scalars[2] == "/" else {
            throw PathResolverError.malformedPath
        }
        guard let storage = mappings.first(where: { $0.canonicalDrive == drive }) else {
            throw PathResolverError.mappingNotFound(drive)
        }
        let body = String(input.dropFirst(3))
        let components = try parseSeparatedComponents(body, separators: ["\\", "/"], windowsSyntax: true)
        return ResolvedPath(storageID: storage.mapping.id, components: components)
    }

    private func resolveUNCPath(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let body: String
        if input.hasPrefix("\\\\") {
            body = String(input.dropFirst(2))
        } else if input.hasPrefix("//") {
            body = String(input.dropFirst(2))
        } else {
            throw PathResolverError.malformedPath
        }

        let pieces = try parseSeparatedComponents(body, separators: ["\\", "/"], windowsSyntax: false)
        guard pieces.count >= 2 else { throw PathResolverError.malformedPath }
        for component in pieces.dropFirst(2) {
            try validateComponent(component, windowsSyntax: true)
        }
        let server = pieces[0]
        let share = pieces[1]
        let relative = Array(pieces.dropFirst(2))
        guard let storage = longestSMBMapping(
            server: server,
            share: share,
            path: relative,
            mappings: mappings
        ) else {
            throw PathResolverError.mappingNotFound("\\\\\(server)\\\(share)")
        }
        return ResolvedPath(
            storageID: storage.mapping.id,
            components: Array(relative.dropFirst(storage.subpathComponents.count))
        )
    }

    private func resolveMacPath(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let pathComponents = try parseSeparatedComponents(String(input.dropFirst()), separators: ["/"], windowsSyntax: false)
        let normalizedInput = "/" + pathComponents.joined(separator: "/")

        // Sort by length so this remains correct if a future configuration permits nested mounts.
        let candidates = mappings.sorted { $0.canonicalMountPath.count > $1.canonicalMountPath.count }
        for storage in candidates {
            let mount = storage.canonicalMountPath
            if normalizedInput == mount {
                return ResolvedPath(storageID: storage.mapping.id, components: [])
            }
            let prefix = mount + "/"
            if normalizedInput.hasPrefix(prefix) {
                let relative = String(normalizedInput.dropFirst(prefix.count))
                let components = try parseSeparatedComponents(relative, separators: ["/"], windowsSyntax: false)
                return ResolvedPath(storageID: storage.mapping.id, components: components)
            }
        }
        throw PathResolverError.mappingNotFound(input)
    }

    private func resolveStorageURL(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let url = try parseURL(input, scheme: "storage")
        guard let host = url.host, !host.isEmpty else { throw PathResolverError.invalidURL }
        guard let storage = findStorage(host, in: mappings) else {
            throw PathResolverError.mappingNotFound(host)
        }
        let components = try decodedURLPathComponents(url.percentEncodedPath)
        return ResolvedPath(storageID: storage.mapping.id, components: components)
    }

    private func resolveSMBURL(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let url = try parseURL(input, scheme: "smb")
        guard let host = url.host, !host.isEmpty else { throw PathResolverError.invalidURL }
        let pieces = try decodedURLPathComponents(url.percentEncodedPath)
        guard let share = pieces.first else { throw PathResolverError.malformedPath }
        let relative = Array(pieces.dropFirst())
        guard let storage = longestSMBMapping(
            server: host,
            share: share,
            path: relative,
            mappings: mappings
        ) else {
            throw PathResolverError.mappingNotFound("smb://\(host)/\(share)")
        }
        return ResolvedPath(
            storageID: storage.mapping.id,
            components: Array(relative.dropFirst(storage.subpathComponents.count))
        )
    }

    private func resolveFileURL(_ input: String, mappings: [ValidatedStorageMapping]) throws -> ResolvedPath {
        let url = try parseURL(input, scheme: "file")
        let pieces = try decodedURLPathComponents(url.percentEncodedPath)
        if let host = url.host, !host.isEmpty, host.lowercased() != "localhost" {
            guard let share = pieces.first else { throw PathResolverError.malformedPath }
            guard let storage = longestSMBMapping(
                server: host,
                share: share,
                path: Array(pieces.dropFirst()),
                mappings: mappings
            ) else {
                throw PathResolverError.mappingNotFound("file://\(host)/\(share)")
            }
            let relative = Array(pieces.dropFirst())
            return ResolvedPath(
                storageID: storage.mapping.id,
                components: Array(relative.dropFirst(storage.subpathComponents.count))
            )
        }

        let path = "/" + pieces.joined(separator: "/")
        return try resolveMacPath(path, mappings: mappings)
    }

    private func parseURL(_ input: String, scheme: String) throws -> URLComponents {
        // Foundation can re-escape existing %XX sequences when a URL also
        // contains raw Unicode. Encode only characters outside URL syntax first.
        let syntax = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
        guard let encoded = input.addingPercentEncoding(withAllowedCharacters: syntax),
              let url = URLComponents(string: encoded, encodingInvalidCharacters: false),
              url.scheme?.lowercased() == scheme,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            throw PathResolverError.invalidURL
        }
        // A malformed percent escape can otherwise be silently retained by URLComponents.
        guard url.percentEncodedPath.removingPercentEncoding != nil else {
            throw PathResolverError.invalidURL
        }
        return url
    }

    private func decodedURLPathComponents(_ path: String) throws -> [String] {
        guard path.isEmpty || path.hasPrefix("/") else { throw PathResolverError.invalidURL }
        let body = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return try parseURLSeparatedComponents(body)
    }

    private func parseURLSeparatedComponents(_ body: String) throws -> [String] {
        if body.isEmpty { return [] }
        var pieces = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
        // A trailing slash is a normal representation of a directory URL.
        if pieces.last == "" {
            pieces.removeLast()
        }
        guard !pieces.contains(where: { $0.isEmpty }) else { throw PathResolverError.malformedPath }

        var result: [String] = []
        result.reserveCapacity(pieces.count)
        for piece in pieces {
            guard let decoded = String(piece).removingPercentEncoding else {
                throw PathResolverError.invalidURL
            }
            guard !decoded.contains("/") && !decoded.contains("\\") else {
                throw PathResolverError.invalidComponent(decoded)
            }
            try validateComponent(decoded, windowsSyntax: false)
            result.append(decoded)
        }
        return result
    }

    private func parseSeparatedComponents(
        _ body: String,
        separators: Set<Character>,
        windowsSyntax: Bool
    ) throws -> [String] {
        if body.isEmpty { return [] }
        let pieces = body.split(omittingEmptySubsequences: false, whereSeparator: { separators.contains($0) })
        var result = pieces.map(String.init)
        if result.last == "" { result.removeLast() }
        guard !result.contains(where: { $0.isEmpty }) else { throw PathResolverError.malformedPath }
        for component in result {
            try validateComponent(component, windowsSyntax: windowsSyntax)
        }
        return result
    }

    private func validateResolvedComponents(
        _ components: [String],
        windowsSyntax: Bool
    ) throws -> [String] {
        guard !components.contains(where: { $0.isEmpty }) else { throw PathResolverError.invalidResolvedPath }
        for component in components {
            try validateComponent(component, windowsSyntax: windowsSyntax)
        }
        return components
    }

    private func validateComponent(_ component: String, windowsSyntax: Bool) throws {
        guard !component.isEmpty else { throw PathResolverError.invalidComponent(component) }
        if component == ".." { throw PathResolverError.pathTraversal }
        if component == "." { throw PathResolverError.invalidComponent(component) }
        guard !component.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !component.contains("/"),
              !component.contains("\\") else {
            throw PathResolverError.invalidComponent(component)
        }
        if windowsSyntax {
            try validateWindowsComponent(component)
        }
    }

    private func validateWindowsComponent(_ component: String) throws {
        let invalidCharacters = CharacterSet(charactersIn: "<>:\"/\\|?*")
        guard !component.unicodeScalars.contains(where: { invalidCharacters.contains($0) }),
              !component.hasSuffix(" "),
              !component.hasSuffix(".") else {
            throw PathResolverError.invalidWindowsComponent(component)
        }
        let base = component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first?.uppercased() ?? ""
        let reserved: Set<String> = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
        guard !reserved.contains(base) else {
            throw PathResolverError.invalidWindowsComponent(component)
        }
    }

    private func findStorage(_ id: String, in mappings: [ValidatedStorageMapping]) -> ValidatedStorageMapping? {
        mappings.first { $0.canonicalID == id.lowercased() }
    }

    private func longestSMBMapping(
        server: String,
        share: String,
        path: [String],
        mappings: [ValidatedStorageMapping]
    ) -> ValidatedStorageMapping? {
        let canonicalServer = MappingValidator.canonicalServer(server)
        let canonicalShare = share.lowercased()
        return mappings
            .filter {
                $0.canonicalServer == canonicalServer
                    && $0.canonicalShare == canonicalShare
                    && pathHasPrefix(path, $0.subpathComponents)
            }
            .max { lhs, rhs in
                lhs.subpathComponents.count < rhs.subpathComponents.count
            }
    }

    private func pathHasPrefix(_ path: [String], _ prefix: [String]) -> Bool {
        guard prefix.count <= path.count else { return false }
        return zip(path, prefix).allSatisfy { $0.0.lowercased() == $0.1.lowercased() }
    }

    private func isDrivePath(_ input: String) -> Bool {
        let scalars = Array(input.unicodeScalars)
        return scalars.count >= 3
            && MappingValidator.isASCIIAlpha(scalars[0])
            && scalars[1] == ":"
            && (scalars[2] == "\\" || scalars[2] == "/")
    }

    private func isUNCPath(_ input: String) -> Bool {
        input.hasPrefix("\\\\") || input.hasPrefix("//")
    }

    private func hasURLScheme(_ input: String, _ scheme: String) -> Bool {
        input.hasPrefix("\(scheme)://")
    }

    private func joinPOSIX(_ root: String, _ components: [String]) -> String {
        guard !components.isEmpty else { return root }
        return root + "/" + components.joined(separator: "/")
    }

    private func joinWindows(_ root: String, _ components: [String]) -> String {
        guard !components.isEmpty else { return root }
        if root.hasSuffix("\\") {
            return root + components.joined(separator: "\\")
        }
        return root + "\\" + components.joined(separator: "\\")
    }

    private func encodeStorageComponent(_ component: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
