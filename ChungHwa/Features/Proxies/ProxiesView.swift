import SwiftUI

enum ProxySort: Hashable, CaseIterable {
    case latency, name, defaultOrder
    var label: String {
        switch self {
        case .latency:      return "延迟"
        case .name:         return "名称"
        case .defaultOrder: return "默认"
        }
    }
}

enum ProxyViewMode: Hashable {
    case grid, list
}

struct ProxiesView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    @State private var query: String = ""
    @State private var sort: ProxySort = .defaultOrder
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
                            isOpen: openMap[group.name] ?? false,
                            onToggle: { isOpen in openMap[group.name] = isOpen }
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
            // Hide groups whose nodes are all filtered out.
            let filtered = ProxiesHelpers.filterAndSort(
                names: group.all ?? [],
                query: query, sort: sort, store: store)
            return !filtered.isEmpty || query.isEmpty
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ProxySearchField(text: $query)
                .frame(width: 220)

            ChSeg(
                value: sort,
                onChange: { sort = $0 },
                options: [
                    (.latency, "延迟"),
                    (.name, "名称"),
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
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ChungHwa.Palette.brass)
                            .shadow(color: ChungHwa.Palette.brass.opacity(0.35), radius: 1, y: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(kernel.apiClient == nil)
            .help("测试所有组")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug")
                .font(.system(size: 44)).foregroundStyle(ChungHwa.Palette.faint)
            Text("内核未启动")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("在概览页启动后再来。")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var noGroupsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 44)).foregroundStyle(ChungHwa.Palette.faint)
            Text("没有代理组")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("当前配置里没有 proxy-groups。")
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
