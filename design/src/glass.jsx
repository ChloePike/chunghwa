// Liquid Glass primitives + theme tokens for ChungHwa
// Theme values come from `theme` arg: { dark, accent, glass } where glass is 'subtle'|'medium'|'heavy'

function chTokens({ dark, glass = "medium" }) {
  const blurMap = { subtle: 24, medium: 40, heavy: 64 };
  const tintMap = dark
    ? { subtle: 0.28, medium: 0.40, heavy: 0.55 }
    : { subtle: 0.42, medium: 0.55, heavy: 0.70 };
  return {
    text: dark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.86)",
    textDim: dark ? "rgba(255,255,255,0.62)" : "rgba(0,0,0,0.54)",
    textFaint: dark ? "rgba(255,255,255,0.38)" : "rgba(0,0,0,0.34)",
    line: dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.08)",
    lineSoft: dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.05)",
    fill: dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)",
    fillStrong: dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.06)",
    glassBlur: `blur(${blurMap[glass]}px) saturate(180%)`,
    glassTint: dark
      ? `rgba(28, 28, 32, ${tintMap[glass]})`
      : `rgba(255,255,255, ${tintMap[glass]})`,
    glassBorder: dark
      ? "0.5px solid rgba(255,255,255,0.12)"
      : "0.5px solid rgba(255,255,255,0.6)",
    glassHighlight: dark
      ? "inset 0 0.5px 0 rgba(255,255,255,0.10)"
      : "inset 0 0.5px 0 rgba(255,255,255,0.6)",
    panel: dark ? "rgba(40,40,46,0.72)" : "rgba(255,255,255,0.78)",
    panelInset: dark ? "rgba(0,0,0,0.18)" : "rgba(0,0,0,0.025)",
  };
}

const STATUS = {
  on:      { fg: "#34c759", bg: "rgba(52,199,89,0.18)", ring: "rgba(52,199,89,0.45)" },
  testing: { fg: "#ff9f0a", bg: "rgba(255,159,10,0.18)", ring: "rgba(255,159,10,0.45)" },
  off:     { fg: "#ff453a", bg: "rgba(255,69,58,0.18)", ring: "rgba(255,69,58,0.45)" },
  idle:    { fg: "#8e8e93", bg: "rgba(142,142,147,0.18)", ring: "rgba(142,142,147,0.40)" },
  info:    { fg: "#0a84ff", bg: "rgba(10,132,255,0.18)", ring: "rgba(10,132,255,0.45)" },
  purple:  { fg: "#bf5af2", bg: "rgba(191,90,242,0.18)", ring: "rgba(191,90,242,0.45)" },
};

function ChGlass({ children, radius = 14, dark, glass = "medium", style = {}, className = "" }) {
  const t = chTokens({ dark, glass });
  return (
    <div className={className} style={{ position: "relative", borderRadius: radius, ...style }}>
      <div style={{
        position: "absolute", inset: 0, borderRadius: radius,
        background: t.glassTint,
        backdropFilter: t.glassBlur,
        WebkitBackdropFilter: t.glassBlur,
        border: t.glassBorder,
        boxShadow: t.glassHighlight,
        pointerEvents: "none",
      }} />
      <div style={{ position: "relative", zIndex: 1 }}>{children}</div>
    </div>
  );
}

function ChStatusDot({ status = "on", size = 8, pulse = false }) {
  const s = STATUS[status];
  return (
    <span style={{
      display: "inline-block", width: size, height: size, borderRadius: "50%",
      background: s.fg,
      boxShadow: `0 0 0 ${Math.max(2, size/2)}px ${s.bg}`,
      animation: pulse ? "ch-pulse 1.6s ease-in-out infinite" : "none",
      flexShrink: 0,
    }} />
  );
}

function ChBadge({ children, status = "info", dark }) {
  const s = STATUS[status];
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 5,
      height: 20, padding: "0 8px", borderRadius: 6,
      background: s.bg, color: s.fg,
      fontSize: 11, fontWeight: 600, letterSpacing: 0.1,
      border: `0.5px solid ${s.ring}`,
    }}>{children}</span>
  );
}

function ChPill({ children, active, dark, onClick, style = {} }) {
  const t = chTokens({ dark });
  return (
    <button onClick={onClick} style={{
      height: 26, padding: "0 12px", borderRadius: 7, border: 0,
      background: active ? (dark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.08)") : "transparent",
      color: t.text, fontSize: 12, fontWeight: 500,
      cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 6,
      ...style,
    }}>{children}</button>
  );
}

function ChCard({ children, dark, glass = "subtle", padding = 16, style = {}, radius = 14 }) {
  const t = chTokens({ dark, glass });
  return (
    <div style={{
      background: t.panel,
      backdropFilter: t.glassBlur,
      WebkitBackdropFilter: t.glassBlur,
      border: t.glassBorder,
      boxShadow: t.glassHighlight,
      borderRadius: radius,
      padding,
      ...style,
    }}>{children}</div>
  );
}

function ChToggle({ checked, onChange, dark, accent = "#34c759" }) {
  return (
    <button onClick={() => onChange?.(!checked)} style={{
      width: 38, height: 22, borderRadius: 11, border: 0, padding: 0,
      background: checked ? accent : (dark ? "rgba(255,255,255,0.18)" : "rgba(120,120,128,0.32)"),
      position: "relative", cursor: "pointer", transition: "background 180ms ease",
      flexShrink: 0,
    }}>
      <span style={{
        position: "absolute", top: 2, left: checked ? 18 : 2,
        width: 18, height: 18, borderRadius: "50%",
        background: "#fff",
        boxShadow: "0 1px 2px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.06)",
        transition: "left 200ms cubic-bezier(0.32,0.72,0,1)",
      }} />
    </button>
  );
}

function ChSegmented({ value, options, onChange, dark, accent }) {
  const t = chTokens({ dark });
  return (
    <div style={{
      display: "inline-flex", padding: 2, borderRadius: 9,
      background: dark ? "rgba(0,0,0,0.30)" : "rgba(0,0,0,0.05)",
      border: `0.5px solid ${t.line}`,
    }}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button key={o.value} onClick={() => onChange(o.value)} style={{
            height: 26, padding: "0 14px", borderRadius: 7, border: 0,
            background: active
              ? (dark ? "rgba(255,255,255,0.14)" : "#fff")
              : "transparent",
            color: active ? t.text : t.textDim,
            fontSize: 12, fontWeight: 600, cursor: "pointer",
            boxShadow: active ? "0 1px 2px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.05)" : "none",
            transition: "background 140ms ease",
            display: "inline-flex", alignItems: "center", gap: 6,
          }}>{o.label}</button>
        );
      })}
    </div>
  );
}

function ChSectionHeader({ title, subtitle, right, dark }) {
  const t = chTokens({ dark });
  return (
    <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", marginBottom: 14 }}>
      <div>
        <div style={{ fontSize: 22, fontWeight: 700, color: t.text, letterSpacing: -0.3 }}>{title}</div>
        {subtitle && <div style={{ fontSize: 13, color: t.textDim, marginTop: 3 }}>{subtitle}</div>}
      </div>
      {right}
    </div>
  );
}

Object.assign(window, {
  chTokens, ChGlass, ChStatusDot, ChBadge, ChPill, ChCard, ChToggle, ChSegmented, ChSectionHeader, STATUS,
});
