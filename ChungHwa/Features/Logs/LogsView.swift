import SwiftUI

struct LogsView: View {
    @Environment(LogStore.self) private var store
    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Logs")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Spacer()
            Text("\(store.lines.count) lines")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear") { store.clear() }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.lines.isEmpty {
            ContentUnavailableView("No log output yet",
                                   systemImage: "terminal",
                                   description: Text("mihomo stdout/stderr will appear here once the kernel starts."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.lines) { line in
                            LogRow(line: line).id(line.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.lines.count) {
                    guard follow, let last = store.lines.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                .onAppear {
                    if let last = store.lines.last {
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
            Text(line.stream == .stderr ? "E" : "O")
                .foregroundStyle(line.stream == .stderr ? .red : .blue)
                .frame(width: 14, alignment: .center)
            Text(line.text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 16)
    }
}
