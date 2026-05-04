import Foundation
import OSLog

/// Helper for granting `setuid root` to the active mihomo binary so it can
/// open `/dev/utun` for TUN mode. We delegate the actual privilege escalation
/// to `osascript … with administrator privileges`, which surfaces the system
/// auth prompt — no separate XPC helper to install or maintain.
///
/// NOT `@MainActor`: `Process.waitUntilExit()` is a synchronous blocking
/// call. Pinning this struct to MainActor would freeze the entire UI for
/// the duration of the auth prompt and leave it stuck if the user cancels
/// (which is exactly the bug "取消后没办法继续执行" reported).
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
    /// Throws on cancel or auth failure. The blocking `waitUntilExit()` runs
    /// on a background thread via `Task.detached` so the main UI stays
    /// responsive while the password prompt is up.
    static func grantPrivileges(path: String) async throws {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"chown root:wheel \\\"\(escaped)\\\" && chmod u+s \\\"\(escaped)\\\"\" with administrator privileges"

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let errPipe = Pipe()
            proc.standardError = errPipe
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // osascript user-cancel error is exit code 1 with message
                // "User canceled."; surface a friendlier Chinese message.
                let msg: String
                if raw.contains("User canceled") || raw.contains("用户已取消") || proc.terminationStatus == 1 && raw.isEmpty {
                    msg = "已取消授权"
                } else {
                    msg = raw.isEmpty ? "授权失败" : raw
                }
                log.error("setuid grant failed: \(msg, privacy: .public)")
                throw NSError(
                    domain: "ChungHwa.Privilege",
                    code: Int(proc.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: msg]
                )
            }
        }.value
    }
}
