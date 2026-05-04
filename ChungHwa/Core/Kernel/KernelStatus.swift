import Foundation

enum KernelStatus: Equatable, Sendable {
    case idle
    case starting
    case running(version: String)
    case failed(reason: String)
}
