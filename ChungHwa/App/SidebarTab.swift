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
        case .overview:      return "概览"
        case .trafficStats:  return "流量"
        case .connections:   return "连接"
        case .logs:          return "日志"
        case .topology:      return "拓扑"
        case .routeMap:      return "路由"
        case .proxies:       return "代理"
        case .rules:         return "规则"
        case .providers:     return "提供方"
        case .profiles:      return "配置"
        case .advanced:      return "高级"
        case .settings:      return "设置"
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
        .init(id: "visualization", header: "可视化",          tabs: [.topology, .routeMap]),
        .init(id: "proxy",         header: "代理",            tabs: [.proxies, .rules, .providers]),
        .init(id: "config",        header: "配置",            tabs: [.profiles, .advanced]),
    ]
}
