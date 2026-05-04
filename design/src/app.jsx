// ChungHwa main app — wires together window chrome, screens, traffic sim, and Tweaks panel.

const { useState, useEffect, useMemo, useRef } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "appearance": "dark",
  "wallpaper": "aurora-dark",
  "glass": "medium",
  "density": "comfortable",
  "showGraph": true,
  "accent": "blue"
}/*EDITMODE-END*/;

const SCREENS = {
  overview: { title: "Overview" },
  proxies: { title: "Proxies" },
  rules: { title: "Rules" },
  connections: { title: "Connections" },
  logs: { title: "Logs" },
  settings: { title: "Settings" },
};

function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const dark = tweaks.appearance === "dark";

  // Auto-pair wallpaper to appearance unless user picked one
  useEffect(() => {
    if (dark && tweaks.wallpaper === "aurora-light") setTweak("wallpaper", "aurora-dark");
    if (!dark && tweaks.wallpaper === "aurora-dark") setTweak("wallpaper", "aurora-light");
    if (!dark && tweaks.wallpaper === "midnight") setTweak("wallpaper", "linen");
    if (dark && tweaks.wallpaper === "linen") setTweak("wallpaper", "midnight");
  }, [dark]);

  const [screen, setScreen] = useState("overview");
  const [mode, setMode] = useState("rule");
  const [systemProxy, setSystemProxy] = useState(true);
  const [tunMode, setTunMode] = useState(false);
  const [groups, setGroups] = useState(CH_DATA.PROXY_GROUPS);

  const currentNode = useMemo(() => {
    const main = groups[0];
    return main.nodes.find(n => n.id === main.selected) || main.nodes[0];
  }, [groups]);

  // Traffic sim
  const [traffic, setTraffic] = useState({
    up: Array(60).fill(0).map(() => 30000 + Math.random() * 80000),
    down: Array(60).fill(0).map(() => 200000 + Math.random() * 1500000),
  });
  useEffect(() => {
    const id = setInterval(() => {
      setTraffic(prev => {
        const nextDn = systemProxy ? Math.max(50000, (prev.down[prev.down.length-1] || 500000) + (Math.random() - 0.45) * 700000) : 0;
        const nextUp = systemProxy ? Math.max(5000, (prev.up[prev.up.length-1] || 50000) + (Math.random() - 0.45) * 60000) : 0;
        return {
          up: [...prev.up.slice(1), nextUp],
          down: [...prev.down.slice(1), nextDn],
        };
      });
    }, 600);
    return () => clearInterval(id);
  }, [systemProxy]);

  const screenEl = (() => {
    switch (screen) {
      case "overview": return <ChScreenOverview {...{ dark, mode, setMode, systemProxy, setSystemProxy, tunMode, setTunMode, traffic, currentNode }}/>;
      case "proxies":  return <ChScreenProxies dark={dark} groups={groups} setGroups={setGroups} currentNodeId={currentNode.id} onSelectNode={()=>{}}/>;
      case "rules":    return <ChScreenRules dark={dark}/>;
      case "connections": return <ChScreenConnections dark={dark}/>;
      case "logs":     return <ChScreenLogs dark={dark}/>;
      case "settings": return <ChScreenSettings dark={dark}/>;
    }
  })();

  const t = chTokens({ dark });

  return (
    <div style={{ position: "fixed", inset: 0, overflow: "hidden" }}>
      <ChWallpaper variant={tweaks.wallpaper}/>

      {/* Floating macOS menu bar (decorative) */}
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 24,
        background: dark ? "rgba(0,0,0,0.30)" : "rgba(255,255,255,0.30)",
        backdropFilter: "blur(30px) saturate(180%)",
        WebkitBackdropFilter: "blur(30px) saturate(180%)",
        borderBottom: dark ? "0.5px solid rgba(255,255,255,0.10)" : "0.5px solid rgba(0,0,0,0.10)",
        display: "flex", alignItems: "center", padding: "0 12px", gap: 14,
        fontSize: 12, color: dark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.85)",
        zIndex: 10,
      }}>
        <span style={{ fontSize: 13 }}></span>
        <span style={{ fontWeight: 700 }}>ChungHwa</span>
        <span>File</span><span>Edit</span><span>View</span><span>Profile</span><span>Help</span>
        <div style={{ flex: 1 }}/>
        {/* Menu bar status icon */}
        <div style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
          <ChStatusDot status={systemProxy ? "on" : "idle"} size={7} pulse={systemProxy}/>
          <span style={{ fontVariantNumeric: "tabular-nums", fontSize: 11 }}>
            ↓{fmtSpeed(traffic.down[traffic.down.length-1] || 0).replace("/s", "")}
          </span>
        </div>
        <span style={{ fontSize: 11, opacity: 0.7 }}>Mon May 4</span>
        <span style={{ fontSize: 11, opacity: 0.7 }}>10:42 AM</span>
      </div>

      {/* The window */}
      <div style={{
        position: "absolute", top: 56, left: "50%", transform: "translateX(-50%)",
        width: "min(1180px, calc(100vw - 80px))",
        height: "calc(100vh - 96px)",
        maxHeight: 820,
        borderRadius: 14,
        overflow: "hidden",
        background: dark ? "rgba(28,28,32,0.65)" : "rgba(252,252,254,0.75)",
        boxShadow: dark
          ? "0 0 0 0.5px rgba(255,255,255,0.10), 0 30px 80px rgba(0,0,0,0.55), 0 8px 24px rgba(0,0,0,0.35)"
          : "0 0 0 0.5px rgba(0,0,0,0.12), 0 30px 80px rgba(0,0,0,0.30), 0 8px 24px rgba(0,0,0,0.15)",
        display: "flex",
        backdropFilter: "blur(60px) saturate(200%)",
        WebkitBackdropFilter: "blur(60px) saturate(200%)",
      }}>
        <ChSidebar dark={dark} screen={screen} setScreen={setScreen} systemProxy={systemProxy} currentNode={currentNode}/>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
          <ChToolbar dark={dark} title={SCREENS[screen].title} traffic={traffic}/>
          <div className={"nice-scroll" + (dark ? " dark" : "")} style={{ flex: 1, overflowY: "auto", color: t.text }}>
            {screenEl}
          </div>
        </div>
      </div>

      {/* Tweaks panel */}
      <TweaksPanel title="Tweaks" dark={dark}>
        <TweakSection title="Appearance">
          <TweakRadio label="Mode" value={tweaks.appearance} onChange={(v) => setTweak("appearance", v)}
            options={[{ value: "light", label: "Light" }, { value: "dark", label: "Dark" }]}/>
          <TweakSelect label="Wallpaper" value={tweaks.wallpaper} onChange={(v) => setTweak("wallpaper", v)}
            options={[
              { value: "aurora-dark", label: "Aurora · Dark" },
              { value: "aurora-light", label: "Aurora · Light" },
              { value: "midnight", label: "Midnight" },
              { value: "linen", label: "Linen" },
            ]}/>
          <TweakRadio label="Glass" value={tweaks.glass} onChange={(v) => setTweak("glass", v)}
            options={[
              { value: "subtle", label: "Subtle" },
              { value: "medium", label: "Medium" },
              { value: "heavy", label: "Heavy" },
            ]}/>
        </TweakSection>
        <TweakSection title="Layout">
          <TweakRadio label="Density" value={tweaks.density} onChange={(v) => setTweak("density", v)}
            options={[
              { value: "compact", label: "Compact" },
              { value: "comfortable", label: "Comfort" },
            ]}/>
          <TweakToggle label="Show traffic graph" value={tweaks.showGraph} onChange={(v) => setTweak("showGraph", v)}/>
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App/>);
