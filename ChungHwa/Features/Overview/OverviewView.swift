import SwiftUI

/// Overview dashboard. Top-level only reads `KernelController` + a few store
/// identities; every value that ticks at 1Hz lives inside a leaf so the page
/// doesn't re-evaluate per sample.
struct OverviewView: View {
    @Environment(KernelController.self) private var kernel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LiveTrafficCard()

                // Three short cards in one row — same intrinsic content height
                // so the row reads as a clean band. Proxy groups goes full
                // width below since its row count varies wildly.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    NetworkCard()
                    ResourcesCard()
                    SubscriptionHealthCard()
                }

                ProxyGroupsCard()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
        }
        .background(ChungHwa.Palette.bg)
    }
}

/// Posts the sidebar-switch notification ContentView listens for.
func switchTab(_ tab: SidebarTab) {
    NotificationCenter.default.post(name: .chungHwaSwitchTab, object: tab.rawValue)
}

/// Shared row heights so the three overview cards line up at the same
/// vertical positions regardless of internal content.
let statTopRowHeight: CGFloat = 54
let statBottomRowHeight: CGFloat = 36
