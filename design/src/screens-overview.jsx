// Overview / Dashboard

function ChTrafficGraph({ dark, data, color = "#34c759", color2 = "#0a84ff", height = 130 }) {
  const t = chTokens({ dark });
  const { up = [], down = [] } = data;
  const W = 560, H = height;
  const max = Math.max(1, ...up, ...down);
  const points = (arr) => arr.map((v, i) => {
    const x = (i / (arr.length - 1)) * W;
    const y = H - (v / max) * (H - 12) - 4;
    return [x, y];
  });
  const linePath = (pts) => pts.length ? "M" + pts.map(p => p.join(",")).join(" L ") : "";
  const areaPath = (pts) => pts.length ? linePath(pts) + ` L ${W},${H} L 0,${H} Z` : "";
  const dn = points(down), upPts = points(up);

  return (
    <div style={{ position: "relative", width: "100%", height }}>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height: "100%", display: "block" }}>
        <defs>
          <linearGradient id="dn-grad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color2} stopOpacity="0.45"/>
            <stop offset="100%" stopColor={color2} stopOpacity="0"/>
          </linearGradient>
          <linearGradient id="up-grad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.35"/>
            <stop offset="100%" stopColor={color} stopOpacity="0"/>
          </linearGradient>
        </defs>
        {/* gridlines */}
        {[0.25, 0.5, 0.75].map(g => (
          <line key={g} x1="0" y1={H * g} x2={W} y2={H * g} stroke={t.line} strokeWidth="0.5"/>
        ))}
        <path d={areaPath(dn)} fill="url(#dn-grad)" />
        <path d={linePath(dn)} fill="none" stroke={color2} strokeWidth="1.5" strokeLinejoin="round"/>
        <path d={areaPath(upPts)} fill="url(#up-grad)" />
        <path d={linePath(upPts)} fill="none" stroke={color} strokeWidth="1.5" strokeLinejoin="round"/>
      </svg>
    </div>
  );
}

function fmtBytes(b) {
  if (b < 1024) return `${b} B`;
  if (b < 1024**2) return `${(b/1024).toFixed(1)} KB`;
  if (b < 1024**3) return `${(b/1024/1024).toFixed(1)} MB`;
  return `${(b/1024/1024/1024).toFixed(2)} GB`;
}

function fmtSpeed(bps) {
  if (bps < 1024) return `${bps.toFixed(0)} B/s`;
  if (bps < 1024**2) return `${(bps/1024).toFixed(1)} KB/s`;
  return `${(bps/1024/1024).toFixed(2)} MB/s`;
}

