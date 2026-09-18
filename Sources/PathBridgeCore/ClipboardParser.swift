import Foundation

/// Extracts paths from clipboard text.
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

    /// Extracts path-like values from natural-language clipboard text.
    ///
    /// The returned values retain their spelling, including URL percent escapes
    /// and spaces inside a path. Extraction ends at quotes, line boundaries,
    /// clear sentence punctuation, or another path root. An unquoted path and
    /// trailing prose separated only by spaces are intentionally kept together:
    /// there is no reliable way to tell prose from a legal filename component.
    /// Use quotes when that distinction matters.
    public static func candidates(in text: String) throws -> [String] {
        guard !text.isEmpty else {
            throw PathResolverError.emptyInput
        }

        var value = text
        if value.first == "\u{FEFF}" {
            value.removeFirst()
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PathResolverError.emptyInput
        }

        let characters = Array(value)
        if pathRootCount(in: characters) == 1, let completePath = try? parse(text) {
            // Preserve the existing single-path contract, including legal
            // punctuation such as commas, parentheses, and URL query marks.
            // Count roots first so two paths on one line cannot be swallowed as
            // one permissive single-path value.
            return [completePath]
        }

        var result: [String] = []
        var seen = Set<String>()
        var cursor = 0

        while cursor < characters.count {
            guard let root = pathRoot(at: cursor, in: characters) else {
                cursor += 1
                continue
            }

            let extraction = extractCandidate(
                from: cursor,
                root: root,
                in: characters
            )
            if let candidate = extraction.value, !candidate.isEmpty, seen.insert(candidate).inserted {
                result.append(candidate)
            }

            // Keep a root at the extraction boundary available for the next
            // scan, while always making forward progress for empty fragments.
            cursor = max(cursor + 1, extraction.nextCursor)
        }

        guard !result.isEmpty else {
            throw PathResolverError.invalidClipboardText
        }
        return result
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

    private enum PathRoot {
        case url
        case drive
        case unc
        case posix
    }

    private struct CandidateExtraction {
        let value: String?
        let nextCursor: Int
    }

    private static func pathRootCount(in characters: [Character]) -> Int {
        var count = 0
        var index = 0
        while index < characters.count {
            if pathRoot(at: index, in: characters) != nil {
                count += 1
            }
            index += 1
        }
        return count
    }

    private static func pathRoot(at index: Int, in characters: [Character]) -> PathRoot? {
        if matches("smb://", at: index, in: characters),
           isRootBoundary(at: index, in: characters, pairRoot: false) {
            return .url
        }
        if matches("file://", at: index, in: characters),
           isRootBoundary(at: index, in: characters, pairRoot: false) {
            return .url
        }
        if matches("storage://", at: index, in: characters),
           isRootBoundary(at: index, in: characters, pairRoot: false) {
            return .url
        }

        if index + 2 < characters.count,
           isASCIIAlpha(characters[index]),
           characters[index + 1] == ":",
           isPathSeparator(characters[index + 2]),
           isRootBoundary(at: index, in: characters, pairRoot: false) {
            return .drive
        }

        if index + 1 < characters.count,
           isPathSeparator(characters[index]),
           isPathSeparator(characters[index + 1]),
           isRootBoundary(at: index, in: characters, pairRoot: true) {
            return .unc
        }

        if characters[index] == "/",
           (index + 1 == characters.count || characters[index + 1] != "/"),
           isRootBoundary(at: index, in: characters, pairRoot: false) {
            return .posix
        }

        return nil
    }

    private static func extractCandidate(
        from start: Int,
        root: PathRoot,
        in characters: [Character]
    ) -> CandidateExtraction {
        let openingQuote = start > 0 ? quotePair(for: characters[start - 1]) : nil
        var end = start
        var stoppedAtAnotherRoot = false
        var wrapperStack: [Character] = []

        while end < characters.count {
            if openingQuote == nil, end > start, pathRoot(at: end, in: characters) != nil {
                stoppedAtAnotherRoot = true
                break
            }

            let character = characters[end]
            if character.unicodeScalars.contains(where: {
                CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            }) {
                break
            }
            if let openingQuote, character == openingQuote {
                break
            }
            if openingQuote == nil && quotePair(for: character) != nil {
                break
            }
            if openingQuote == nil
                && isNaturalLanguageTerminator(
                    character,
                    at: end,
                    in: characters,
                    preservingURLQuestion: isURLRoot(root)
                ) {
                break
            }
            if openingQuote == nil {
                if let openingWrapper = openingWrapper(forClosing: character) {
                    if wrapperStack.last == openingWrapper {
                        wrapperStack.removeLast()
                    } else if isWrapperBoundary(after: end, in: characters) {
                        break
                    }
                } else if isOpeningWrapper(character) {
                    wrapperStack.append(character)
                }
            }
            end += 1
        }

        var candidate = String(characters[start..<end])
            .trimmingCharacters(in: .whitespaces)
        if stoppedAtAnotherRoot {
            candidate = trimConnectorSuffix(from: candidate)
        }

        let nextCursor: Int
        if stoppedAtAnotherRoot {
            // `end` points at the next root. It must be scanned by the outer
            // loop so multiple candidates retain their original order.
            nextCursor = end
        } else {
            nextCursor = max(end, start + 1)
        }
        return CandidateExtraction(value: candidate.isEmpty ? nil : candidate, nextCursor: nextCursor)
    }

    private static func isURLRoot(_ root: PathRoot) -> Bool {
        if case .url = root {
            return true
        }
        return false
    }

    private static func trimConnectorSuffix(from value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        let connectors = [
            "and", "or", "then", "also",
            "和", "或", "以及", "还有", "另一个", "再"
        ]

        for connector in connectors {
            let suffix = " " + connector
            if result.count >= suffix.count,
               result.lowercased().hasSuffix(suffix.lowercased()) {
                result.removeLast(suffix.count)
                return result.trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    private static func matches(_ literal: String, at index: Int, in characters: [Character]) -> Bool {
        let literalCharacters = Array(literal)
        guard index >= 0, index + literalCharacters.count <= characters.count else {
            return false
        }
        return String(characters[index..<(index + literalCharacters.count)]).lowercased() == literal
    }

    private static func isRootBoundary(
        at index: Int,
        in characters: [Character],
        pairRoot: Bool
    ) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]

        if pairRoot {
            // Prevent the `//` in unsupported URLs such as https:// from being
            // mistaken for an UNC path.
            return previous != "/" && previous != "\\" && previous != ":"
                && !isAlphaNumeric(previous)
        }

        return previous != "/" && previous != "\\"
            && !isAlphaNumeric(previous)
            && previous != "_" && previous != "-" && previous != "."
    }

    private static func isASCIIAlpha(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        return ("A"..."Z").contains(Character(scalar))
            || ("a"..."z").contains(Character(scalar))
    }

    private static func isAlphaNumeric(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func isPathSeparator(_ character: Character) -> Bool {
        character == "/" || character == "\\"
    }

    private static func quotePair(for character: Character) -> Character? {
        switch character {
        case "\"": return "\""
        case "'": return "'"
        case "`": return "`"
        case "“": return "”"
        case "‘": return "’"
        default: return nil
        }
    }

    private static func isNaturalLanguageTerminator(
        _ character: Character,
        at index: Int,
        in characters: [Character],
        preservingURLQuestion: Bool
    ) -> Bool {
        if preservingURLQuestion && character == "?" {
            return false
        }
        if ",;!?".contains(character),
           index + 1 < characters.count,
           pathRoot(at: index + 1, in: characters) != nil {
            return true
        }
        if ",;!?".contains(character),
           index + 1 < characters.count,
           !characters[index + 1].unicodeScalars.contains(where: {
               CharacterSet.whitespacesAndNewlines.contains($0)
                   || CharacterSet.controlCharacters.contains($0)
           }),
           !isClosingWrapper(characters[index + 1]) {
            // A punctuation mark followed immediately by another filename
            // character can be part of a legal path (for example foo,bar or
            // shot (final).hip). Sentence punctuation remains a boundary when
            // it is followed by whitespace, a wrapper, or the end of input.
            return false
        }
        switch character {
        case ",", ";", "!", "?", "，", "。", "；", "！", "？", "、", "：", "…":
            return true
        default:
            return false
        }
    }

    private static func isClosingWrapper(_ character: Character) -> Bool {
        openingWrapper(forClosing: character) != nil
    }

    private static func isOpeningWrapper(_ character: Character) -> Bool {
        switch character {
        case "(", "[", "{", "<", "（", "【", "〈", "《", "「", "『":
            return true
        default:
            return false
        }
    }

    private static func openingWrapper(forClosing character: Character) -> Character? {
        switch character {
        case ")": return "("
        case "]": return "["
        case "}": return "{"
        case ">": return "<"
        case "）": return "（"
        case "】": return "【"
        case "〉": return "〈"
        case "》": return "《"
        case "」": return "「"
        case "』": return "『"
        case "”": return "“"
        case "’": return "‘"
        case "›": return "‹"
        case "»": return "«"
        default: return nil
        }
    }

    private static func isWrapperBoundary(after index: Int, in characters: [Character]) -> Bool {
        let nextIndex = index + 1
        guard nextIndex < characters.count else { return true }
        let next = characters[nextIndex]
        if next.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.controlCharacters.contains($0)
        }) {
            return true
        }
        if isNaturalLanguageTerminator(
            next,
            at: nextIndex,
            in: characters,
            preservingURLQuestion: false
        ) {
            return true
        }
        return pathRoot(at: nextIndex, in: characters) != nil
    }
}
