// Window chrome — sidebar nav + traffic-light buttons + toolbar.
// Custom-built to match ChungHwa's visual language; loosely inspired by macOS Tahoe.

function ChTrafficLights({ dark }) {
  const dot = (bg) => (
    <span style={{
      width: 12, height: 12, borderRadius: "50%", background: bg,
      border: dark ? "0.5px solid rgba(0,0,0,0.30)" : "0.5px solid rgba(0,0,0,0.10)",
      display: "inline-block",
    }}/>
  );
  return (
    <div style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
      {dot("#ff5f57")}{dot("#febc2e")}{dot("#28c840")}
    </div>
  );
}

function ChSidebarItem({ icon: Icon, label, badge, count, active, onClick, dark, accent = "#0a84ff" }) {
  const t = chTokens({ dark });
  const [hover, setHover] = React.useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        width: "calc(100% - 12px)", margin: "1px 6px",
        display: "flex", alignItems: "center", gap: 9,
        height: 28, padding: "0 9px", borderRadius: 7, border: 0,
        background: active
          ? (dark ? "rgba(255,255,255,0.13)" : "rgba(255,255,255,0.55)")
          : hover
            ? (dark ? "rgba(255,255,255,0.05)" : "rgba(255,255,255,0.28)")
            : "transparent",
        backdropFilter: active ? "blur(20px) saturate(180%)" : "none",
        WebkitBackdropFilter: active ? "blur(20px) saturate(180%)" : "none",
        boxShadow: active ? "inset 0 0.5px 0 rgba(255,255,255,0.4), 0 1px 2px rgba(0,0,0,0.06)" : "none",
        color: active ? t.text : t.textDim,
        fontSize: 13, fontWeight: active ? 600 : 500,
        cursor: "pointer", textAlign: "left",
        transition: "background 120ms ease",
      }}
    >
      <span style={{ display: "inline-flex", color: active ? accent : t.textDim, width: 16 }}><Icon size={15}/></span>
      <span style={{ flex: 1 }}>{label}</span>
      {badge && <ChStatusDot status={badge} size={6} pulse={badge === "on"} />}
      {count != null && (
        <span style={{
          fontSize: 10, fontWeight: 600,
          color: t.textFaint, fontVariantNumeric: "tabular-nums",
        }}>{count}</span>
      )}
    </button>
  );
}

