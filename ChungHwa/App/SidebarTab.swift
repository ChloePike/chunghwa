import Foundation

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case overview, proxies, rules, connections, logs, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:    return "Overview"
        case .proxies:     return "Proxies"
        case .rules:       return "Rules"
        case .connections: return "Connections"
        case .logs:        return "Logs"
        case .settings:    return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:    return "square.grid.2x2"
        case .proxies:     return "globe"
        case .rules:       return "list.bullet.rectangle"
        case .connections: return "link"
        case .logs:        return "terminal"
        case .settings:    return "gear"
        }
    }

    static var primary: [SidebarTab] {
        [.overview, .proxies, .rules, .connections, .logs]
    }
}
