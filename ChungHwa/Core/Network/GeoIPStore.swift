import Foundation
import Observation
import OSLog

/// In-memory + on-disk cache of `IP → ISO country code`, fed by the
/// ipwho.is HTTPS endpoint.
///
/// Why not bundle MaxMind: the GeoLite2-Country .mmdb is several MB and
/// requires a license-key download flow. For a desktop UI that just needs a
/// flag next to each connection row, a remote HTTPS lookup with persistent
/// caching is dramatically simpler — every IP is queried at most once across
/// the lifetime of the app.
///
/// Why ipwho.is: free, no API key, and serves over HTTPS so macOS App
/// Transport Security doesn't block the request. ip-api.com only offers
/// HTTPS on its paid tier, and plain HTTP is ATS-blocked by default — the
/// reason the previous implementation silently returned empty country codes.
///
/// Usage:
/// - Views call `resolve(ips:)` with the set of destination IPs they want
///   flags for. New (uncached) entries are queued and flushed in a
///   bounded-concurrency burst with a 0.4s debounce so a fast-changing
///   connection list coalesces into a single round of requests per burst.
/// - Views read `country(for:)` synchronously per row. A miss schedules the
///   IP for the next batch and returns nil; the next time the view body is
///   evaluated (which happens on every connections-store snapshot) the
///   answer will be there.
///
/// Network: ipwho.is is a third-party HTTPS geo service, not routed
/// through mihomo. We use an ephemeral URLSession with a 5s timeout so a
/// flaky network can't stall the UI.
///
/// Privacy: we send destination IPs (which the user is already connecting
/// to) to ipwho.is. Source IPs and any other metadata are never sent.
@Observable
@MainActor
final class GeoIPStore {

    // MARK: - Public state

    /// IP → ISO 3166-1 alpha-2 country code. The sentinel `"LAN"` is used
    /// for private / loopback / link-local addresses we deliberately don't
    /// query upstream for.
    private(set) var countryByIP: [String: String] = [:]

    /// IPs awaiting the next batch flush. Used purely to gate the debounce
    /// task; views don't read this directly.
    private(set) var pendingIPs: Set<String> = []

    // MARK: - Internals

    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private var pendingFlushCount: Int = 0
    @ObservationIgnored private let log = Logger(
        subsystem: "com.tzaigroup.chunghwa", category: "geoip")
    @ObservationIgnored private let session: URLSession

    /// Sentinel value persisted in the cache for private / loopback IPs so
    /// we don't repeatedly classify them on every cold start.
    private static let lanSentinel = "LAN"

    /// Maximum in-flight HTTPS requests at once. ipwho.is is per-IP, so
    /// we fan out — but unbounded parallelism would hammer the service
    /// and risk getting rate-limited.
    private static let maxConcurrent = 6

    /// How long we wait after the most-recent `resolve(ips:)` before
    /// firing the next HTTP burst. Long enough to coalesce a burst of
    /// per-frame connections updates, short enough to feel live.
    private static let debounce: TimeInterval = 0.4

    /// Flush the on-disk cache after this many new entries, so a single
    /// long session doesn't accumulate hundreds of un-persisted lookups.
    private static let persistEvery: Int = 20

    // MARK: - Init

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("ChungHwa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheURL = dir.appendingPathComponent("geoip-cache.json")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)

        loadCache()
    }

    // MARK: - Public API

    /// O(1) cache read used by view bodies. On miss, schedules a batch
    /// lookup that will populate the cache so the next render finds it.
    /// Returns the literal sentinel `"LAN"` for private/loopback IPs.
    func country(for ip: String) -> String? {
        guard !ip.isEmpty else { return nil }
        if let hit = countryByIP[ip] { return hit }

        // Private IPs are answered locally — no HTTP needed.
        if Self.isPrivateOrLoopback(ip) {
            countryByIP[ip] = Self.lanSentinel
            return Self.lanSentinel
        }

        // Public miss: queue and let the debounce kick off.
        if !pendingIPs.contains(ip) {
            pendingIPs.insert(ip)
            scheduleLookup()
        }
        return nil
    }

    /// Bulk variant for views holding a set of currently-visible IPs. Adds
    /// every uncached public address to the pending queue and (re)arms the
    /// debounce. Cheap to call on every snapshot.
    func resolve(ips: Set<String>) {
        var added = false
        for ip in ips where !ip.isEmpty {
            if countryByIP[ip] != nil { continue }
            if Self.isPrivateOrLoopback(ip) {
                countryByIP[ip] = Self.lanSentinel
                continue
            }
            if pendingIPs.insert(ip).inserted {
                added = true
            }
        }
        if added {
            scheduleLookup()
        }
    }

    /// Drop pending state. Caller invokes this on kernel restart so we
    /// don't carry stale work over a clean transition. The persistent
    /// cache is intentionally preserved — IP→country mappings don't
    /// expire on a kernel cycle.
    func reset() {
        lookupTask?.cancel()
        lookupTask = nil
        pendingIPs.removeAll()
    }

    // MARK: - Debounced batch driver

