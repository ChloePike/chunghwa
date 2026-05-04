import SwiftUI

// MARK: - Sort & view modes

private enum ProxySort: Hashable, CaseIterable {
    case latency, name, defaultOrder
    var label: String {
        switch self {
        case .latency:      return "延迟"
        case .name:         return "名字"
        case .defaultOrder: return "默认"
        }
    }
}

private enum ProxyViewMode: Hashable {
    case grid, list
}

// MARK: - Main screen

struct ProxiesView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    @State private var query: String = ""
    @State private var sort: ProxySort = .latency
    @State private var view: ProxyViewMode = .grid
    @State private var openMap: [String: Bool] = [:]

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
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChungHwa.Palette.bg)
        .task(id: kernelStatusKey) {
            await store.refresh(api: kernel.apiClient)
            // Pre-open the first group so the user sees nodes without clicking.
            if let first = store.groups.first?.name, openMap[first] == nil {
                openMap[first] = true
            }
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

    // MARK: layout

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let err = store.lastError {
                        errorBanner(err)
                    }
                    ForEach(visibleGroups, id: \.name) { group in
                        ProxyGroupCard(
                            group: group,
                            query: query,
                            sort: sort,
                            mode: view,
                            isOpen: Binding(
                                get: { openMap[group.name] ?? false },
                                set: { openMap[group.name] = $0 }
                            )
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private var visibleGroups: [MihomoProxy] {
        store.groups.filter { group in
            // Hide groups that have no nodes matching the current filter.
            let filtered = filterAndSort(group: group)
            return !filtered.isEmpty || query.isEmpty
        }
    }

    private func filterAndSort(group: MihomoProxy) -> [String] {
        let names = group.all ?? []
        let filtered: [String]
        if query.isEmpty {
            filtered = names
        } else {
            let q = query.lowercased()
            filtered = names.filter { name in
                if name.lowercased().contains(q) { return true }
                if let p = store.proxy(name), p.type.lowercased().contains(q) { return true }
                return false
            }
        }
        switch sort {
        case .defaultOrder:
            return filtered
        case .name:
            return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .latency:
            return filtered.sorted { lhs, rhs in
                let l = store.proxy(lhs)?.lastDelay ?? 9999
                let r = store.proxy(rhs)?.lastDelay ?? 9999
                return l < r
            }
        }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ProxySearchField(text: $query)
                .frame(width: 220)

            ChSeg(
                value: sort,
                onChange: { sort = $0 },
                options: [
                    (.latency, "延迟"),
                    (.name, "名字"),
                    (.defaultOrder, "默认"),
                ]
            )

            Spacer()

            ViewModeToggle(mode: $view)

            Button {
                Task {
                    for g in store.groups {
                        await store.testGroup(g.name, api: kernel.apiClient)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .semibold))
                    Text("测全部").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ChungHwa.Palette.brass)
                        .shadow(color: ChungHwa.Palette.brass.opacity(0.35), radius: 1, y: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(kernel.apiClient == nil)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(ChungHwa.Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    // MARK: states / banners

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug")
                .font(.system(size: 44)).foregroundStyle(ChungHwa.Palette.faint)
            Text("内核未运行")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("在概览页启动内核以查看代理分组。")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var noGroupsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44)).foregroundStyle(ChungHwa.Palette.faint)
            Text("暂无代理分组")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("当前配置不含 `proxy-groups`，请在设置里编辑 YAML。")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(ChungHwa.Palette.earth)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ChungHwa.Palette.earth)
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ChungHwa.Palette.fill)
        )
    }
}

// MARK: - Search field

private struct ProxySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.faint)
            TextField("搜索节点…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.text)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ChungHwa.Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ChungHwa.Palette.fill)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
    }
}

// MARK: - View-mode toggle

private struct ViewModeToggle: View {
    @Binding var mode: ProxyViewMode

    var body: some View {
        HStack(spacing: 0) {
            iconButton(systemName: "square.grid.2x2", active: mode == .grid) { mode = .grid }
            iconButton(systemName: "list.bullet",     active: mode == .list) { mode = .list }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ChungHwa.Palette.fill)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
    }

    private func iconButton(systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? ChungHwa.Palette.pillBg : Color.clear)
                        .shadow(color: active ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Group card

private struct ProxyGroupCard: View {
    let group: MihomoProxy
    let query: String
    let sort: ProxySort
    let mode: ProxyViewMode
    @Binding var isOpen: Bool

    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    private var visibleNames: [String] {
        let names = group.all ?? []
        let filtered: [String]
        if query.isEmpty {
            filtered = names
        } else {
            let q = query.lowercased()
            filtered = names.filter { name in
                if name.lowercased().contains(q) { return true }
                if let p = store.proxy(name), p.type.lowercased().contains(q) { return true }
                return false
            }
        }
        switch sort {
        case .defaultOrder:
            return filtered
        case .name:
            return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .latency:
            return filtered.sorted { lhs, rhs in
                let l = store.proxy(lhs)?.lastDelay ?? 9999
                let r = store.proxy(rhs)?.lastDelay ?? 9999
                return l < r
            }
        }
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

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isOpen.toggle() }
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
                    Text("\(group.all?.count ?? 0) 节点")
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
            withAnimation(.snappy(duration: 0.18)) { isOpen.toggle() }
        }
    }

