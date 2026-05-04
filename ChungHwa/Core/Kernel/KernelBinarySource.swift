import Foundation

enum KernelBinarySource: Equatable, Sendable {
    case bundled
    case managed
    case custom

    var displayName: String {
        switch self {
        case .bundled: return "Bundled"
        case .managed: return "Managed"
        case .custom:  return "Custom"
        }
    }
}

struct KernelBinary: Equatable, Sendable {
    let url: URL
    let source: KernelBinarySource
}
