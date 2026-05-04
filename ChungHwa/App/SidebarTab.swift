import Foundation

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case overview, trafficStats, connections, logs
    case topology, routeMap
    case proxies, rules, providers
    case profiles, advanced
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:      return "Overview"
        case .trafficStats:  return "Traffic Stats"
        case .connections:   return "Connections"
        case .logs:          return "Logs"
        case .topology:      return "Topology"
        case .routeMap:      return "Route Map"
        case .proxies:       return "Proxies"
        case .rules:         return "Rules"
        case .providers:     return "Providers"
        case .profiles:      return "Profiles"
        case .advanced:      return "Advanced"
        case .settings:      return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:      return "square.grid.2x2"
        case .trafficStats:  return "chart.line.uptrend.xyaxis"
        case .connections:   return "link"
        case .logs:          return "terminal"
        case .topology:      return "point.3.connected.trianglepath.dotted"
        case .routeMap:      return "map"
        case .proxies:       return "globe"
        case .rules:         return "list.bullet.rectangle"
        case .providers:     return "shippingbox"
        case .profiles:      return "doc.text"
        case .advanced:      return "slider.horizontal.3"
        case .settings:      return "gearshape"
        }
    }
}

struct SidebarSection: Identifiable {
    let id: String
    let header: String?
    let tabs: [SidebarTab]
}

extension SidebarTab {
    /// Sidebar layout, mirroring `design/src/app.jsx` Sidebar(). Settings is
    /// the footer slot — not present in any section.
    static let sections: [SidebarSection] = [
        .init(id: "main",          header: nil,             tabs: [.overview, .trafficStats, .connections, .logs]),
        .init(id: "visualization", header: "Visualization", tabs: [.topology, .routeMap]),
        .init(id: "proxy",         header: "Proxy",         tabs: [.proxies, .rules, .providers]),
        .init(id: "config",        header: "Config",        tabs: [.profiles, .advanced]),
    ]
}
