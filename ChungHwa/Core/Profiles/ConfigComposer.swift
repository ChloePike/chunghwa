import Foundation

/// Builds the on-disk yaml mihomo runs.
///
/// Strategy: append a sentinel block with our mandatory keys *after* the user's content.
/// mihomo (via Go yaml.v3) takes the last value for duplicate top-level keys, so our
/// `external-controller` and `secret` always win regardless of what the user supplies.
enum ConfigComposer {
    static func compose(userYaml: String?, externalControllerHostPort: String, secret: String) -> String {
        let body = userYaml.map { trimmedTrailing($0) } ?? defaultBody
        return """
        \(body)

        # === ChungHwa overrides — managed by the app, do not edit ===
        external-controller: \(externalControllerHostPort)
        secret: \(secret)
        """
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
