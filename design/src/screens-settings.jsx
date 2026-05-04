// Settings — power-user surface

function ChScreenSettings({ dark }) {
  const t = chTokens({ dark });

  const Row = ({ label, sub, children, last }) => (
    <div style={{
      display: "flex", alignItems: "center", gap: 16,
      padding: "12px 18px",
      borderTop: `0.5px solid ${t.lineSoft}`,
    }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 13, fontWeight: 500, color: t.text }}>{label}</div>
        {sub && <div style={{ fontSize: 11, color: t.textFaint, marginTop: 2 }}>{sub}</div>}
      </div>
      {children}
    </div>
  );

  const Section = ({ title, children }) => (
    <ChCard dark={dark} padding={0} radius={14} style={{ overflow: "hidden", marginBottom: 14 }}>
      <div style={{
        padding: "12px 18px", fontSize: 13, fontWeight: 700, color: t.text,
        background: dark ? "rgba(0,0,0,0.15)" : "rgba(0,0,0,0.02)",
        borderBottom: `0.5px solid ${t.line}`,
      }}>{title}</div>
      {children}
    </ChCard>
  );

  const Field = ({ value, w = 220, mono }) => (
    <div style={{
      height: 26, padding: "0 10px", borderRadius: 7,
      background: dark ? "rgba(0,0,0,0.30)" : "rgba(0,0,0,0.04)",
      border: `0.5px solid ${t.line}`,
      display: "inline-flex", alignItems: "center",
      fontSize: 12, color: t.text, width: w,
      fontFamily: mono ? "ui-monospace, SF Mono, Menlo, monospace" : "inherit",
    }}>{value}</div>
  );

  const Select = ({ value }) => (
    <div style={{
      height: 26, padding: "0 8px 0 10px", borderRadius: 7,
      background: dark ? "rgba(255,255,255,0.10)" : "#fff",
      border: `0.5px solid ${t.line}`,
      boxShadow: "0 1px 2px rgba(0,0,0,0.04)",
      display: "inline-flex", alignItems: "center", gap: 6,
      fontSize: 12, color: t.text, fontWeight: 500,
    }}>
      {value} <Icons.chevD size={11} style={{ color: t.textDim }}/>
    </div>
  );

  return (
    <div style={{ padding: "12px 28px 28px" }}>
      <ChSectionHeader dark={dark} title="Settings" subtitle="Network, DNS, profiles, and advanced controls." />

      <Section title="Inbound">
        <Row label="Mixed Port" sub="HTTP and SOCKS5 share this port"><Field value="7890" w={100} mono/></Row>
        <Row label="SOCKS5 Port"><Field value="7891" w={100} mono/></Row>
        <Row label="Allow LAN" sub="Accept connections from devices on the local network">
          <ChToggle checked={true} onChange={()=>{}} dark={dark} accent="#0a84ff"/>
        </Row>
        <Row label="Bind Address"><Field value="*" w={100} mono/></Row>
      </Section>

      <Section title="DNS">
        <Row label="DNS Mode"><Select value="Fake-IP"/></Row>
        <Row label="Default Resolver" sub="Used for local lookups">
          <Field value="https://1.1.1.1/dns-query" w={260} mono/>
        </Row>
        <Row label="Nameserver Policy" sub="Per-domain overrides">
          <span style={{ fontSize: 12, color: t.textDim }}>3 entries</span>
          <Icons.chevR size={12} style={{ color: t.textFaint, marginLeft: 8 }}/>
        </Row>
        <Row label="Enable EDNS Client Subnet">
          <ChToggle checked={false} onChange={()=>{}} dark={dark} accent="#0a84ff"/>
        </Row>
      </Section>

      <Section title="Profiles & Subscriptions">
        <div style={{ padding: "8px 12px" }}>
          {[
            { name: "main.yaml", url: "subscribe.example.net/main", updated: "2 hours ago", active: true },
            { name: "backup.yaml", url: "subscribe.example.net/backup", updated: "3 days ago", active: false },
          ].map((p, i) => (
            <div key={p.name} style={{
              display: "flex", alignItems: "center", gap: 12,
              padding: "10px 8px", borderRadius: 8,
              background: p.active ? (dark ? "rgba(52,199,89,0.10)" : "rgba(52,199,89,0.06)") : "transparent",
            }}>
              <div style={{
                width: 28, height: 28, borderRadius: 7,
                background: dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)",
                display: "flex", alignItems: "center", justifyContent: "center",
                color: p.active ? "#34c759" : t.textDim,
              }}><Icons.shield size={14}/></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600, color: t.text, display: "flex", alignItems: "center", gap: 8 }}>
                  {p.name} {p.active && <ChBadge status="on" dark={dark}>Active</ChBadge>}
                </div>
                <div style={{ fontSize: 11, color: t.textFaint, fontFamily: "ui-monospace, SF Mono, Menlo, monospace", marginTop: 2 }}>
                  {p.url} · updated {p.updated}
                </div>
              </div>
              <button style={{
                border: 0, background: "transparent", color: t.textDim, cursor: "pointer",
                padding: 6, borderRadius: 6,
              }}><Icons.refresh size={13}/></button>
              <button style={{
                border: 0, background: "transparent", color: t.textDim, cursor: "pointer",
                padding: 6, borderRadius: 6,
              }}><Icons.ellipsis size={14}/></button>
            </div>
          ))}
          <button style={{
            width: "100%", marginTop: 4,
            padding: "10px", border: `1px dashed ${t.line}`, borderRadius: 8,
            background: "transparent", color: t.textDim, fontSize: 12, fontWeight: 500,
            cursor: "pointer", display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 6,
          }}>
            <Icons.plus size={12}/> Add subscription URL
          </button>
        </div>
      </Section>

      <Section title="Advanced">
        <Row label="External Controller" sub="REST API for third-party clients">
          <Field value="127.0.0.1:9090" w={180} mono/>
        </Row>
        <Row label="Log Level"><Select value="info"/></Row>
        <Row label="Strict Route" sub="Reject traffic that doesn't match any rule">
          <ChToggle checked={false} onChange={()=>{}} dark={dark} accent="#ff453a"/>
        </Row>
        <Row label="IPv6"><ChToggle checked={true} onChange={()=>{}} dark={dark} accent="#0a84ff"/></Row>
        <Row label={CH_DATA.APP_VERSION} sub="Up to date">
          <ChGlass dark={dark} radius={7}>
            <button style={{
              height: 26, padding: "0 12px", border: 0, background: "transparent",
              color: t.text, fontSize: 12, fontWeight: 600, cursor: "pointer",
            }}>Check for updates</button>
          </ChGlass>
        </Row>
      </Section>
    </div>
  );
}

window.ChScreenSettings = ChScreenSettings;
