import SwiftUI

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
        .navigationTitle("Logs")
    }

    // MARK: - Source

    private var sourceLines: [LogLine] {
        paused ? frozenLines : store.lines
    }

    private var visibleLines: [LogLine] {
        guard filter != .all else { return sourceLines }
        return sourceLines.filter { filter.includes($0.stream) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ChSeg(
                value: filter,
                onChange: { filter = $0 },
                options: LogLevelFilter.allCases.map { ($0, $0.label) }
            )

            Spacer(minLength: 0)

            Text("\(visibleLines.count) / \(sourceLines.count) lines")
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.faint)
                .monospacedDigit()

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
        }
    }

    // MARK: - Scroll

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        LogRow(line: line)
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
                guard !paused, let last = visibleLines.last else { return }
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
                if !nowPaused, let last = store.lines.last {
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
}

// MARK: - Row

private struct LogRow: View {
    let line: LogLine

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

            Text(line.text)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineSpacing(4)
        .padding(.vertical, 1)
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
