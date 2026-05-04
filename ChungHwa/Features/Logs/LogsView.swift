import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os.log

private enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all, info, warn, error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:   return "All"
        case .info:  return "Info"
        case .warn:  return "Warn"
        case .error: return "Error"
        }
    }

    func includes(_ stream: LogStream) -> Bool {
        switch self {
        case .all:
            return true
        case .info:
            return stream == .info || stream == .debug || stream == .stdout
        case .warn:
            return stream == .warning
        case .error:
            return stream == .error || stream == .stderr
        }
    }
}

struct LogsView: View {
    @Environment(LogStore.self) private var store
    @State private var filter: LogLevelFilter = .all
    @State private var paused = false
    @State private var frozenLines: [LogLine] = []
    @State private var query: String = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            ChCard(padding: 0) {
                logScroll
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ChungHwa.Palette.bg.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .chungHwaFocusFilter)) { _ in
            filterFocused = true
        }
    }

    // MARK: - Source

    private var sourceLines: [LogLine] {
        paused ? frozenLines : store.lines
    }

    private var visibleLines: [LogLine] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        return sourceLines.filter { line in
            guard filter.includes(line.stream) else { return false }
            if !trimmedQuery.isEmpty,
               !line.text.localizedCaseInsensitiveContains(trimmedQuery) {
                return false
            }
            return true
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ChSeg(
                value: filter,
                onChange: { filter = $0 },
                options: LogLevelFilter.allCases.map { ($0, $0.label) }
            )

            searchField

            Spacer(minLength: 0)

            countLabel

            ChPill(active: paused, action: togglePause) {
                HStack(spacing: 4) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(paused ? "Resume" : "Pause")
                }
            }

            ChPill(active: false, action: clearLogs) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Clear")
                }
            }

            ChPill(active: false, action: saveLogs) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Save")
                }
            }
            .help("Export visible logs to a file")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.faint)

            TextField("Filter…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.text)
                .focused($filterFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ChungHwa.Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 220, height: 25)
        .background(ChungHwa.Palette.fill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ChungHwa.Palette.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var countLabel: some View {
        let visible = visibleLines.count
        let total = sourceLines.count
        if isSearching && visible == 0 {
            Text("no matches")
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.earth)
                .monospacedDigit()
        } else {
            Text("\(visible) / \(total) lines")
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.faint)
                .monospacedDigit()
        }
    }

    // MARK: - Scroll

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        LogRow(line: line, query: query)
                            .id(line.id)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ChungHwa.Palette.cardSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: store.lines.count) {
                guard !paused, !isSearching, let last = visibleLines.last else { return }
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: filter) {
                if let last = visibleLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: paused) { _, nowPaused in
                if !nowPaused, !isSearching, let last = store.lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: query) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty, let last = visibleLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = visibleLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePause() {
        if paused {
            paused = false
            frozenLines = []
        } else {
            frozenLines = store.lines
            paused = true
        }
    }

    private func clearLogs() {
        store.clear()
        if paused {
            frozenLines = []
        }
    }

    private static let exportLogger = Logger(subsystem: "com.tzaigroup.chunghwa", category: "logs")

    private static let exportFilenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static let exportTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func saveLogs() {
        let lines = visibleLines
        let defaultFilename = "chunghwa-logs-\(Self.exportFilenameFormatter.string(from: Date())).txt"

        let panel = NSSavePanel()
        panel.title = "Save logs"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let body = lines.map(Self.formatLine).joined(separator: "\n")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            Self.exportLogger.info("Exported \(lines.count, privacy: .public) log lines to \(url.path, privacy: .public)")
        } catch {
            Self.exportLogger.error("Failed to export logs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func formatLine(_ line: LogLine) -> String {
        let ts = exportTimestampFormatter.string(from: line.date)
        let level: String
        switch line.stream {
        case .stdout:  level = "OUT"
        case .stderr:  level = "ERR"
        case .debug:   level = "DEBUG"
        case .info:    level = "INFO"
        case .warning: level = "WARN"
        case .error:   level = "ERROR"
        }
        return "\(ts) [\(level)] \(line.text)"
    }
}

// MARK: - Row

private struct LogRow: View {
    let line: LogLine
    let query: String

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.formatter.string(from: line.date))
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.faint)

            Text(levelLabel)
                .font(ChungHwa.Typography.mono(11, weight: .semibold))
                .foregroundStyle(levelColor)
                .frame(width: 44, alignment: .leading)

            Text(highlightedText)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineSpacing(4)
        .padding(.vertical, 1)
    }

    private var highlightedText: AttributedString {
        var attr = AttributedString(line.text)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return attr }
        var i = attr.startIndex
        while i < attr.endIndex,
              let range = attr[i...].range(of: trimmed, options: .caseInsensitive) {
            attr[range].backgroundColor = NSColor(ChungHwa.Palette.brass.opacity(0.30))
            attr[range].font = .system(size: 11, design: .monospaced).bold()
            i = range.upperBound
        }
        return attr
    }

    private var levelLabel: String {
        switch line.stream {
        case .stdout:  return "OUT"
        case .stderr:  return "ERR"
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARN"
        case .error:   return "ERROR"
        }
    }

    private var levelColor: Color {
        switch line.stream {
        case .info:    return ChungHwa.Palette.patina
        case .warning: return ChungHwa.Palette.brass
        case .error:   return ChungHwa.Palette.earth
        case .debug:   return ChungHwa.Palette.faint
        case .stdout, .stderr: return ChungHwa.Palette.dim
        }
    }
}
