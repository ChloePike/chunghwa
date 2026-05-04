// Logs screen — terminal-style

function ChScreenLogs({ dark }) {
  const t = chTokens({ dark });
  const [logs, setLogs] = React.useState(() => seed(20));
  const [level, setLevel] = React.useState("all");
  const containerRef = React.useRef(null);

  React.useEffect(() => {
    const id = setInterval(() => {
      setLogs(prev => [...prev.slice(-200), makeLog()]);
    }, 1100);
    return () => clearInterval(id);
  }, []);

  React.useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs.length]);

  const visible = logs.filter(l => level === "all" || l.level === level);

  return (
    <div style={{ padding: "12px 28px 28px", display: "flex", flexDirection: "column", gap: 14, height: "100%" }}>
      <ChSectionHeader
        dark={dark}
        title="Logs"
        subtitle="Live tail of the core engine."
        right={
          <ChSegmented
            dark={dark}
            value={level}
            onChange={setLevel}
            options={[
              { value: "all", label: "All" },
              { value: "info", label: "Info" },
              { value: "warn", label: "Warn" },
              { value: "error", label: "Error" },
            ]}
          />
        }
      />

      <ChCard dark={dark} padding={0} radius={14} style={{ overflow: "hidden", flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
        <div
          ref={containerRef}
          className={"nice-scroll" + (dark ? " dark" : "")}
          style={{
            flex: 1, overflowY: "auto",
            padding: "12px 16px",
            fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
            fontSize: 11.5, lineHeight: 1.7,
            background: dark ? "rgba(0,0,0,0.25)" : "rgba(0,0,0,0.02)",
        }}>
          {visible.map((l, i) => (
            <div key={i} style={{ display: "flex", gap: 10 }}>
              <span style={{ color: t.textFaint, flexShrink: 0 }}>{l.t}</span>
              <span style={{
                color: l.level === "error" ? "#ff453a" : l.level === "warn" ? "#ff9f0a" : "#0a84ff",
                fontWeight: 700, flexShrink: 0, width: 44, textTransform: "uppercase",
              }}>{l.level}</span>
              <span style={{ color: t.text }}>{l.msg}</span>
            </div>
          ))}
        </div>
      </ChCard>
    </div>
  );
}

const LOG_TEMPLATES = [
  { level: "info",  msg: "[TCP] github.com:443 matched DOMAIN-SUFFIX → DIRECT" },
  { level: "info",  msg: "[TCP] api.openai.com:443 matched DOMAIN-SUFFIX → Auto Select (Tokyo 02)" },
  { level: "info",  msg: "[DNS] resolved fonts.gstatic.com → 142.250.71.227" },
  { level: "info",  msg: "[URLTest] Taipei 01: 38ms · Tokyo 02: 62ms · best=Taipei 01" },
  { level: "warn",  msg: "[Proxy] Frankfurt timeout, retrying with fallback" },
  { level: "info",  msg: "[Cfg] subscription 'main' refreshed, 24 nodes" },
  { level: "error", msg: "[Conn] handshake failed: tls: certificate expired" },
  { level: "info",  msg: "[TCP] claude.ai:443 → Auto Select (Tokyo 02)" },
  { level: "warn",  msg: "[GeoIP] mmdb older than 30 days, consider updating" },
  { level: "info",  msg: "[Match] rule no.5 hit: GEOIP CN → DIRECT" },
];
let _logId = 0;
function makeLog() {
  const tpl = LOG_TEMPLATES[Math.floor(Math.random() * LOG_TEMPLATES.length)];
  const d = new Date();
  const t = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}:${String(d.getSeconds()).padStart(2, "0")}.${String(d.getMilliseconds()).padStart(3, "0")}`;
  return { ...tpl, t, id: ++_logId };
}
function seed(n) { return Array.from({ length: n }, makeLog); }

window.ChScreenLogs = ChScreenLogs;