function ChScreenOverview({ dark, mode, setMode, systemProxy, setSystemProxy, tunMode, setTunMode, traffic, accent, currentNode }) {
  const t = chTokens({ dark });
  const sessionUp = traffic.up.reduce((a,b)=>a+b, 0);
  const sessionDn = traffic.down.reduce((a,b)=>a+b, 0);

  return (
    <div style={{ padding: "12px 28px 28px", display: "flex", flexDirection: "column", gap: 18 }}>
      <ChSectionHeader
        dark={dark}
        title="Overview"
        subtitle={systemProxy ? "Connection is active and routing through ChungHwa." : "System proxy is paused."}
        right={
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ fontSize: 12, color: t.textDim, fontWeight: 500 }}>System Proxy</span>
            <ChToggle checked={systemProxy} onChange={setSystemProxy} dark={dark} accent="#34c759" />
          </div>
        }
      />

      {/* Hero status card — the big "are we on" surface */}
      <ChCard dark={dark} glass="medium" padding={0} radius={18} style={{ overflow: "hidden" }}>
        <div style={{
          padding: "22px 24px 20px",
          background: systemProxy
            ? `linear-gradient(135deg, ${dark ? "rgba(52,199,89,0.16)" : "rgba(52,199,89,0.10)"}, transparent 60%)`
            : "transparent",
          borderBottom: `0.5px solid ${t.line}`,
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div style={{
              width: 56, height: 56, borderRadius: 16,
              background: systemProxy ? STATUS.on.bg : STATUS.idle.bg,
              border: `0.5px solid ${systemProxy ? STATUS.on.ring : STATUS.idle.ring}`,
              display: "flex", alignItems: "center", justifyContent: "center",
              color: systemProxy ? STATUS.on.fg : STATUS.idle.fg,
              position: "relative",
            }}>
              <Icons.shield size={28} stroke={1.6}/>
              {systemProxy && <span style={{
                position: "absolute", top: 4, right: 4,
                width: 8, height: 8, borderRadius: "50%", background: STATUS.on.fg,
                animation: "ch-pulse 1.6s ease-in-out infinite",
                boxShadow: "0 0 6px " + STATUS.on.fg,
              }}/>}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span style={{ fontSize: 18, fontWeight: 700, color: t.text }}>
                  {systemProxy ? "Connected" : "Disconnected"}
                </span>
                <ChBadge status={systemProxy ? "on" : "idle"} dark={dark}>
                  {mode.toUpperCase()}
                </ChBadge>
                {tunMode && <ChBadge status="purple" dark={dark}>TUN</ChBadge>}
              </div>
              <div style={{ fontSize: 13, color: t.textDim, marginTop: 5, display: "flex", gap: 14, flexWrap: "wrap" }}>
                <span>via <strong style={{ color: t.text, fontWeight: 600 }}>{currentNode.flag} {currentNode.name}</strong></span>
                <span>·</span>
                <span>{currentNode.proto}</span>
                <span>·</span>
                <span>{currentNode.ping} ms</span>
              </div>
            </div>
            <ChSegmented
              dark={dark}
              value={mode}
              onChange={setMode}
              options={[
                { value: "rule", label: "Rule" },
                { value: "global", label: "Global" },
                { value: "direct", label: "Direct" },
              ]}
            />
          </div>
        </div>

        {/* Traffic graph */}
        <div style={{ padding: "14px 24px 18px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 18, marginBottom: 8 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#0a84ff" }}/>
              <span style={{ fontSize: 11, color: t.textDim, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5 }}>Down</span>
              <span style={{ fontSize: 13, color: t.text, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
                {fmtSpeed(traffic.down[traffic.down.length-1] || 0)}
              </span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#34c759" }}/>
              <span style={{ fontSize: 11, color: t.textDim, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5 }}>Up</span>
              <span style={{ fontSize: 13, color: t.text, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
                {fmtSpeed(traffic.up[traffic.up.length-1] || 0)}
              </span>
            </div>
            <div style={{ flex: 1 }}/>
            <span style={{ fontSize: 11, color: t.textFaint }}>last 60 s</span>
          </div>
          <ChTrafficGraph dark={dark} data={traffic} />
        </div>
      </ChCard>

      {/* Quick stats grid */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12 }}>
        {[
          { label: "Session ▼", value: fmtBytes(sessionDn * 100), sub: "since 09:42", color: "#0a84ff" },
          { label: "Session ▲", value: fmtBytes(sessionUp * 100), sub: "since 09:42", color: "#34c759" },
          { label: "Connections", value: "127", sub: "12 active", color: "#bf5af2" },
          { label: "Memory", value: "84.2 MB", sub: "0.3% CPU", color: "#ff9f0a" },
        ].map((s) => (
          <ChCard key={s.label} dark={dark} padding={14} radius={12}>
            <div style={{ fontSize: 11, color: t.textDim, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5 }}>{s.label}</div>
            <div style={{ fontSize: 22, fontWeight: 700, color: t.text, marginTop: 6, fontVariantNumeric: "tabular-nums", letterSpacing: -0.3 }}>{s.value}</div>
            <div style={{ fontSize: 11, color: t.textFaint, marginTop: 2 }}>{s.sub}</div>
          </ChCard>
        ))}
      </div>

      {/* Active group + features row */}
      <div style={{ display: "grid", gridTemplateColumns: "1.4fr 1fr", gap: 12 }}>
        <ChCard dark={dark} padding={0} radius={14}>
          <div style={{ padding: "12px 16px", borderBottom: `0.5px solid ${t.line}`, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: t.text }}>Active Selection</div>
            <span style={{ fontSize: 11, color: t.textDim }}>Auto Select · URL Test</span>
          </div>
          <div style={{ padding: "10px 8px" }}>
            {CH_DATA.PROXY_GROUPS[0].nodes.slice(0, 5).map((n) => {
              const active = n.id === currentNode.id;
              const pingColor = n.ping < 80 ? STATUS.on.fg : n.ping < 180 ? STATUS.testing.fg : STATUS.off.fg;
              return (
                <div key={n.id} style={{
                  display: "flex", alignItems: "center", gap: 10,
                  padding: "8px 12px", borderRadius: 8,
                  background: active ? (dark ? "rgba(52,199,89,0.10)" : "rgba(52,199,89,0.08)") : "transparent",
                }}>
                  <span style={{ fontSize: 16, lineHeight: 1, width: 18 }}>{n.flag}</span>
                  <span style={{ fontSize: 13, color: t.text, fontWeight: active ? 600 : 500, flex: 1 }}>{n.name}</span>
                  <span style={{ fontSize: 11, color: t.textFaint, fontVariantNumeric: "tabular-nums" }}>{n.proto}</span>
                  <span style={{
                    fontSize: 12, color: pingColor, fontWeight: 600,
                    fontVariantNumeric: "tabular-nums", width: 56, textAlign: "right",
                  }}>{n.ping} ms</span>
                  {active && <Icons.check size={14} style={{ color: STATUS.on.fg }}/>}
                </div>
              );
            })}
          </div>
        </ChCard>

        <ChCard dark={dark} padding={0} radius={14}>
          <div style={{ padding: "12px 16px", borderBottom: `0.5px solid ${t.line}`, fontSize: 13, fontWeight: 600, color: t.text }}>
            System
          </div>
          <div style={{ padding: 4 }}>
            {[
              { label: "System Proxy", sub: "HTTP / HTTPS / SOCKS5", val: systemProxy, set: setSystemProxy, color: "#34c759" },
              { label: "TUN Mode", sub: "Route all traffic", val: tunMode, set: setTunMode, color: "#bf5af2" },
              { label: "Allow LAN", sub: "Devices on 192.168.x.x", val: true, set: () => {}, color: "#0a84ff" },
              { label: "Auto-start at login", sub: "Launch with macOS", val: false, set: () => {}, color: "#0a84ff" },
            ].map((row, i) => (
              <div key={row.label} style={{
                display: "flex", alignItems: "center", gap: 12,
                padding: "10px 12px",
                borderTop: i ? `0.5px solid ${t.lineSoft}` : "none",
              }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 500, color: t.text }}>{row.label}</div>
                  <div style={{ fontSize: 11, color: t.textFaint, marginTop: 1 }}>{row.sub}</div>
                </div>
                <ChToggle checked={row.val} onChange={row.set} dark={dark} accent={row.color}/>
              </div>
            ))}
          </div>
        </ChCard>
      </div>
    </div>
  );
}

window.ChScreenOverview = ChScreenOverview;
window.ChTrafficGraph = ChTrafficGraph;
window.fmtBytes = fmtBytes;
window.fmtSpeed = fmtSpeed;
