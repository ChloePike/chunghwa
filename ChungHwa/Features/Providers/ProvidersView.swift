import SwiftUI

/// Subscription / proxy-set providers. Mihomo exposes these via
/// `/providers/proxies` and `/providers/rules`; we already have rule
/// providers wired in `RuleStore`, but proxy providers (the YAML-side
/// concept of subscriptions) need their own model + store. Until that
/// lands, this screen surfaces what we already know via `ProfileStore` —
/// each URL-source profile is effectively a proxy-set provider — and
/// reuses `RuleStore.providers` for the rules half.
struct ProvidersView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProfileStore.self) private var profiles
    @Environment(RuleStore.self) private var ruleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                proxyProvidersCard
                ruleProvidersCard
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ChungHwa.Palette.bg)
        .navigationTitle("Providers")
        .task(id: kernel.apiClient == nil ? "off" : "on") {
            await ruleStore.refresh(api: kernel.apiClient)
        }
    }

    private var subscriptionProfiles: [Profile] {
        profiles.profiles.filter { if case .url = $0.source { true } else { false } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Providers")
                .font(ChungHwa.Typography.serif(20, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Text("\(subscriptionProfiles.count) proxy · \(ruleStore.providers.count) rule")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var proxyProvidersCard: some View {
        ChCardWithHeader("Proxy providers",
                         systemImage: "shippingbox",
                         iconColor: ChungHwa.Palette.patina) {
            if subscriptionProfiles.isEmpty {
                Text("No subscription profiles. Add one in Profiles → From URL…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(subscriptionProfiles.enumerated()), id: \.element.id) { i, p in
                        if i > 0 {
                            Rectangle().fill(ChungHwa.Palette.lineSoft).frame(height: 0.5)
                        }
                        proxyRow(p)
                    }
                }
            }
        }
    }

    private func proxyRow(_ p: Profile) -> some View {
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

    private var ruleProvidersCard: some View {
        ChCardWithHeader("Rule providers",
                         systemImage: "list.bullet.rectangle",
                         iconColor: ChungHwa.Palette.brass) {
            if ruleStore.providers.isEmpty {
                Text(kernel.apiClient == nil
                     ? "Kernel is not running."
                     : "No rule-set providers in the active profile.")
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
                Text("\(p.behavior) · \(p.type) · \(p.ruleCount) rules")
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
