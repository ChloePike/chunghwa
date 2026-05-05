import Foundation

enum ConnectionsHelpers {
    /// "LAN" sentinel → 🏠. Two-letter ISO → flag emoji. Anything else (or
    /// pending) renders empty so the column doesn't thrash.
    static func regionGlyph(_ country: String?) -> String {
        guard let country, !country.isEmpty else { return "" }
        if country == "LAN" { return "🏠" }
        return flag(country)
    }

    /// ISO 3166-1 alpha-2 → regional-indicator flag emoji. Returns "" for
    /// inputs that aren't two ASCII letters so we never render half a codepoint.
    static func flag(_ iso: String) -> String {
        let upper = iso.uppercased()
        guard upper.count == 2 else { return "" }
        let base: UInt32 = 0x1F1E6 - 0x41
        var out = ""
        for ch in upper.unicodeScalars {
            guard (0x41...0x5A).contains(ch.value),
                  let scalar = Unicode.Scalar(base + ch.value)
            else { return "" }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// Rule-column display string. mihomo emits wordy constants
    /// ("DOMAIN-SUFFIX", "DOMAIN-KEYWORD") that don't fit the 110pt column —
    /// abbreviate to keep the column glanceable.
    static func ruleText(_ rule: String) -> String {
        switch rule {
        case "DOMAIN-SUFFIX":  return "SUFFIX"
        case "DOMAIN-KEYWORD": return "KEYWORD"
        case "RuleSet":        return "RULESET"
        case "":               return "—"
        default:               return rule
        }
    }
}
