import Foundation

/// Builds the on-disk yaml mihomo runs.
///
/// Strategy: strip any top-level `external-controller` / `secret` from the
/// user's yaml and append our own at the bottom. Earlier we relied on Go
/// yaml.v3 "last value wins" semantics, but mihomo's parser is strict about
/// duplicate keys and refuses to load when both are present.
enum ConfigComposer {
    static func compose(userYaml: String?, externalControllerHostPort: String, secret: String) -> String {
        let bodyRaw = userYaml ?? defaultBody
        let stripped = stripTopLevelKeys(
            bodyRaw,
            keys: ["external-controller", "secret"]
        )
        let body = trimmedTrailing(stripped)
        return """
        \(body)

        # === ChungHwa overrides — managed by the app, do not edit ===
        external-controller: \(externalControllerHostPort)
        secret: \(secret)
        """
    }

    /// Remove every top-level (zero-indent) line that defines one of the
    /// listed keys. Naive, line-based, comment-tolerant. Doesn't handle
    /// multi-line block scalars or anchors for these keys, but
    /// `external-controller` and `secret` are always inline scalars in
    /// practice.
    private static func stripTopLevelKeys(_ yaml: String, keys: [String]) -> String {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [Substring] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if matchesTopLevelKey(line, keys: keys) { continue }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    private static func matchesTopLevelKey(_ line: Substring, keys: [String]) -> Bool {
        // Top-level: must start at column 0 with a non-whitespace character.
        guard let first = line.first, !first.isWhitespace else { return false }
        guard let colon = line.firstIndex(of: ":") else { return false }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return keys.contains(key)
    }

    private static let defaultBody: String = """
    mixed-port: 7890
    allow-lan: false
    mode: rule
    log-level: info
    """

    private static func trimmedTrailing(_ s: String) -> String {
        var s = s
        while let last = s.last, last == "\n" || last == " " || last == "\t" || last == "\r" {
            s.removeLast()
        }
        return s
    }
}
