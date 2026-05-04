// Live connections log

function ChScreenConnections({ dark }) {
  const t = chTokens({ dark });
  const [conns, setConns] = React.useState(() => makeInitialConns(14));
  const [paused, setPaused] = React.useState(false);
  const [filter, setFilter] = React.useState("");

  React.useEffect(() => {
    if (paused) return;
    const id = setInterval(() => {
      setConns(prev => {
        const next = [...prev];
        // randomly add/update/finish
        if (Math.random() < 0.7 && next.length < 40) {
          next.unshift(makeConn());
        }
        return next.map(c => ({
          ...c,
          dn: c.live ? c.dn + Math.floor(Math.random() * 80000) : c.dn,
          up: c.live ? c.up + Math.floor(Math.random() * 8000) : c.up,
          dur: c.live ? c.dur + 1 : c.dur,
          live: c.live && Math.random() > 0.04,
        })).slice(0, 40);
      });
    }, 800);
    return () => clearInterval(id);
  }, [paused]);

  const visible = conns.filter(c =>
    !filter || c.host.toLowerCase().includes(filter.toLowerCase()) || c.proc.toLowerCase().includes(filter.toLowerCase())
  );

  return (
    <div style={{ padding: "12px 28px 28px", display: "flex", flexDirection: "column", gap: 14, height: "100%" }}>
      <ChSectionHeader
        dark={dark}
        title="Connections"
        subtitle={`${conns.filter(c => c.live).length} active · ${conns.length} total`}
        right={
          <div style={{ display: "flex", gap: 8 }}>
            <ChGlass dark={dark} radius={8}>
              <div style={{ height: 32, padding: "0 12px", display: "flex", alignItems: "center", gap: 8 }}>
                <Icons.search size={13} style={{ color: t.textDim }}/>
                <input
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="Filter host or process…"
                  style={{
                    border: 0, background: "transparent", outline: "none",
                    color: t.text, fontSize: 12, width: 200, fontFamily: "inherit",
                  }}
                />
              </div>
            </ChGlass>
            <ChGlass dark={dark} radius={8}>
              <button onClick={() => setPaused(p => !p)} style={{
                height: 32, width: 36, border: 0, background: "transparent",
                color: t.text, cursor: "pointer", display: "inline-flex",
                alignItems: "center", justifyContent: "center",
              }}>
                {paused ? <Icons.play size={12}/> : <Icons.pause size={13}/>}
              </button>
            </ChGlass>
            <ChGlass dark={dark} radius={8}>
              <button onClick={() => setConns([])} style={{
                height: 32, width: 36, border: 0, background: "transparent",
                color: t.text, cursor: "pointer", display: "inline-flex",
                alignItems: "center", justifyContent: "center",
              }}>
                <Icons.trash size={13}/>
              </button>
            </ChGlass>
          </div>
        }
      />

      <ChCard dark={dark} padding={0} radius={14} style={{ overflow: "hidden", flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
        <div style={{
          display: "grid",
          gridTemplateColumns: "12px 1.6fr 1fr 90px 90px 84px 80px",
          padding: "10px 16px", gap: 12,
          borderBottom: `0.5px solid ${t.line}`,
          fontSize: 11, fontWeight: 600, color: t.textDim, textTransform: "uppercase", letterSpacing: 0.5,
          background: dark ? "rgba(0,0,0,0.15)" : "rgba(0,0,0,0.02)",
        }}>
          <span/><span>Host</span><span>Process</span>
          <span style={{ textAlign: "right" }}>Down</span>
          <span style={{ textAlign: "right" }}>Up</span>
          <span>Rule</span>
          <span style={{ textAlign: "right" }}>Time</span>
        </div>
        <div className={"nice-scroll" + (dark ? " dark" : "")} style={{ flex: 1, overflowY: "auto" }}>
          {visible.map((c) => (
            <div key={c.id} style={{
              display: "grid",
              gridTemplateColumns: "12px 1.6fr 1fr 90px 90px 84px 80px",
              padding: "8px 16px", gap: 12, alignItems: "center",
              borderTop: `0.5px solid ${t.lineSoft}`, fontSize: 12,
            }}>
              <ChStatusDot status={c.live ? "on" : "idle"} size={6} pulse={c.live}/>
              <span style={{ color: t.text, fontFamily: "ui-monospace, SF Mono, Menlo, monospace", fontSize: 11.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {c.host}<span style={{ color: t.textFaint }}>:{c.port}</span>
              </span>
              <span style={{ color: t.textDim }}>{c.proc}</span>
              <span style={{ color: t.text, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{fmtBytes(c.dn)}</span>
              <span style={{ color: t.text, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{fmtBytes(c.up)}</span>
              <span style={{
                color: c.action === "DIRECT" ? t.textDim : "#34c759",
                fontSize: 11, fontWeight: 600,
              }}>{c.action}</span>
              <span style={{ color: t.textFaint, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{c.dur}s</span>
            </div>
          ))}
        </div>
      </ChCard>
    </div>
  );
}

let _connId = 0;
function makeConn() {
  const host = CH_DATA.HOSTS[Math.floor(Math.random() * CH_DATA.HOSTS.length)];
  const proc = CH_DATA.PROCESSES[Math.floor(Math.random() * CH_DATA.PROCESSES.length)];
  const isDirect = host.includes("apple") || host.includes("icloud") || host.startsWith("192.");
  return {
    id: ++_connId,
    host,
    port: [443, 443, 80, 8080, 53][Math.floor(Math.random() * 5)],
    proc,
    dn: Math.floor(Math.random() * 200000),
    up: Math.floor(Math.random() * 20000),
    dur: Math.floor(Math.random() * 30),
    live: true,
    action: isDirect ? "DIRECT" : "Auto Select",
  };
}
function makeInitialConns(n) { return Array.from({ length: n }, makeConn); }

window.ChScreenConnections = ChScreenConnections;
