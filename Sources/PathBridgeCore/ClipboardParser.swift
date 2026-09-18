import Foundation

/// Extracts one path from clipboard text without attempting natural-language parsing.
public enum ClipboardParser {
    public static func parse(_ text: String) throws -> String {
        guard !text.isEmpty else {
            throw PathResolverError.emptyInput
        }

        var value = text
        if value.first == "\u{FEFF}" {
            value.removeFirst()
        }

        guard !value.unicodeScalars.contains(where: {
            CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else {
            throw PathResolverError.invalidClipboardText
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw PathResolverError.emptyInput
        }

        if let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'")
        {
            value.removeFirst()
            value.removeLast()
            guard !value.isEmpty,
                  !value.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) else {
                throw PathResolverError.invalidClipboardText
            }
        } else if value.first == "\"" || value.first == "'" || value.last == "\"" || value.last == "'" {
            throw PathResolverError.invalidClipboardText
        }

        guard isPathLike(value) else {
            throw PathResolverError.invalidClipboardText
        }
        return value
    }

    private static func isPathLike(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("storage://") || lowercased.hasPrefix("smb://") || lowercased.hasPrefix("file://") {
            return true
        }
        if value.hasPrefix("/") || value.hasPrefix("\\\\") || value.hasPrefix("//") {
            return true
        }

        let scalars = Array(value.unicodeScalars)
        guard scalars.count >= 3,
              MappingValidator.isASCIIAlpha(scalars[0]),
              scalars[1] == ":",
              scalars[2] == "\\" || scalars[2] == "/" else {
            return false
        }
        return true
    }
}
