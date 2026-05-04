// Proxies — groups + nodes with latency tests

function pingColor(ping) {
  if (!ping || ping < 0) return "#8e8e93";
  if (ping < 80) return "#34c759";
  if (ping < 180) return "#ff9f0a";
  return "#ff453a";
}

function ChScreenProxies({ dark, groups, setGroups, currentNodeId, onSelectNode }) {
  const t = chTokens({ dark });
  const [openGroup, setOpenGroup] = React.useState("auto");
  const [testing, setTesting] = React.useState(false);
  const [hidden, setHidden] = React.useState({});

  const runTest = () => {
    setTesting(true);
    setTimeout(() => {
      setGroups(prev => prev.map(g => ({
        ...g,
        nodes: g.nodes.map(n => ({
          ...n,
          ping: Math.max(20, Math.round(n.ping * (0.7 + Math.random() * 0.6))),
        })),
      })));
      setTesting(false);
    }, 1400);
  };

  return (
    <div style={{ padding: "12px 28px 28px", display: "flex", flexDirection: "column", gap: 16 }}>
      <ChSectionHeader
        dark={dark}
        title="Proxies"
        subtitle="Pick a node, or let URL Test pick the fastest."
        right={
          <div style={{ display: "flex", gap: 8 }}>
            <ChGlass dark={dark} radius={8}>
              <button onClick={runTest} style={{
                height: 32, padding: "0 14px", border: 0, background: "transparent",
                color: t.text, fontSize: 12, fontWeight: 600, cursor: "pointer",
                display: "inline-flex", alignItems: "center", gap: 6,
              }}>
                <span style={{ animation: testing ? "ch-spin 0.9s linear infinite" : "none", display: "inline-flex" }}>
                  <Icons.refresh size={13}/>
                </span>
                {testing ? "Testing…" : "Test latency"}
              </button>
            </ChGlass>
          </div>
        }
      />

      {groups.map((g) => {
        const isOpen = openGroup === g.id;
        const sel = g.nodes.find(n => n.id === g.selected);
        return (
          <ChCard key={g.id} dark={dark} padding={0} radius={14} style={{ overflow: "hidden" }}>
            <div
              onClick={() => setOpenGroup(isOpen ? null : g.id)}
              style={{
                padding: "14px 18px", display: "flex", alignItems: "center", gap: 14,
                cursor: "pointer", userSelect: "none",
                borderBottom: isOpen ? `0.5px solid ${t.line}` : "none",
              }}>
              <div style={{
                width: 32, height: 32, borderRadius: 8,
                background: dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)",
                display: "flex", alignItems: "center", justifyContent: "center",
                color: t.textDim, transform: isOpen ? "rotate(90deg)" : "none",
                transition: "transform 180ms ease",
              }}>
                <Icons.chevR size={14}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ fontSize: 14, fontWeight: 600, color: t.text }}>{g.name}</span>
                  <ChBadge status="info" dark={dark}>{g.type}</ChBadge>
                  <span style={{ fontSize: 11, color: t.textFaint }}>{g.nodes.length} nodes</span>
                </div>
                <div style={{ fontSize: 12, color: t.textDim, marginTop: 3 }}>
                  Now using <strong style={{ color: t.text, fontWeight: 600 }}>{sel?.flag} {sel?.name}</strong> · {sel?.ping} ms
                </div>
              </div>
              <span style={{
                fontSize: 12, fontWeight: 700, color: pingColor(sel?.ping),
                fontVariantNumeric: "tabular-nums",
              }}>{sel?.ping} ms</span>
            </div>

            {isOpen && (
              <div style={{ padding: 8 }}>
                {g.nodes.map((n) => {
                  const active = n.id === g.selected;
                  return (
                    <button
                      key={n.id}
                      onClick={() => {
                        setGroups(prev => prev.map(x => x.id === g.id ? { ...x, selected: n.id } : x));
                        if (g.id === "auto") onSelectNode?.(n);
                      }}
                      style={{
                        width: "100%", display: "flex", alignItems: "center", gap: 12,
                        padding: "10px 12px", borderRadius: 9, border: 0,
                        background: active ? (dark ? "rgba(10,132,255,0.16)" : "rgba(10,132,255,0.10)") : "transparent",
                        cursor: "pointer", textAlign: "left",
                      }}
                      onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = dark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)"; }}
                      onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = "transparent"; }}
                    >
                      <span style={{
                        width: 18, height: 18, borderRadius: "50%",
                        border: `1.5px solid ${active ? "#0a84ff" : t.line}`,
                        background: active ? "#0a84ff" : "transparent",
                        display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
                      }}>
                        {active && <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#fff" }}/>}
                      </span>
                      <span style={{ fontSize: 16, width: 22 }}>{n.flag}</span>
                      <span style={{ fontSize: 13, color: t.text, fontWeight: 500, flex: 1 }}>{n.name}</span>
                      <span style={{ fontSize: 11, color: t.textFaint, fontFamily: "ui-monospace, SF Mono, Menlo, monospace" }}>{n.proto}</span>
                      <div style={{ display: "flex", alignItems: "center", gap: 6, width: 64, justifyContent: "flex-end" }}>
                        {testing ? (
                          <span style={{ display: "inline-flex", gap: 2 }}>
                            {[0,1,2].map(i => (
                              <span key={i} style={{
                                width: 3, height: 10, borderRadius: 1.5, background: t.textDim,
                                animation: `ch-blink 1s ease-in-out ${i*0.15}s infinite`,
                              }}/>
                            ))}
                          </span>
                        ) : (
                          <span style={{
                            fontSize: 12, fontWeight: 700, color: pingColor(n.ping),
                            fontVariantNumeric: "tabular-nums",
                          }}>{n.ping} ms</span>
                        )}
                      </div>
                      <div style={{ width: 50 }}>
                        <div style={{
                          width: "100%", height: 4, borderRadius: 2,
                          background: dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)",
                          overflow: "hidden",
                        }}>
                          <div style={{
                            width: `${n.load}%`, height: "100%",
                            background: n.load > 70 ? "#ff9f0a" : "#34c759",
                          }}/>
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </ChCard>
        );
      })}
    </div>
  );
}

window.ChScreenProxies = ChScreenProxies;
window.pingColor = pingColor;
