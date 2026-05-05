import Foundation
import OSLog

/// Manages the setuid-root mihomo binary that lives at a stable, app-independent
/// location: `/Library/PrivilegedHelperTools/org.clash.ChungHwa.mihomo`.
///
/// Why a dedicated location instead of stamping setuid onto the bundled /
/// managed / custom binary directly:
///   - touching the binary inside the .app bundle invalidates the ad-hoc
///     signature and gets reset on every brew upgrade or Xcode rebuild.
///   - setuid state was previously per-source; switching custom/managed/bundled
///     would silently un-root TUN.
/// `/Library/PrivilegedHelperTools/` is the Apple-blessed home for privileged
/// helpers, so the file survives app reinstalls, brew upgrades, Xcode rebuilds,
/// and is orthogonal to which source the resolver picked.
///
/// We delegate the actual privilege escalation to
/// `osascript … with administrator privileges`, which surfaces the system auth
/// prompt — no separate XPC helper to install or maintain.
///
/// NOT `@MainActor`: `Process.waitUntilExit()` is a synchronous blocking call.
/// Pinning this struct to MainActor would freeze the entire UI for the duration
/// of the auth prompt and leave it stuck if the user cancels (this was the
/// "can't retry after cancel" bug).
struct KernelPrivilegeHelper {
    static let log = Logger(subsystem: "org.clash.ChungHwa", category: "privilege")

    /// Stable, root-owned path the setuid kernel lives at after the user
    /// authorizes. Survives app reinstalls, brew upgrades, Xcode rebuilds.
    static let privilegedBinaryPath = "/Library/PrivilegedHelperTools/org.clash.ChungHwa.mihomo"

    /// True iff the file at `privilegedBinaryPath` exists, is owned by root,
    /// and has the setuid bit set. Synchronous; cheap stat call.
    static func isPrivileged() -> Bool {
        var st = stat()
        guard stat(privilegedBinaryPath, &st) == 0 else { return false }
        let isRoot = st.st_uid == 0
        let isSetuid = (st.st_mode & UInt16(S_ISUID)) != 0
        return isRoot && isSetuid
    }

    /// One-shot privilege grant. Reads `sourcePath`, copies it to
    /// `privilegedBinaryPath`, chowns it to root:wheel, chmod u+s.
    /// Returns when the file is in place. Throws on user-cancel of the auth
    /// prompt or any shell failure (with a Chinese-friendly
    /// `localizedDescription`).
    static func grantPrivileges(sourcePath: String) async throws {
        let src = sourcePath.replacingOccurrences(of: "\"", with: "\\\"")
        let dst = privilegedBinaryPath.replacingOccurrences(of: "\"", with: "\\\"")
        // One osascript invocation = one auth prompt, regardless of how many
        // shell commands we chain inside.
        let shell = "mkdir -p /Library/PrivilegedHelperTools && cp \\\"\(src)\\\" \\\"\(dst)\\\" && chown root:wheel \\\"\(dst)\\\" && chmod u+s \\\"\(dst)\\\""
        let script = "do shell script \"\(shell)\" with administrator privileges"
        try await runOsascript(script: script, failurePrefix: "授权失败")
    }

    /// Removes the privileged file. Same osascript path as grant; no-op if
    /// the file is already gone.
    static func revokePrivileges() async throws {
        let dst = privilegedBinaryPath.replacingOccurrences(of: "\"", with: "\\\"")
        let shell = "rm -f \\\"\(dst)\\\""
        let script = "do shell script \"\(shell)\" with administrator privileges"
        try await runOsascript(script: script, failurePrefix: "撤销失败")
    }

    /// Runs an admin-authorized shell snippet via osascript. The blocking
    /// `waitUntilExit()` runs on a background thread via `Task.detached` so
    /// the main UI stays responsive while the password prompt is up.
    private static func runOsascript(script: String, failurePrefix: String) async throws {
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
                if raw.contains("User canceled") || raw.contains("用户已取消") || (proc.terminationStatus == 1 && raw.isEmpty) {
                    msg = "已取消授权"
                } else {
                    msg = raw.isEmpty ? failurePrefix : raw
                }
                log.error("privileged op failed: \(msg, privacy: .public)")
                throw NSError(
                    domain: "ChungHwa.Privilege",
                    code: Int(proc.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: msg]
                )
            }
        }.value
    }
}
