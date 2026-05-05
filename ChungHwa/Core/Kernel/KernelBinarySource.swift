import Foundation

enum KernelBinarySource: Equatable, Sendable {
    /// `/Library/PrivilegedHelperTools/`, setuid root — used for TUN.
    case privileged
    case custom
    case managed
    case bundled

    var displayName: String {
        switch self {
        case .privileged: return "Privileged"
        case .custom:     return "Custom"
        case .managed:    return "Managed"
        case .bundled:    return "Bundled"
        }
    }
}

struct KernelBinary: Equatable, Sendable {
    let url: URL
    let source: KernelBinarySource
}
