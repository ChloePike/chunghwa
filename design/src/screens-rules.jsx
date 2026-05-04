// Rules editor

function ChScreenRules({ dark }) {
  const t = chTokens({ dark });
  const [filter, setFilter] = React.useState("");
  const rules = CH_DATA.RULES.filter(r =>
    !filter || r.match.toLowerCase().includes(filter.toLowerCase()) ||
    r.action.toLowerCase().includes(filter.toLowerCase()) ||
    r.type.toLowerCase().includes(filter.toLowerCase())
  );

  const typeColor = (type) => ({
    "DOMAIN-SUFFIX": "#0a84ff",
    "DOMAIN-KEYWORD": "#5e5ce6",
    "GEOIP": "#bf5af2",
    "IP-CIDR": "#ff9f0a",
    "PROCESS-NAME": "#ff375f",
    "MATCH": "#8e8e93",
  })[type] || "#8e8e93";

  const actionColor = (a) => a === "DIRECT" ? "#8e8e93" : a === "REJECT" ? "#ff453a" : "#34c759";

  return (
    <div style={{ padding: "12px 28px 28px", display: "flex", flexDirection: "column", gap: 14 }}>
      <ChSectionHeader
        dark={dark}
        title="Rules"
        subtitle={`${CH_DATA.RULES.length} rules · evaluated top to bottom`}
        right={
          <div style={{ display: "flex", gap: 8 }}>
            <ChGlass dark={dark} radius={8}>
              <div style={{
                height: 32, padding: "0 12px", display: "flex", alignItems: "center", gap: 8,
                color: t.textDim, fontSize: 12,
              }}>
                <Icons.search size={13}/>
                <input
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="Filter rules…"
                  style={{
                    border: 0, background: "transparent", outline: "none",
                    color: t.text, fontSize: 12, width: 160, fontFamily: "inherit",
                  }}
                />
              </div>
            </ChGlass>
            <ChGlass dark={dark} radius={8}>
              <button style={{
                height: 32, padding: "0 12px", border: 0, background: "transparent",
                color: t.text, fontSize: 12, fontWeight: 600, cursor: "pointer",
                display: "inline-flex", alignItems: "center", gap: 6,
              }}>
                <Icons.plus size={13}/> New rule
              </button>
            </ChGlass>
          </div>
        }
      />

      <ChCard dark={dark} padding={0} radius={14} style={{ overflow: "hidden" }}>
        {/* header */}
        <div style={{
          display: "grid", gridTemplateColumns: "32px 130px 1fr 160px 80px 32px",
          padding: "10px 16px", gap: 12,
          borderBottom: `0.5px solid ${t.line}`,
          fontSize: 11, fontWeight: 600, color: t.textDim, textTransform: "uppercase", letterSpacing: 0.5,
          background: dark ? "rgba(0,0,0,0.15)" : "rgba(0,0,0,0.02)",
        }}>
          <span>#</span><span>Type</span><span>Match</span><span>Action</span><span style={{ textAlign: "right" }}>Hits</span><span/>
        </div>
        {rules.map((r, i) => (
          <div key={i} style={{
            display: "grid", gridTemplateColumns: "32px 130px 1fr 160px 80px 32px",
            padding: "10px 16px", gap: 12, alignItems: "center",
            borderTop: i ? `0.5px solid ${t.lineSoft}` : "none",
            fontSize: 13,
          }}>
            <span style={{ color: t.textFaint, fontVariantNumeric: "tabular-nums" }}>{i+1}</span>
            <span style={{
              fontSize: 11, fontWeight: 700, color: typeColor(r.type),
              fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
            }}>{r.type}</span>
            <span style={{
              color: t.text, fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
              fontSize: 12,
            }}>{r.match}</span>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: "50%", background: actionColor(r.action) }}/>
              <span style={{ color: t.text, fontWeight: 500 }}>{r.action}</span>
            </span>
            <span style={{
              color: t.textDim, fontVariantNumeric: "tabular-nums",
              textAlign: "right", fontSize: 12,
            }}>{r.hits.toLocaleString()}</span>
            <button style={{
              border: 0, background: "transparent", color: t.textFaint, cursor: "pointer",
              padding: 4, borderRadius: 4,
            }}><Icons.ellipsis size={14}/></button>
          </div>
        ))}
      </ChCard>
    </div>
  );
}

window.ChScreenRules = ChScreenRules;