    @ViewBuilder
    private var selectedSubtitle: some View {
        if let now = group.now {
            HStack(spacing: 6) {
                Text("已选:")
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
            Text("最快 \(ms) ms")
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
            HStack(spacing: 5) {
                if isTesting {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(isTesting ? "测试中" : "测试")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
            .opacity(isTesting ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isTesting || kernel.apiClient == nil)
    }

    // MARK: body

    @ViewBuilder
    private func body(for names: [String]) -> some View {
        if names.isEmpty {
            Text("没有匹配 \"\(query)\" 的节点")
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
                    NodeCard(
                        name: name,
                        proxy: store.proxy(name),
                        isSelected: name == group.now,
                        isSwitchable: group.isUserSwitchable,
                        isTesting: isTesting,
                        onSelect: { select(name) }
                    )
                }
            }
            .padding(10)
        } else {
            VStack(spacing: 1) {
                listHeader
                ForEach(names, id: \.self) { name in
                    NodeRow(
                        name: name,
                        proxy: store.proxy(name),
                        isSelected: name == group.now,
                        isSwitchable: group.isUserSwitchable,
                        isTesting: isTesting,
                        onSelect: { select(name) }
                    )
                }
            }
            .padding(6)
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 13)
            Text("名字")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("协议")
                .frame(width: 90, alignment: .leading)
            Text("测试")
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

// MARK: - Node card (grid)

private struct NodeCard: View {
    let name: String
    let proxy: MihomoProxy?
    let isSelected: Bool
    let isSwitchable: Bool
    let isTesting: Bool
    let onSelect: () -> Void

    @State private var shimmer: Bool = false

    private var pingValue: Int { proxy?.lastDelay ?? 0 }
    private var pingColor: Color {
        pingValue == 0 ? ChungHwa.Palette.faint : ChLatency.color(pingValue)
    }
    /// 0…1 fill width for the latency bar.
    private var pingFraction: Double {
        guard pingValue > 0 else { return 0 }
        let raw = 1.0 - Double(pingValue) / 250.0
        return max(0.08, min(1.0, raw))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                row1
                row2
                latencyBar
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected
                          ? ChungHwa.Palette.brass.opacity(0.10)
                          : ChungHwa.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? ChungHwa.Palette.brass : ChungHwa.Palette.line,
                                  lineWidth: 0.5)
            )
            .shadow(color: isSelected ? ChungHwa.Palette.brass.opacity(0.20) : .black.opacity(0.02),
                    radius: isSelected ? 1 : 0.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSwitchable && !isSelected)
        .help(isSwitchable ? "点击选择" : "由 \(proxy?.type ?? "分组") 自动选择")
    }

    private var row1: some View {
        HStack(spacing: 7) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                ZStack {
                    Circle().fill(ChungHwa.Palette.brass)
                        .frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var row2: some View {
        HStack(spacing: 6) {
            if let p = proxy {
                Text(p.type.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(ChungHwa.Palette.fill)
                    )
            }
            Spacer()
            if isTesting {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 8, height: 8)
                    Text("测试中…")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.brass)
                        .monospacedDigit()
                }
            } else {
                Text(pingValue == 0 ? "—" : "\(pingValue) ms")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(pingColor)
                    .monospacedDigit()
            }
        }
    }

    private var latencyBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ChungHwa.Palette.fill)
                if isTesting {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ChungHwa.Palette.brass.opacity(0),
                                    ChungHwa.Palette.brass,
                                    ChungHwa.Palette.brass.opacity(0),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: shimmer ? geo.size.width * 0.5 : -geo.size.width * 0.5)
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false),
                                   value: shimmer)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .onAppear { shimmer = true }
                        .onDisappear { shimmer = false }
                } else if pingValue > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pingColor)
                        .frame(width: geo.size.width * pingFraction)
                        .animation(.easeInOut(duration: 0.28), value: pingFraction)
                }
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Node row (list)

private struct NodeRow: View {
    let name: String
    let proxy: MihomoProxy?
    let isSelected: Bool
    let isSwitchable: Bool
    let isTesting: Bool
    let onSelect: () -> Void

    private var pingValue: Int { proxy?.lastDelay ?? 0 }
    private var pingColor: Color {
        pingValue == 0 ? ChungHwa.Palette.faint : ChLatency.color(pingValue)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                radio
                    .frame(width: 13)
                Text(name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(proxy?.type.uppercased() ?? "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(width: 90, alignment: .leading)
                Text(pingValue > 0 ? "已测" : "—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .frame(width: 70, alignment: .leading)
                latencyTrailing
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? ChungHwa.Palette.brass.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSwitchable && !isSelected)
        .help(isSwitchable ? "点击选择" : "由 \(proxy?.type ?? "分组") 自动选择")
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? ChungHwa.Palette.brass : ChungHwa.Palette.line,
                              lineWidth: 1.4)
                .background(
                    Circle().fill(isSelected ? ChungHwa.Palette.brass : Color.clear)
                )
                .frame(width: 13, height: 13)
            if isSelected {
                Circle().fill(.white).frame(width: 4, height: 4)
            }
        }
    }

    @ViewBuilder
    private var latencyTrailing: some View {
        if isTesting {
            Text("…")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(ChungHwa.Palette.brass)
                .monospacedDigit()
        } else {
            Text(pingValue == 0 ? "—" : "\(pingValue) ms")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(pingColor)
                .monospacedDigit()
        }
    }
}
