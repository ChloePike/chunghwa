import Foundation

enum ProxiesHelpers {
    static func filterAndSort(names: [String],
                              query: String,
                              sort: ProxySort,
                              store: ProxyStore) -> [String] {
        let filtered: [String]
        if query.isEmpty {
            filtered = names
        } else {
            let q = query.lowercased()
            filtered = names.filter { name in
                if name.lowercased().contains(q) { return true }
                if let p = store.proxy(name), p.type.lowercased().contains(q) { return true }
                return false
            }
        }
        switch sort {
        case .defaultOrder:
            return filtered
        case .name:
            return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .latency:
            return filtered.sorted { lhs, rhs in
                let l = store.proxy(lhs)?.lastDelay ?? 9999
                let r = store.proxy(rhs)?.lastDelay ?? 9999
                return l < r
            }
        }
    }
}
