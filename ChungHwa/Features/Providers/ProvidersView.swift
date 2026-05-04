import SwiftUI

/// Three views onto the "providers" concept that mihomo / our profile
/// store expose:
///
/// 1. **Subscription profiles** — local URL-source profiles that *we*
///    fetch (via `ProfileStore`). These produce the YAML mihomo loads.
/// 2. **Proxy providers** — `/providers/proxies`, i.e. node lists mihomo
///    itself pulls from a subscription URL or file.
/// 3. **Rule providers** — `/providers/rules`, rule-set lists fed into
///    the rule engine.
struct ProvidersView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProfileStore.self) private var profiles
    @Environment(RuleStore.self) private var ruleStore
    @Environment(ProxyProviderStore.self) private var proxyProviderStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                subscriptionProfilesCard
                proxyProvidersCard
                ruleProvidersCard
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ChungHwa.Palette.bg)
        .task(id: kernel.apiClient == nil ? "off" : "on") {
            await ruleStore.refresh(api: kernel.apiClient)
            await proxyProviderStore.refresh(api: kernel.apiClient)
        }
    }

    private var subscriptionProfiles: [Profile] {
        profiles.profiles.filter { if case .url = $0.source { true } else { false } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("提供方")
                .font(ChungHwa.Typography.serif(20, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Text("\(subscriptionProfiles.count) 订阅 · \(proxyProviderStore.providers.count) 代理 · \(ruleStore.providers.count) 规则")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    // MARK: - Subscription profiles (URL-source ProfileStore profiles)

    private var subscriptionProfilesCard: some View {
        ChCardWithHeader("订阅配置",
                         systemImage: "shippingbox",
                         iconColor: ChungHwa.Palette.patina) {
            if subscriptionProfiles.isEmpty {
                Text("暂无订阅配置。可在「配置」页 → 从 URL… 添加。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(subscriptionProfiles.enumerated()), id: \.element.id) { i, p in
                        if i > 0 {
                            Rectangle().fill(ChungHwa.Palette.lineSoft).frame(height: 0.5)
                        }
                        subscriptionRow(p)
                    }
                }
            }
        }
    }

    private func subscriptionRow(_ p: Profile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.brass)
                .frame(width: 22, height: 22)
                .background(ChungHwa.Palette.brass.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                if case .url(let u) = p.source {
                    Text(u.host ?? u.absoluteString)
                        .font(ChungHwa.Typography.mono(10.5))
                        .foregroundStyle(ChungHwa.Palette.faint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(p.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Proxy providers (mihomo /providers/proxies)

    private var proxyProvidersCard: some View {
        ChCardWithHeader("代理提供方",
                         systemImage: "shippingbox",
                         iconColor: ChungHwa.Palette.brass) {
            if proxyProviderStore.providers.isEmpty {
                Text(kernel.apiClient == nil
                     ? "内核未运行。"
                     : "当前配置不含代理提供方。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(proxyProviderStore.providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 {
                            Rectangle().fill(ChungHwa.Palette.lineSoft).frame(height: 0.5)
                        }
                        proxyProviderRow(p)
                    }
                }
            }
        }
    }

    private func proxyProviderRow(_ p: MihomoProxyProvider) -> some View {
        let inFlight = proxyProviderStore.updatingProviders.contains(p.name)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.brass)
                .frame(width: 22, height: 22)
                .background(ChungHwa.Palette.brass.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                Text("\(p.type) · \(p.vehicleType ?? "—")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                if let info = p.subscriptionInfo {
                    if let used = subscriptionUsedLine(info) {
                        Text(used)
                            .font(ChungHwa.Typography.mono(10.5))
                            .foregroundStyle(ChungHwa.Palette.dim)
                    }
                    if let expires = subscriptionExpiresLine(info) {
                        Text(expires)
                            .font(.system(size: 10.5))
                            .foregroundStyle(ChungHwa.Palette.dim)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    Task { await proxyProviderStore.updateProvider(p.name, api: kernel.apiClient) }
                } label: {
                    if inFlight {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ChungHwa.Palette.dim)
                .disabled(kernel.apiClient == nil || inFlight)
                .help("刷新提供方")

                Button {
                    Task { await proxyProviderStore.healthcheck(p.name, api: kernel.apiClient) }
                } label: {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ChungHwa.Palette.dim)
                .disabled(kernel.apiClient == nil || inFlight)
                .help("检查节点健康")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }

    /// e.g. `Used: 14.2 GB / 50 GB`. Returns nil if total is zero/missing,
    /// since "0 / 0" is meaningless for the user.
    private func subscriptionUsedLine(_ info: MihomoProxyProvider.SubscriptionInfo) -> String? {
        let upload = info.Upload ?? 0
        let download = info.Download ?? 0
        let total = info.Total ?? 0
        let used = upload + download
        if total <= 0 && used <= 0 { return nil }
        if total <= 0 {
            return "已用: \(ChFormat.bytes(used))"
        }
        return "已用: \(ChFormat.bytes(used)) / \(ChFormat.bytes(total))"
    }

    /// e.g. `Expires: in 26 days`. mihomo uses `0` to mean never-expires.
    private func subscriptionExpiresLine(_ info: MihomoProxyProvider.SubscriptionInfo) -> String? {
        guard let expire = info.Expire, expire > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(expire))
        return "到期: \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Rule providers

    private var ruleProvidersCard: some View {
        ChCardWithHeader("规则提供方",
                         systemImage: "list.bullet.rectangle",
                         iconColor: ChungHwa.Palette.brass) {
            if ruleStore.providers.isEmpty {
                Text(kernel.apiClient == nil
                     ? "内核未运行。"
                     : "当前配置不含规则集提供方。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ruleStore.providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 {
                            Rectangle().fill(ChungHwa.Palette.lineSoft).frame(height: 0.5)
                        }
                        ruleRow(p)
                    }
                }
            }
        }
    }

    private func ruleRow(_ p: MihomoRuleProvider) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.patina)
                .frame(width: 22, height: 22)
                .background(ChungHwa.Palette.patina.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                Text("\(p.behavior) · \(p.type) · \(p.ruleCount) 条规则")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            Spacer()
            Button {
                Task { await ruleStore.updateProvider(p.name, api: kernel.apiClient) }
            } label: {
                if ruleStore.updatingProviders.contains(p.name) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ChungHwa.Palette.dim)
            .disabled(kernel.apiClient == nil || ruleStore.updatingProviders.contains(p.name))
        }
        .padding(.vertical, 8)
    }
}
