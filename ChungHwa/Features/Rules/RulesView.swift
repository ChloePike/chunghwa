import SwiftUI

/// Bone & Brass on Patina reskin of the Rules screen.
///
/// One `ChCard` wrapping a 5-column table (#, TYPE, MATCH, ACTION, HITS) with a
/// search input + refresh button toolbar above. If the running config declares
/// rule-providers, a thin banner above the card lists them with an "Update"
/// button per row.
struct RulesView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(RuleStore.self) private var store

    @State private var query: String = ""
    @State private var typeFilter: String? = nil
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if !typeCounts.isEmpty {
                typeFilterRow
            }
            if !store.providers.isEmpty {
                providersBanner
            }
            card
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .task(id: kernel.apiClient == nil ? "off" : "on") {
            await store.refresh(api: kernel.apiClient)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chungHwaFocusFilter)) { _ in
            filterFocused = true
        }
    }

    // MARK: - Filtering

    private var filtered: [MihomoRule] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.rules.filter { rule in
            if let t = typeFilter, rule.type != t { return false }
            if q.isEmpty { return true }
            return rule.type.lowercased().contains(q)
                || rule.payload.lowercased().contains(q)
                || rule.proxy.lowercased().contains(q)
        }
    }

    private var typeCounts: [(type: String, count: Int)] {
        let grouped = Dictionary(grouping: store.rules, by: { $0.type }).mapValues(\.count)
        return grouped
            .filter { $0.value >= 1 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { (type: $0.key, count: $0.value) }
    }

    private var hasActiveFilter: Bool {
        typeFilter != nil ||
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Toolbar (search + refresh)

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                TextField("过滤规则", text: $query)
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
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )

            Text(countText)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .monospacedDigit()

            Spacer(minLength: 0)

            iconButton(systemName: "arrow.clockwise", size: 12) {
                Task { await store.refresh(api: kernel.apiClient) }
            }
            .disabled(kernel.apiClient == nil || store.isRefreshing)
        }
    }

    private var countText: String {
        let total = store.rules.count
        let shown = filtered.count
        if shown == total { return "\(total) 条规则" }
        return "\(shown) / \(total) 条规则"
    }

    // MARK: - Type filter chips

    private var typeFilterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(label: "全部", count: store.rules.count, isActive: typeFilter == nil) {
                        typeFilter = nil
                    }
                    ForEach(typeCounts, id: \.type) { entry in
                        typeChip(
                            label: entry.type,
                            count: entry.count,
                            isActive: typeFilter == entry.type
                        ) {
                            typeFilter = (typeFilter == entry.type) ? nil : entry.type
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 1)
            }
            if hasActiveFilter {
                Text("显示 \(filtered.count) / \(store.rules.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
            }
        }
    }

    private func typeChip(label: String,
                          count: Int,
                          isActive: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(ChungHwa.Typography.mono(10, weight: .semibold))
                    .foregroundStyle(isActive ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? ChungHwa.Palette.brass : ChungHwa.Palette.faint)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive
                          ? ChungHwa.Palette.brass.opacity(0.20)
                          : Color.clear)
                    .strokeBorder(
                        isActive ? ChungHwa.Palette.brass : ChungHwa.Palette.line,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Providers banner

    private var providersBanner: some View {
        ChCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("规则提供方")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(ChungHwa.Palette.faint)
                VStack(spacing: 0) {
                    ForEach(Array(store.providers.enumerated()), id: \.element.id) { idx, p in
                        HStack(spacing: 10) {
                            Text(p.name)
                                .font(ChungHwa.Typography.mono(11.5, weight: .semibold))
                                .foregroundStyle(ChungHwa.Palette.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(p.type)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(ChungHwa.Palette.faint)
                            Text(p.behavior)
                                .font(.system(size: 10.5))
                                .foregroundStyle(ChungHwa.Palette.faint)
                            Spacer(minLength: 0)
                            Text("\(p.ruleCount) 条规则")
                                .font(.system(size: 11))
                                .foregroundStyle(ChungHwa.Palette.dim)
                                .monospacedDigit()
                            updateButton(for: p)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle()
                                    .fill(ChungHwa.Palette.lineSoft)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateButton(for p: MihomoRuleProvider) -> some View {
        let pending = store.updatingProviders.contains(p.name)
        return Button {
            Task { await store.updateProvider(p.name, api: kernel.apiClient) }
        } label: {
            HStack(spacing: 4) {
                if pending {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                }
                Text("更新")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(pending || kernel.apiClient == nil)
    }

    // MARK: - Card / table

    @ViewBuilder
    private var card: some View {
        ChCard(padding: 0) {
            if kernel.apiClient == nil {
                emptyState(title: "内核未运行",
                           system: "powerplug",
                           subtitle: "mihomo 启动后规则会显示在这里。")
            } else {
                VStack(spacing: 0) {
                    headerRow
                    if filtered.isEmpty {
                        emptyState(title: store.rules.isEmpty ? "暂无规则" : "无匹配",
                                   system: "list.bullet.rectangle",
                                   subtitle: store.rules.isEmpty
                                       ? "请加载含路由规则的配置。"
                                       : "请换一个搜索词。")
                    } else {
                        rowList
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        RulesGridRow(
            index:  { headerCell("#", alignment: .leading) },
            type:   { headerCell("类型", alignment: .leading) },
            match:  { headerCell("匹配", alignment: .leading) },
            action: { headerCell("动作", alignment: .leading) },
            hits:   { headerCell("命中", alignment: .trailing) }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    private func headerCell(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(ChungHwa.Palette.faint)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var rowList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { rule in
                    RuleRowView(rule: rule, displayIndex: indexFor(rule))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                }
            }
        }
    }

    /// Pull the original index back out of the synthesised id (`"<idx>|..."`),
    /// so search results still display the rule's true position in the list.
    private func indexFor(_ rule: MihomoRule) -> Int {
        if let bar = rule.id.firstIndex(of: "|"),
           let n = Int(rule.id[..<bar]) {
            return n
        }
        return 0
    }

    // MARK: - Empty state

    private func emptyState(title: String, system: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: system)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }

    // MARK: - Icon button (matches design's btnGhost 28×28)

    private func iconButton(systemName: String,
                            size: CGFloat,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ChungHwa.Palette.fill)
                        .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct RuleRowView: View {
    let rule: MihomoRule
    let displayIndex: Int

    var body: some View {
        RulesGridRow(
            index: {
                Text("\(displayIndex)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            type: {
                Text(rule.type)
                    .font(ChungHwa.Typography.mono(10.5, weight: .bold))
                    .foregroundStyle(typeColor(rule.type))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(rule.type)
            },
            match: {
                Text(rule.payload.isEmpty ? "—" : rule.payload)
                    .font(ChungHwa.Typography.mono(11.5))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(rule.payload)
            },
            action: {
                Text(rule.proxy)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(rule.proxy == "DIRECT" || rule.proxy == "REJECT"
                                     ? ChungHwa.Palette.dim
                                     : ChungHwa.Palette.patina)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            hits: {
                Text("—")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
    }

    /// Map mihomo's rule kinds onto the Bone & Brass palette so the table
    /// reads at a glance.
    private func typeColor(_ type: String) -> Color {
        switch type {
        case "DOMAIN-SUFFIX", "DOMAIN-KEYWORD":
            return ChungHwa.Palette.patina
        case "GEOIP", "IP-CIDR":
            return ChungHwa.Palette.brass
        case "PROCESS-NAME":
            return ChungHwa.Palette.earth
        case "MATCH":
            return ChungHwa.Palette.faint
        default:
            return ChungHwa.Palette.faint
        }
    }
}

// MARK: - Shared 5-column grid

/// `# (32) | TYPE (130) | MATCH (1fr) | ACTION (130) | HITS (70)`
private struct RulesGridRow<Index: View, Type: View, Match: View,
                            Action: View, Hits: View>: View {
    @ViewBuilder var index: () -> Index
    @ViewBuilder var type: () -> Type
    @ViewBuilder var match: () -> Match
    @ViewBuilder var action: () -> Action
    @ViewBuilder var hits: () -> Hits

    var body: some View {
        GeometryReader { geo in
            let fixedSum: CGFloat = 32 + 130 + 130 + 70
            let gapSum: CGFloat = 10 * 4
            let matchW = max(0, geo.size.width - fixedSum - gapSum)

            HStack(spacing: 10) {
                index().frame(width: 32, alignment: .leading)
                type().frame(width: 130, alignment: .leading)
                match().frame(width: matchW, alignment: .leading)
                action().frame(width: 130, alignment: .leading)
                hits().frame(width: 70, alignment: .trailing)
            }
        }
        .frame(height: rowHeight)
    }

    private var rowHeight: CGFloat { 18 }
}
