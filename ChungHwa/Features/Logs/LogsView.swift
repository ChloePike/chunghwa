import SwiftUI

private enum LogFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case process
    case runtime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return "All"
        case .errors:  return "Errors"
        case .process: return "Process"
        case .runtime: return "Runtime"
        }
    }

    func includes(_ stream: LogStream) -> Bool {
        switch self {
        case .all: return true
        case .errors:
            return stream == .stderr || stream == .error || stream == .warning
        case .process:
            return stream.isProcessPipe
        case .runtime:
            return !stream.isProcessPipe
        }
    }
}

struct LogsView: View {
    @Environment(LogStore.self) private var store
    @State private var follow = true
    @State private var filter: LogFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Logs")
    }

    private var visibleLines: [LogLine] {
        guard filter != .all else { return store.lines }
        return store.lines.filter { filter.includes($0.stream) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(LogFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Spacer()
            Text("\(visibleLines.count) / \(store.lines.count) lines")
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Clear") { store.clear() }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.lines.isEmpty {
            ContentUnavailableView("No log output yet",
                                   systemImage: "terminal",
                                   description: Text("mihomo runtime events and stdout/stderr appear here once the kernel starts."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(visibleLines) { line in
                            LogRow(line: line).id(line.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.lines.count) {
                    guard follow, let last = visibleLines.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                .onChange(of: filter) {
                    if let last = visibleLines.last {
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
    }
}

private struct LogRow: View {
    let line: LogLine

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.formatter.string(from: line.date))
                .foregroundStyle(.tertiary)
                .frame(width: 92, alignment: .leading)
            Text(glyph)
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)
            Text(line.text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 16)
    }

    private var glyph: String {
        switch line.stream {
        case .stdout:  return "·"
        case .stderr:  return "!"
        case .debug:   return "D"
        case .info:    return "I"
        case .warning: return "W"
        case .error:   return "E"
        }
    }

    private var color: Color {
        switch line.stream {
        case .stdout:  return .secondary
        case .stderr:  return .red
        case .debug:   return .secondary
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