function ChSidebar({ dark, screen, setScreen, systemProxy, currentNode }) {
  const t = chTokens({ dark });

  const items = [
    { id: "overview",    icon: Icons.dashboard, label: "Overview" },
    { id: "proxies",     icon: Icons.globe,     label: "Proxies", count: 13 },
    { id: "rules",       icon: Icons.rules,     label: "Rules", count: CH_DATA.RULES.length },
    { id: "connections", icon: Icons.link,      label: "Connections", badge: systemProxy ? "on" : "idle" },
    { id: "logs",        icon: Icons.log,       label: "Logs" },
  ];
  const settings = [
    { id: "settings",    icon: Icons.gear,      label: "Settings" },
  ];

  const SectionHead = ({ children }) => (
    <div style={{
      padding: "12px 16px 4px", fontSize: 11, fontWeight: 700,
      color: t.textFaint, letterSpacing: 0.4, textTransform: "uppercase",
    }}>{children}</div>
  );

  return (
    <div style={{
      width: 218, height: "100%", flexShrink: 0,
      display: "flex", flexDirection: "column",
      position: "relative",
      background: dark ? "rgba(28,28,32,0.55)" : "rgba(245,247,252,0.55)",
      backdropFilter: "blur(50px) saturate(200%)",
      WebkitBackdropFilter: "blur(50px) saturate(200%)",
      borderRight: `0.5px solid ${t.line}`,
    }}>
      {/* Title bar */}
      <div style={{
        height: 38, padding: "0 14px", display: "flex", alignItems: "center", gap: 10,
        WebkitAppRegion: "drag",
      }}>
        <ChTrafficLights dark={dark}/>
      </div>

      {/* Brand */}
      <div style={{ padding: "6px 16px 12px", display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{
          width: 26, height: 26, borderRadius: 7,
          background: "linear-gradient(135deg, #34c759, #0a84ff)",
          display: "flex", alignItems: "center", justifyContent: "center",
          boxShadow: "0 2px 6px rgba(10,132,255,0.35), inset 0 0.5px 0 rgba(255,255,255,0.4)",
          color: "#fff",
        }}>
          <Icons.shield size={14} stroke={2}/>
        </div>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: t.text, letterSpacing: -0.1 }}>ChungHwa</div>
          <div style={{ fontSize: 10, color: t.textFaint, marginTop: 1 }}>v1.4.0</div>
        </div>
      </div>

      {/* Nav */}
      <div style={{ flex: 1, overflowY: "auto" }} className={"nice-scroll" + (dark ? " dark" : "")}>
        {items.map(it => (
          <ChSidebarItem key={it.id} dark={dark}
            icon={it.icon} label={it.label}
            badge={it.badge} count={it.count}
            active={screen === it.id}
            onClick={() => setScreen(it.id)}
          />
        ))}

        <SectionHead>Configuration</SectionHead>
        {settings.map(it => (
          <ChSidebarItem key={it.id} dark={dark}
            icon={it.icon} label={it.label}
            active={screen === it.id}
            onClick={() => setScreen(it.id)}
          />
        ))}

        <SectionHead>Profiles</SectionHead>
        {[
          { id: "main", label: "main.yaml", active: true },
          { id: "backup", label: "backup.yaml", active: false },
        ].map(p => (
          <button key={p.id} style={{
            width: "calc(100% - 12px)", margin: "1px 6px",
            display: "flex", alignItems: "center", gap: 9,
            height: 26, padding: "0 9px", borderRadius: 7, border: 0,
            background: "transparent",
            color: t.textDim, fontSize: 12, fontWeight: 500,
            cursor: "pointer", textAlign: "left",
          }}>
            <ChStatusDot status={p.active ? "on" : "idle"} size={6}/>
            <span style={{ flex: 1, fontFamily: "ui-monospace, SF Mono, Menlo, monospace", fontSize: 11 }}>{p.label}</span>
          </button>
        ))}
      </div>

      {/* Footer status pill */}
      <div style={{ padding: 8 }}>
        <ChGlass dark={dark} radius={10}>
          <div style={{ padding: "8px 10px", display: "flex", alignItems: "center", gap: 9 }}>
            <ChStatusDot status={systemProxy ? "on" : "idle"} size={8} pulse={systemProxy}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: t.text, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {systemProxy ? `${currentNode.flag} ${currentNode.name}` : "Disconnected"}
              </div>
              <div style={{ fontSize: 10, color: t.textFaint, fontVariantNumeric: "tabular-nums" }}>
                {systemProxy ? `${currentNode.ping} ms · ${currentNode.proto}` : "tap to connect"}
              </div>
            </div>
          </div>
        </ChGlass>
      </div>
    </div>
  );
}

function ChToolbar({ dark, title, traffic }) {
  const t = chTokens({ dark });
  const dn = traffic.down[traffic.down.length - 1] || 0;
  const up = traffic.up[traffic.up.length - 1] || 0;
  return (
    <div style={{
      height: 38, flexShrink: 0,
      display: "flex", alignItems: "center", padding: "0 16px",
      borderBottom: `0.5px solid ${t.line}`,
      background: dark ? "rgba(28,28,32,0.40)" : "rgba(255,255,255,0.40)",
      backdropFilter: "blur(40px) saturate(180%)",
      WebkitBackdropFilter: "blur(40px) saturate(180%)",
      gap: 12,
    }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: t.text }}>{title}</div>
      <div style={{ flex: 1 }}/>
      {/* Live mini-speed indicator */}
      <div style={{ display: "inline-flex", alignItems: "center", gap: 12, fontSize: 11, color: t.textDim, fontVariantNumeric: "tabular-nums" }}>
        <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
          <Icons.download size={11} style={{ color: "#0a84ff" }}/>
          <span style={{ fontWeight: 600, color: t.text }}>{fmtSpeed(dn)}</span>
        </span>
        <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
          <Icons.upload size={11} style={{ color: "#34c759" }}/>
          <span style={{ fontWeight: 600, color: t.text }}>{fmtSpeed(up)}</span>
        </span>
      </div>
    </div>
  );
}

window.ChSidebar = ChSidebar;
window.ChToolbar = ChToolbar;
window.ChTrafficLights = ChTrafficLights;
