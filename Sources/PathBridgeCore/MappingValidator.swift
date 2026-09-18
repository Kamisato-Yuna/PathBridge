import Foundation

/// Internal canonical form used by the resolver after validation.
internal struct ValidatedStorageMapping: Sendable {
    internal let mapping: StorageMapping
    internal let canonicalID: String
    internal let canonicalDrive: String?
    internal let canonicalServer: String
    internal let canonicalShare: String
    internal let canonicalSubpath: String
    internal let subpathComponents: [String]
    internal let canonicalMountPath: String

    internal var uncKey: String {
        if canonicalSubpath.isEmpty {
            return "\(canonicalServer)/\(canonicalShare)"
        }
        return "\(canonicalServer)/\(canonicalShare)/\(canonicalSubpath)"
    }
}

public enum MappingValidator {
    /// Validate every mapping and reject ambiguous IDs, drives, UNC roots, or mount paths.
    public static func validate(_ mappings: [StorageMapping]) throws {
        _ = try validatedMappings(mappings)
    }

    internal static func validatedMappings(_ mappings: [StorageMapping]) throws -> [ValidatedStorageMapping] {
        var ids = Set<String>()
        var drives = Set<String>()
        var uncRoots = Set<String>()
        var mountPaths = Set<String>()
        var result: [ValidatedStorageMapping] = []
        result.reserveCapacity(mappings.count)

        for mapping in mappings {
            let canonicalID = try validateID(mapping.id)
            guard ids.insert(canonicalID).inserted else {
                throw PathResolverError.duplicateMapping("id \(mapping.id)")
            }

            guard !mapping.name.isEmpty,
                  !mapping.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw PathResolverError.invalidMapping("name")
            }

            let canonicalDrive = try validateDrive(mapping.windowsDrive)
            if let canonicalDrive {
                guard drives.insert(canonicalDrive).inserted else {
                    throw PathResolverError.duplicateMapping("windowsDrive \(mapping.windowsDrive ?? "")")
                }
            }

            let canonicalServer = try validateServer(mapping.server)
            let canonicalShare = try validateShare(mapping.share)
            let (canonicalSubpath, subpathComponents) = try validateSubpath(mapping.subpath)
            let uncKey = canonicalSubpath.isEmpty
                ? "\(canonicalServer)/\(canonicalShare)"
                : "\(canonicalServer)/\(canonicalShare)/\(canonicalSubpath)"
            guard uncRoots.insert(uncKey).inserted else {
                let uncPrefix = String(repeating: "\\", count: 2) + mapping.server + "\\" + mapping.share
                throw PathResolverError.duplicateMapping("UNC \(uncPrefix)")
            }

            let canonicalMountPath = try validateMountPath(mapping.mountPath)
            guard mountPaths.insert(canonicalMountPath.lowercased()).inserted else {
                throw PathResolverError.duplicateMapping("mountPath \(mapping.mountPath)")
            }

            result.append(
                ValidatedStorageMapping(
                    mapping: mapping,
                    canonicalID: canonicalID,
                    canonicalDrive: canonicalDrive,
                    canonicalServer: canonicalServer,
                    canonicalShare: canonicalShare,
                    canonicalSubpath: canonicalSubpath,
                    subpathComponents: subpathComponents,
                    canonicalMountPath: canonicalMountPath
                )
            )
        }