    private func scheduleLookup() {
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.debounce * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.flushPending()
        }
    }

    /// Drain the pending queue with bounded concurrency. ipwho.is is
    /// per-IP, so we issue up to `maxConcurrent` requests in parallel and
    /// stream results back to the cache.
    private func flushPending() async {
        guard !pendingIPs.isEmpty else { return }
        let batch = Array(pendingIPs)
        pendingIPs.removeAll()

        let session = self.session
        let collected = await withTaskGroup(of: (String, String?).self,
                                            returning: [(String, String)].self) { group in
            var iter = batch.makeIterator()
            var inFlight = 0
            var hits: [(String, String)] = []

            // Seed up to maxConcurrent fetches.
            while inFlight < Self.maxConcurrent, let ip = iter.next() {
                group.addTask { (ip, await Self.queryOne(session: session, ip: ip)) }
                inFlight += 1
            }

            while let (ip, code) = await group.next() {
                inFlight -= 1
                if let code, !code.isEmpty {
                    hits.append((ip, code))
                }
                if let next = iter.next() {
                    group.addTask { (next, await Self.queryOne(session: session, ip: next)) }
                    inFlight += 1
                }
            }
            return hits
        }

        guard !collected.isEmpty else {
            log.debug("geoip flush: 0/\(batch.count, privacy: .public) resolved")
            return
        }

        for (ip, code) in collected {
            countryByIP[ip] = code
        }
        log.debug("geoip flush: \(collected.count, privacy: .public)/\(batch.count, privacy: .public) resolved")
        pendingFlushCount += collected.count
        if pendingFlushCount >= Self.persistEvery {
            pendingFlushCount = 0
        }
        // Either threshold hit OR end of a quiet burst — persist either way
        // so a quiet session still ends up on disk.
        persistCache()
    }

    // MARK: - HTTP

    /// Look up a single IP via api.country.is. Returns the ISO 3166-1
    /// alpha-2 country code or nil on any failure. country.is's free tier
    /// has a much higher rate limit than ipwho.is (which we used previously
    /// and routinely 429'd from with 6 concurrent fetches), and the response
    /// payload is just `{"ip":"…","country":"US"}` — minimal to decode.
    /// Failures are silently dropped — callers re-queue on the next miss.
    private static func queryOne(session: URLSession, ip: String) async -> String? {
        guard let url = URL(string: "https://api.country.is/\(ip)") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let entry = try JSONDecoder().decode(CountryISEntry.self, from: data)
            guard let code = entry.country, !code.isEmpty else { return nil }
            return code.uppercased()
        } catch {
            return nil
        }
    }

    private struct CountryISEntry: Decodable {
        let country: String?
    }

    // MARK: - Flag emoji

    /// Convert an ISO 3166-1 alpha-2 country code to a regional-indicator
    /// flag emoji. "JP" → 🇯🇵. Returns "" for inputs that aren't two ASCII
    /// letters; "LAN" sentinel returns a house glyph.
    static func flagEmoji(iso: String) -> String {
        if iso == lanSentinel { return "🏠" }
        let upper = iso.uppercased()
        guard upper.count == 2 else { return "" }
        let base: UInt32 = 0x1F1E6 - 0x41
        var out = ""
        for ch in upper.unicodeScalars {
            guard (0x41...0x5A).contains(ch.value),
                  let scalar = Unicode.Scalar(base + ch.value)
            else { return "" }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    // MARK: - Private-range classifier

    /// Returns true for IPs we should never send to the geo service: RFC1918,
    /// CGNAT, loopback, link-local (v4 and v6), unique-local v6 and the v6
    /// loopback.
    static func isPrivateOrLoopback(_ ip: String) -> Bool {
        if ip.isEmpty { return true }

        if ip.contains(":") {
            // IPv6 — case-insensitive prefix match is enough for the
            // canonical forms mihomo emits.
            let lower = ip.lowercased()
            if lower == "::1" || lower == "::" { return true }
            if lower.hasPrefix("fe80:") { return true }            // link-local
            // Unique local: fc00::/7  → first byte 1111 110x, i.e. fc__ or fd__.
            if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }
            return false
        }

        // IPv4
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]),
              let b = Int(parts[1])
        else { return false }
        if a == 10 { return true }                                 // 10/8
        if a == 127 { return true }                                // 127/8
        if a == 169 && b == 254 { return true }                    // 169.254/16
        if a == 172 && (16...31).contains(b) { return true }       // 172.16/12
        if a == 192 && b == 168 { return true }                    // 192.168/16
        if a == 100 && (64...127).contains(b) { return true }      // 100.64/10 CGNAT
        return false
    }

    // MARK: - Persistence

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            countryByIP = decoded
            log.debug("loaded \(decoded.count, privacy: .public) cached geoip entries")
        } catch {
            log.error("geoip cache load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Atomic write so a crash mid-flush can never leave a half-written
    /// cache file behind. Snapshot the dict before hopping off the main
    /// actor so the file work doesn't block the UI.
    private func persistCache() {
        let snapshot = countryByIP
        let url = cacheURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: snapshot, options: [.sortedKeys])
                try data.write(to: url, options: [.atomic])
            } catch {
                // Fail quiet — the in-memory cache is still authoritative
                // for this session; we'll retry on the next batch.
            }
        }
    }
}
