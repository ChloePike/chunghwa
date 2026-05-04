import SwiftUI

struct ConnectionsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var store

    @State private var filter: String = ""
    @State private var sortOrder: [KeyPathComparator<MihomoConnection>] = [
        .init(\.download, order: .reverse),
    ]
    @State private var selection: MihomoConnection.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Connections")
    }

    private var visibleRows: [MihomoConnection] {
        let needle = filter.lowercased()
        let filtered = needle.isEmpty
            ? store.connections
            : store.connections.filter { row in
                row.destination.lowercased().contains(needle) ||
                (row.metadata.process?.lowercased().contains(needle) ?? false) ||
                row.activeProxy.lowercased().contains(needle)
            }
        return filtered.sorted(using: sortOrder)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary).font(.caption)
                TextField("Filter host, process, or proxy", text: $filter)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 280)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 6))
            Spacer()
            Text("\(visibleRows.count) / \(store.connections.count)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Label("↑ \(formatBytes(store.uploadTotal))", systemImage: "")
                .labelStyle(.titleOnly)
                .font(.caption).foregroundStyle(.blue).monospacedDigit()
            Label("↓ \(formatBytes(store.downloadTotal))", systemImage: "")
                .labelStyle(.titleOnly)
                .font(.caption).foregroundStyle(.green).monospacedDigit()
            Button(role: .destructive) {
                Task { await store.closeAll(api: kernel.apiClient) }
            } label: {
                Label("Close all", systemImage: "xmark.circle")
            }
            .disabled(store.connections.isEmpty || kernel.apiClient == nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if kernel.apiClient == nil {
            ContentUnavailableView("Kernel is not running",
                                   systemImage: "powerplug",
                                   description: Text("Connections appear here once mihomo is up."))
        } else if store.connections.isEmpty {
            ContentUnavailableView("No active connections",
                                   systemImage: "link.circle",
                                   description: Text("Browse a website to see proxied connections."))
        } else {
            table
        }
    }

    private var table: some View {
        Table(visibleRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Destination") { row in
                Text(row.destination)
                    .font(.callout)
                    .lineLimit(1).truncationMode(.middle)
                    .help(row.destination)
            }
            TableColumn("Process") { row in
                Text(row.metadata.process ?? "—")
                    .font(.callout)
                    .lineLimit(1).truncationMode(.middle)
            }
            TableColumn("Net") { row in
                Text((row.metadata.network ?? "?").uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(40)
            TableColumn("Chain") { row in
                Text(row.chainPath)
                    .font(.callout)
                    .lineLimit(1).truncationMode(.head)
                    .help(row.chainPath)
            }
            TableColumn("Rule") { row in
                Text(row.rule)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(96)
            TableColumn("↑", value: \.upload) { row in
                Text(formatBytes(row.upload))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(.blue)
            }
            .width(72)
            TableColumn("↓", value: \.download) { row in
                Text(formatBytes(row.download))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(.green)
            }
            .width(72)
            TableColumn("Time", value: \.start) { row in
                Text(elapsed(since: row.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .width(56)
        }
        .contextMenu(forSelectionType: MihomoConnection.ID.self) { ids in
            Button("Close", role: .destructive) {
                for id in ids {
                    Task { await store.close(id: id, api: kernel.apiClient) }
                }
            }
        }
    }
}

private let iso = ISO8601DateFormatter()

private func elapsed(since startISO: String) -> String {
    guard let start = iso.date(from: startISO) else { return "—" }
    let s = Int(Date().timeIntervalSince(start))
    if s < 60   { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h"
}

private func formatBytes(_ bytes: Int) -> String {
    let v = Double(bytes)
    switch v {
    case ..<1024:                    return String(format: "%.0f B", v)
    case ..<1_048_576:               return String(format: "%.1f KB", v / 1024)
    case ..<1_073_741_824:           return String(format: "%.1f MB", v / 1_048_576)
    default:                         return String(format: "%.2f GB", v / 1_073_741_824)
    }
}