        return result
    }

    internal static func validateID(_ id: String) throws -> String {
        guard !id.isEmpty else {
            throw PathResolverError.invalidMapping("id is empty")
        }

        let scalars = Array(id.unicodeScalars)
        guard let first = scalars.first,
              isASCIIAlphaNumeric(first),
              let last = scalars.last,
              isASCIIAlphaNumeric(last),
              scalars.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == "-" || $0 == "_" || $0 == "." }) else {
            throw PathResolverError.invalidMapping("id \(id) is not a URL host")
        }

        // A host made entirely of dots is not useful and can be interpreted inconsistently.
        guard scalars.contains(where: { isASCIIAlphaNumeric($0) }) else {
            throw PathResolverError.invalidMapping("id \(id) is not a URL host")
        }
        return id.lowercased()
    }

    internal static func validateDrive(_ drive: String?) throws -> String? {
        guard let drive else { return nil }
        let scalars = Array(drive.unicodeScalars)
        guard scalars.count == 2,
              isASCIIAlpha(scalars[0]),
              scalars[1] == ":" else {
            throw PathResolverError.invalidMapping("windowsDrive \(drive)")
        }
        return drive.uppercased()
    }

    internal static func validateServer(_ server: String) throws -> String {
        guard !server.isEmpty,
              !server.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !server.contains(where: { "/\\?%@#".contains($0) }) else {
            throw PathResolverError.invalidMapping("server \(server)")
        }

        if server.hasPrefix("[") || server.hasSuffix("]") {
            guard server.first == "[", server.last == "]", server.count > 2 else {
                throw PathResolverError.invalidMapping("server \(server)")
            }
            let inner = String(server.dropFirst().dropLast())
            guard isIPv6Like(inner) else {
                throw PathResolverError.invalidMapping("server \(server)")
            }
        } else if server.contains(":") {
            // Accept an unbracketed IPv6 value in configuration and canonicalize it for matching.
            guard isIPv6Like(server) else {
                throw PathResolverError.invalidMapping("server \(server)")
            }
        }

        return canonicalServer(server)
    }

    internal static func validateShare(_ share: String) throws -> String {
        guard !share.isEmpty,
              !share.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !share.contains(where: { "/\\?<>:\"|?*".contains($0) }),
              !share.hasSuffix(" "),
              !share.hasSuffix("."),
              share != ".",
              share != ".." else {
            throw PathResolverError.invalidMapping("share \(share)")
        }
        return share.lowercased()
    }

    internal static func validateMountPath(_ mountPath: String) throws -> String {
        guard mountPath.hasPrefix("/Volumes/") else {
            throw PathResolverError.invalidMapping("mountPath must be an absolute /Volumes/name path")
        }

        var suffix = String(mountPath.dropFirst("/Volumes/".count))
        if suffix.hasSuffix("/") {
            suffix.removeLast()
        }

        guard !suffix.isEmpty else {
            throw PathResolverError.invalidMapping("mountPath must be an absolute /Volumes path")
        }

        let components = suffix.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty }) else {
            throw PathResolverError.invalidMapping("mountPath contains an empty component")
        }
        for component in components {
            let value = String(component)
            guard value != ".", value != "..",
                  !value.contains("\\"),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw PathResolverError.invalidMapping("mountPath contains an invalid component")
            }
        }
        return "/Volumes/\(components.map(String.init).joined(separator: "/"))"
    }

    internal static func validateSubpath(_ subpath: String) throws -> (String, [String]) {
        guard !subpath.isEmpty else { return ("", []) }
        var normalizedInput = subpath
        if normalizedInput.hasSuffix("/") {
            normalizedInput.removeLast()
        }
        guard !normalizedInput.hasPrefix("/"),
              !normalizedInput.hasSuffix("/"),
              !normalizedInput.contains("\\") else {
            throw PathResolverError.invalidMapping("subpath must be relative and use /")
        }
        let components = normalizedInput.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty }) else {
            throw PathResolverError.invalidMapping("subpath contains an empty component")
        }
        var values: [String] = []
        values.reserveCapacity(components.count)
        for component in components {
            let value = String(component)
            guard value != "." else {
                throw PathResolverError.invalidMapping("subpath contains .")
            }
            if value == ".." {
                throw PathResolverError.pathTraversal
            }
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !value.contains("/"),
                  !value.contains(where: { "<>:\"|?*".contains($0) }),
                  !value.hasSuffix(" "),
                  !value.hasSuffix(".") else {
                throw PathResolverError.invalidMapping("subpath contains an invalid component")
            }
            values.append(value)
        }
        return (values.map { $0.lowercased() }.joined(separator: "/"), values)
    }

    internal static func canonicalServer(_ server: String) -> String {
        let lower = server.lowercased()
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            return lower
        }
        if isIPv6Like(server) {
            return "[\(lower)]"
        }
        return lower
    }

    internal static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    internal static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIAlpha(scalar) || (scalar.value >= 48 && scalar.value <= 57)
    }

    internal static func isIPv6Like(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && value.contains(":")
    }
}
