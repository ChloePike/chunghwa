import SwiftUI

struct ProxyGroupCard: View {
    let group: MihomoProxy
    let query: String
    let sort: ProxySort
    let mode: ProxyViewMode
    let isOpen: Bool
    let onToggle: (Bool) -> Void

    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    private var visibleNames: [String] {
        ProxiesHelpers.filterAndSort(
            names: group.all ?? [],
            query: query, sort: sort, store: store)
    }

    private var minPing: Int? {
        let names = group.all ?? []
        let pings = names.compactMap { store.proxy($0)?.lastDelay }.filter { $0 > 0 }
        return pings.min()
    }

    private var isTesting: Bool { store.testingGroups.contains(group.name) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
                body(for: visibleNames)
            }
        }
        .background(ChungHwa.Palette.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { onToggle(!isOpen) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(group.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                    Text(group.type)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ChungHwa.Palette.faint)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ChungHwa.Palette.fill)
                        )
                    Text("\(group.all?.count ?? 0) 个")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.faint)
                }
                selectedSubtitle
            }

            Spacer(minLength: 8)

            if let m = minPing {
                fastestPill(ms: m)
            }

            testButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) { onToggle(!isOpen) }
        }
    }

    @ViewBuilder
    private var selectedSubtitle: some View {
        if let now = group.now {
            HStack(spacing: 6) {
                Text("当前")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                Text(now)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let ms = store.proxy(now)?.lastDelay, ms > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(ChungHwa.Palette.faint)
                    Text("\(ms) ms")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ChLatency.color(ms))
                        .monospacedDigit()
                }
            }
        }
    }

    private func fastestPill(ms: Int) -> some View {
        HStack(spacing: 5) {
            ChDot(color: ChLatency.color(ms), size: 5)
            Text("最低 \(ms) ms")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ChLatency.color(ms))
                .monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ChLatency.color(ms).opacity(0.10))
        )
    }

    private var testButton: some View {
        Button {
            Task { await store.testGroup(group.name, api: kernel.apiClient) }
        } label: {
            Group {
                if isTesting {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                } else {
                    Image(systemName: "bolt.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
            .opacity(isTesting ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isTesting || kernel.apiClient == nil)
        .help(isTesting ? "测试中…" : "测试该组")
    }

    @ViewBuilder
    private func body(for names: [String]) -> some View {
        if names.isEmpty {
            Text("没有匹配 “\(query)” 的节点")
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.faint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if mode == .grid {
            let columns = [GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(names, id: \.self) { name in
                    ProxyNodeCard(
                        name: name,
                        proxy: store.proxy(name),
                        isSelected: name == group.now,
                        isSwitchable: group.isUserSwitchable,
                        isTesting: isTesting,
                        onSelect: { select(name) }
                    )
                    .equatable()
                }
            }
            .padding(10)
        } else {
            VStack(spacing: 1) {
                listHeader
                ForEach(names, id: \.self) { name in
                    ProxyNodeRow(
                        name: name,
                        proxy: store.proxy(name),
                        isSelected: name == group.now,
                        isSwitchable: group.isUserSwitchable,
                        isTesting: isTesting,
                        onSelect: { select(name) }
                    )
                    .equatable()
                }
            }
            .padding(6)
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 13)
            Text("名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("协议")
                .frame(width: 90, alignment: .leading)
            Text("状态")
                .frame(width: 70, alignment: .leading)
            Text("延迟")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(0.4)
        .foregroundStyle(ChungHwa.Palette.faint)
        .textCase(.uppercase)
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func select(_ name: String) {
        guard group.isUserSwitchable else { return }
        Task { await store.select(group: group.name, name: name, api: kernel.apiClient) }
    }
}
