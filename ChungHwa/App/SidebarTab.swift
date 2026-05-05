import Foundation

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case overview, connections, logs
    case topology
    case proxies, rules
    case profiles, advanced
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:      return "概览"
        case .connections:   return "连接"
        case .logs:          return "日志"
        case .topology:      return "拓扑"
        case .proxies:       return "代理"
        case .rules:         return "规则"
        case .profiles:      return "配置"
        case .advanced:      return "高级"
        case .settings:      return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview:      return "gauge.with.dots.needle.50percent"
        case .connections:   return "arrow.left.arrow.right"
        case .logs:          return "terminal"
        case .topology:      return "point.3.connected.trianglepath.dotted"
        case .proxies:       return "globe"
        case .rules:         return "list.bullet.rectangle"
        case .profiles:      return "tray.full"
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
    /// Settings is the footer slot — not present in any section.
    static let sections: [SidebarSection] = [
        .init(id: "main",          header: nil,             tabs: [.overview, .connections, .logs]),
        .init(id: "visualization", header: "可视化",          tabs: [.topology]),
        .init(id: "proxy",         header: "代理",            tabs: [.proxies, .rules]),
        .init(id: "config",        header: "配置",            tabs: [.profiles, .advanced]),
    ]
}
