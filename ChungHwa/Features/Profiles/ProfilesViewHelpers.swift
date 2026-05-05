import SwiftUI

struct ProfilesBrassButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.ink)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.brass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.brassDark.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: ChungHwa.Palette.brassDark.opacity(0.20), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ProfilesGhostButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProfilesBadgeButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(enabled ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(enabled ? ChungHwa.Palette.pillBg : ChungHwa.Palette.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ProfilesIconBadgeButton: View {
    let systemImage: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ChungHwa.Palette.pillBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ProfilesGhostMiniButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct RelativeDateText: View {
    let date: Date

    var body: some View {
        Text(format(date))
    }

    private func format(_ d: Date) -> String {
        let elapsed = Date.now.timeIntervalSince(d)
        if elapsed < 0 { return "刚刚" }
        let s = Int(elapsed)
        switch s {
        case ..<5:
            return "刚刚"
        case ..<60:
            return "\(s) 秒前"
        case ..<3_600:
            let m = s / 60
            return "\(m) 分钟前"
        case ..<86_400:
            let h = s / 3600
            return "\(h) 小时前"
        case ..<(86_400 * 7):
            let dys = s / 86_400
            return "\(dys) 天前"
        case ..<(86_400 * 30):
            let w = s / (86_400 * 7)
            return "\(w) 周前"
        case ..<(86_400 * 365):
            let mo = s / (86_400 * 30)
            return "\(mo) 个月前"
        default:
            let y = s / (86_400 * 365)
            return "\(y) 年前"
        }
    }
}

/// Cheap per-line YAML colorizer: comments faint, top-level keys brass,
/// quoted strings patina, anchors/aliases earth, everything else default.
enum YAMLHighlighter {
    static func highlight(_ yaml: String) -> AttributedString {
        var out = AttributedString("")
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, line) in lines.enumerated() {
            out.append(highlight(line: String(line)))
            if idx < lines.count - 1 {
                var nl = AttributedString("\n")
                nl.foregroundColor = ChungHwa.Palette.text
                out.append(nl)
            }
        }
        return out
    }

    private static func highlight(line raw: String) -> AttributedString {
        if raw.isEmpty {
            var s = AttributedString("")
            s.foregroundColor = ChungHwa.Palette.text
            return s
        }

        let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.first == "#" {
            var s = AttributedString(raw)
            s.foregroundColor = ChungHwa.Palette.faint
            return s
        }

        if let colonIdx = topLevelKeyColonIndex(raw) {
            var out = AttributedString("")
            let keyPart = String(raw[..<colonIdx]) + ":"
            var keyAttr = AttributedString(keyPart)
            keyAttr.foregroundColor = ChungHwa.Palette.brass
            out.append(keyAttr)
            let afterColon = raw.index(after: colonIdx)
            if afterColon < raw.endIndex {
                let rest = String(raw[afterColon...])
                out.append(colorizeValue(rest))
            }
            return out
        }

        return colorizeValue(raw)
    }

    private static func topLevelKeyColonIndex(_ line: String) -> String.Index? {
        guard let first = line.first, !first.isWhitespace else { return nil }
        var i = line.startIndex
        var sawAny = false
        while i < line.endIndex {
            let c = line[i]
            if c.isLetter || c.isNumber || c == "_" || c == "-" {
                sawAny = true
                i = line.index(after: i)
            } else {
                break
            }
        }
        guard sawAny, i < line.endIndex, line[i] == ":" else { return nil }
        return i
    }

    private static func colorizeValue(_ s: String) -> AttributedString {
        var out = AttributedString("")
        var i = s.startIndex
        var pending = ""

        func flushPending() {
            guard !pending.isEmpty else { return }
            var a = AttributedString(pending)
            a.foregroundColor = ChungHwa.Palette.text
            out.append(a)
            pending = ""
        }

        while i < s.endIndex {
            let c = s[i]

            // Inline comment from `#` to EOL — only if preceded by whitespace.
            if c == "#", (i == s.startIndex || s[s.index(before: i)].isWhitespace) {
                flushPending()
                let rest = String(s[i...])
                var a = AttributedString(rest)
                a.foregroundColor = ChungHwa.Palette.faint
                out.append(a)
                return out
            }

            if c == "\"" || c == "'" {
                flushPending()
                let quote = c
                let start = i
                var j = s.index(after: i)
                while j < s.endIndex {
                    let cc = s[j]
                    if cc == "\\", s.index(after: j) < s.endIndex {
                        j = s.index(j, offsetBy: 2)
                        continue
                    }
                    if cc == quote {
                        j = s.index(after: j)
                        break
                    }
                    j = s.index(after: j)
                }
                let segment = String(s[start..<j])
                var a = AttributedString(segment)
                a.foregroundColor = ChungHwa.Palette.patina
                out.append(a)
                i = j
                continue
            }

            if (c == "&" || c == "*"),
               (i == s.startIndex || s[s.index(before: i)].isWhitespace) {
                let next = s.index(after: i)
                if next < s.endIndex {
                    let nc = s[next]
                    if nc.isLetter || nc.isNumber || nc == "_" || nc == "-" {
                        flushPending()
                        let start = i
                        var j = next
                        while j < s.endIndex {
                            let cc = s[j]
                            if cc.isLetter || cc.isNumber || cc == "_" || cc == "-" {
                                j = s.index(after: j)
                            } else { break }
                        }
                        let segment = String(s[start..<j])
                        var a = AttributedString(segment)
                        a.foregroundColor = ChungHwa.Palette.earth
                        out.append(a)
                        i = j
                        continue
                    }
                }
            }

            pending.append(c)
            i = s.index(after: i)
        }

        flushPending()
        return out
    }
}
