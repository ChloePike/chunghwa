import SwiftUI

struct ProxiesView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    @State private var openGroup: String?

    var body: some View {
        Group {
            if kernel.apiClient == nil {
                emptyState
            } else if store.groups.isEmpty && store.isRefreshing {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.groups.isEmpty {
                noGroupsState
            } else {
                groupList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Proxies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh(api: kernel.apiClient) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(kernel.apiClient == nil || store.isRefreshing)
            }
        }
        .task(id: kernelStatusKey) {
            await store.refresh(api: kernel.apiClient)
            // Pre-open the first group so the user sees nodes without clicking.
            if openGroup == nil { openGroup = store.groups.first?.name }
        }
    }

    private var kernelStatusKey: String {
        switch kernel.status {
        case .idle:                  return "idle"
        case .starting:              return "starting"
        case .failed(let r):         return "failed:\(r)"
        case .running(let v):        return "running:\(v)"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("Kernel is not running").font(.title3.weight(.semibold))
            Text("Start the kernel from Overview to see proxy groups.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var noGroupsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("No proxy groups").font(.title3.weight(.semibold))
            Text("Your active profile has no `proxy-groups`. Edit the YAML in Settings.")
                .font(.callout).foregroundStyle(.secondary)
            if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(3)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let err = store.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                    }
                    .padding(10)
                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(store.groups) { group in
                    GroupCard(
                        group: group,
                        isOpen: Binding(
                            get: { openGroup == group.name },
                            set: { isOpen in openGroup = isOpen ? group.name : nil }
                        )
                    )
                }
            }
            .padding(20)
        }
    }
}

private struct GroupCard: View {
    let group: MihomoProxy
    @Binding var isOpen: Bool

    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                Divider()
                nodeList
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.secondary.opacity(0.15)))
    }

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(group.name).font(.subheadline.weight(.semibold))
                        Text(group.type.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(.tint)
                        Text("\(group.all?.count ?? 0) nodes")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let now = group.now {
                        HStack(spacing: 4) {
                            Text("Now using").font(.caption).foregroundStyle(.secondary)
                            Text(now).font(.caption.weight(.semibold))
                            if let ms = store.proxy(now)?.lastDelay {
                                Text("· \(ms) ms")
                                    .font(.caption).foregroundStyle(latencyColor(ms))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await store.testGroup(group.name, api: kernel.apiClient) }
                } label: {
                    if store.testingGroups.contains(group.name) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Test", systemImage: "bolt.horizontal")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.testingGroups.contains(group.name))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nodeList: some View {
        let names = group.all ?? []
        let testing = store.testingGroups.contains(group.name)
        return VStack(spacing: 1) {
            ForEach(names, id: \.self) { name in
                NodeRow(
                    name: name,
                    proxy: store.proxy(name),
                    isSelected: name == group.now,
                    isSwitchable: group.isUserSwitchable,
                    isTesting: testing
                ) {
                    Task { await store.select(group: group.name, name: name, api: kernel.apiClient) }
                }
            }
        }
        .padding(6)
    }
}

private struct NodeRow: View {
    let name: String
    let proxy: MihomoProxy?
    let isSelected: Bool
    let isSwitchable: Bool
    let isTesting: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                radio
                Text(name).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let p = proxy {
                    Text(p.type.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                latencyBadge
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSwitchable && !isSelected)
        .help(isSwitchable ? "Click to select" : "Auto-selected by \(proxy?.type ?? "group")")
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : .secondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private var latencyBadge: some View {
        if isTesting {
            ProgressView().controlSize(.mini)
        } else if let ms = proxy?.lastDelay {
            Text("\(ms) ms")
                .font(.caption.weight(.semibold))
                .foregroundStyle(latencyColor(ms))
                .monospacedDigit()
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}

private func latencyColor(_ ms: Int) -> Color {
    switch ms {
    case ..<80:  return .green
    case ..<180: return .orange
    default:     return .red
    }
}
