import SwiftUI

/// Generic placeholder for screens whose UI is part of the next-phase
/// redesign work but whose data layer is not wired yet. Mirrors the
/// `StubScreen` from `design/src/app.jsx`.
struct StubScreen: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(title)
                .font(ChungHwa.Typography.serif(22, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.3)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .background(ChungHwa.Palette.bg)
        .navigationTitle(title)
    }
}

struct TrafficStatsView: View {
    var body: some View {
        StubScreen(title: "Traffic Stats",
                   subtitle: "Detailed bandwidth, by hour, day, and month.")
    }
}

struct TopologyView: View {
    var body: some View {
        StubScreen(title: "Topology",
                   subtitle: "Visual proxy chain map.")
    }
}

struct RouteMapView: View {
    var body: some View {
        StubScreen(title: "Route Map",
                   subtitle: "Live geographic view of active connections.")
    }
}

struct ProvidersView: View {
    var body: some View {
        StubScreen(title: "Providers",
                   subtitle: "Subscription sources and their nodes.")
    }
}

struct ProfilesView: View {
    var body: some View {
        StubScreen(title: "Profiles",
                   subtitle: "Active configuration files.")
    }
}

struct AdvancedView: View {
    var body: some View {
        StubScreen(title: "Advanced",
                   subtitle: "Kernel logs, connection optimization, DNS, LAN, proxy auth.")
    }
}
