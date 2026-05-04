import Foundation
import OSLog

/// Helper for granting `setuid root` to the active mihomo binary so it can
/// open `/dev/utun` for TUN mode. We delegate the actual privilege escalation
/// to `osascript … with administrator privileges`, which surfaces the system
/// auth prompt — no separate XPC helper to install or maintain.
@MainActor
struct KernelPrivilegeHelper {
    static let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "privilege")

    /// Returns true if `path` is owned by root and has the setuid bit set.
    static func isPrivileged(path: String) -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        let isRoot = st.st_uid == 0
        let isSetuid = (st.st_mode & UInt16(S_ISUID)) != 0
        return isRoot && isSetuid
    }

    /// Runs an admin-authorized `chown root:wheel + chmod u+s` via osascript.
    /// Throws on cancel or auth failure.
    static func grantPrivileges(path: String) async throws {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"chown root:wheel \\\"\(escaped)\\\" && chmod u+s \\\"\(escaped)\\\"\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "授权失败"
            log.error("setuid grant failed: \(msg, privacy: .public)")
            throw NSError(
                domain: "ChungHwa.Privilege",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }
}
