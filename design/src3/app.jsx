// ChungHwa v2 — restrained, ClashMac-inspired warm light aesthetic.
// One file, no fanfare. Hand-drawn cat mark, real density, soft accents.

const { useState, useEffect, useMemo, useRef, useCallback } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "dark": false,
  "outboundMode": "Rule",
  "profile": "Backup",
  "sysProxy": true,
  "tunMode": false,
  "anon": false
}/*EDITMODE-END*/;

// ── Theme ────────────────────────────────────────────────────────────
const T = (dark) => dark ? {
  bg: "#0E2A2A", desk: "#06181a",
  card: "#13383a", cardSoft: "#0f3032",
  line: "rgba(245,241,232,0.10)", lineSoft: "rgba(245,241,232,0.05)",
  text: "#F5F1E8", dim: "rgba(245,241,232,0.65)", faint: "rgba(245,241,232,0.40)",
  side: "rgba(11,34,34,0.92)", sideHover: "rgba(245,241,232,0.05)", sideActive: "rgba(200,169,110,0.14)",
  fill: "rgba(245,241,232,0.06)", fillStrong: "rgba(245,241,232,0.10)",
  pillBg: "rgba(245,241,232,0.10)",
} : {
  bg: "#FBFAF7", desk: "#b9bcb3",
  card: "#FFFFFF", cardSoft: "#F5F1E8",
  line: "rgba(14,42,42,0.12)", lineSoft: "rgba(14,42,42,0.06)",
  text: "#0E2A2A", dim: "#3F6B66", faint: "rgba(63,107,102,0.55)",
  side: "rgba(245,241,232,0.92)", sideHover: "rgba(14,42,42,0.04)", sideActive: "rgba(200,169,110,0.18)",
  fill: "rgba(14,42,42,0.045)", fillStrong: "rgba(14,42,42,0.08)",
  pillBg: "#FFFFFF",
};

// Palette — Bone & Brass on Patina
const C = {
  ink:    "#0E2A2A",  // deep teal text/ink
  patina: "#3F6B66",  // muted teal
  bone:   "#F5F1E8",  // paper
  paper:  "#FBFAF7",  // bright paper
  brass:  "#C8A96E",  // brass accent
  brassDk:"#a88c54",
  // semantic — derived from palette + restrained system colors
  green: "#3F6B66",   // patina = "good"
  amber: "#C8A96E",   // brass = "attention"
  red:   "#9c4a3b",   // earthy red
  warm:  "#C8A96E",   // back-compat: anything labelled "warm" maps to brass
  blue:  "#3F6B66",   // back-compat
  purple:"#3F6B66",
  pink:  "#C8A96E",
  cyan:  "#3F6B66",
  lilac: "#C8A96E",
  olive: "#3F6B66",
  faint: "rgba(14,42,42,0.40)",
};

// ── Mini icons (1.5 stroke, 14px) ────────────────────────────────────
const I = (d, fill = false) => ({ size = 14, c = "currentColor", style }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill={fill ? c : "none"} stroke={fill ? "none" : c}
    strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" style={{ display: "block", flexShrink: 0, ...style }}>
    {d}
  </svg>
);
const Ic = {
  grid: I(<g><rect x="2" y="2" width="5" height="5" rx="1"/><rect x="9" y="2" width="5" height="5" rx="1"/><rect x="2" y="9" width="5" height="5" rx="1"/><rect x="9" y="9" width="5" height="5" rx="1"/></g>),
  chart: I(<path d="M2 13l3.5-4 2.5 2 4-5 2 2.5"/>),
  link: I(<g><path d="M6.5 9.5l3-3"/><path d="M5 11a2 2 0 0 1 0-3l1.5-1.5"/><path d="M11 5a2 2 0 0 1 0 3L9.5 9.5"/></g>),
  list: I(<g><path d="M3 4h10M3 8h10M3 12h6"/></g>),
  topo: I(<g><circle cx="3.5" cy="8" r="1.5"/><circle cx="12.5" cy="3.5" r="1.5"/><circle cx="12.5" cy="12.5" r="1.5"/><path d="M5 8l6-4M5 8l6 4"/></g>),
  map: I(<g><path d="M2 4l4-1 4 2 4-1v10l-4 1-4-2-4 1V4z"/><path d="M6 3v9M10 5v9"/></g>),
  globe: I(<g><circle cx="8" cy="8" r="5.5"/><path d="M2.5 8h11M8 2.5c2 1.8 2 9.2 0 11M8 2.5c-2 1.8-2 9.2 0 11"/></g>),
  rules: I(<g><circle cx="4" cy="4" r="1.2"/><circle cx="4" cy="12" r="1.2"/><path d="M6 4h7M6 12h7M4 5.2v5.6"/></g>),
  cube: I(<g><path d="M8 1.5L13.5 4v8L8 14.5 2.5 12V4L8 1.5z"/><path d="M2.5 4L8 6.5l5.5-2.5M8 6.5v8"/></g>),
  doc: I(<g><path d="M3.5 1.5h6L13 5v9.5h-9.5z"/><path d="M9 1.5V5h4"/><path d="M5.5 8h5M5.5 11h5"/></g>),
  sliders: I(<g><path d="M3 4h6M11 4h2M3 12h2M7 12h6"/><circle cx="10" cy="4" r="1.2"/><circle cx="6" cy="12" r="1.2"/></g>),
  bell: I(<g><path d="M8 2c-2.5 0-4 1.8-4 4v3l-1 2h10l-1-2V6c0-2.2-1.5-4-4-4z"/><path d="M6.5 12.5a1.5 1.5 0 0 0 3 0"/></g>),
  chevR: I(<path d="M6 3l5 5-5 5"/>),
  chevD: I(<path d="M3 6l5 5 5-5"/>),
  chevUD: I(<g><path d="M5 6l3-3 3 3M5 10l3 3 3-3"/></g>),
  refresh: I(<g><path d="M13 7a5 5 0 1 0 .2 2.5"/><path d="M13 3v4h-4"/></g>),
  search: I(<g><circle cx="7" cy="7" r="4"/><path d="M10 10l3 3"/></g>),
  plus: I(<g><path d="M8 3v10M3 8h10"/></g>),
  copy: I(<g><rect x="3" y="3" width="8" height="8" rx="1"/><path d="M5.5 13h6a1.5 1.5 0 0 0 1.5-1.5v-6"/></g>),
  pause: I(<g><rect x="4" y="3.5" width="2.2" height="9" rx="0.4"/><rect x="9.8" y="3.5" width="2.2" height="9" rx="0.4"/></g>),
  play: I(<path d="M5 3l7 5-7 5V3z"/>, true),
  trash: I(<g><path d="M3 4.5h10M6 4.5V3h4v1.5M5 4.5l.5 9h5l.5-9"/></g>),
  cmd: I(<g><path d="M5 5a1.5 1.5 0 1 0 1.5 1.5V11A1.5 1.5 0 1 0 8 9.5h3A1.5 1.5 0 1 0 9.5 11V6.5A1.5 1.5 0 1 0 11 5H6.5"/></g>),
  outbound: I(<g><path d="M2.5 8h7M6 4.5L9.5 8 6 11.5"/><path d="M11.5 3v10"/></g>),
  arrowR: I(<path d="M3 8h10M9 4l4 4-4 4"/>),
  pinPlus: I(<g><circle cx="6.5" cy="6.5" r="3.5"/><path d="M6.5 4.5v4M4.5 6.5h4M9.5 9.5l3 3"/></g>),
  takeover: I(<g><path d="M8 1.5l5 2v5c0 3-2.2 5-5 6-2.8-1-5-3-5-6v-5l5-2z"/></g>),
  spark: I(<g><path d="M8 1.5l1 4 4 1-4 1-1 4-1-4-4-1 4-1z"/></g>),
  tv: I(<g><rect x="2" y="3" width="12" height="8" rx="1.2"/><path d="M5 13.5h6"/></g>),
  music: I(<g><path d="M6 12V4l6-1.5v8"/><circle cx="5" cy="12" r="1.2"/><circle cx="11" cy="10.5" r="1.2"/></g>),
  flag: I(<g><path d="M3.5 14V2.5M3.5 3h8l-1.5 2.5L11.5 8h-8"/></g>),
  hand: I(<g><path d="M5 8V4.5a1 1 0 1 1 2 0V8M7 7.5V3.5a1 1 0 1 1 2 0v4M9 7V5a1 1 0 1 1 2 0v6c0 2-1.5 3-3.5 3S4 13 4 11V8.5"/></g>),
  swap: I(<g><path d="M4 5h8M9 2.5L12.5 5 9 7.5M12 11H4M7 8.5L3.5 11 7 13.5"/></g>),
  desktop: I(<g><rect x="2" y="3" width="12" height="8" rx="1"/><path d="M6 13.5h4M8 11v2.5"/></g>),
  web: I(<g><circle cx="8" cy="8" r="5.5"/><path d="M2.5 8h11"/></g>),
  cpu: I(<g><rect x="3.5" y="3.5" width="9" height="9" rx="1.2"/><rect x="6" y="6" width="4" height="4" rx="0.5"/><path d="M5.5 1.5v2M10.5 1.5v2M5.5 12.5v2M10.5 12.5v2M1.5 5.5h2M1.5 10.5h2M12.5 5.5h2M12.5 10.5h2"/></g>),
  folder: I(<path d="M2 4.5a1 1 0 0 1 1-1h3l1.5 1.5h5.5a1 1 0 0 1 1 1V12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4.5z"/>),
  gear: I(<g><circle cx="8" cy="8" r="2"/><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4"/></g>),
  power: I(<g><path d="M8 2v6"/><path d="M4.5 4.5a5 5 0 1 0 7 0"/></g>),
  ai: I(<g><path d="M8 2L9 6l4 1-4 1-1 4-1-4-4-1 4-1z"/><path d="M12.5 2.5l.5 1.5 1.5.5-1.5.5-.5 1.5-.5-1.5L10.5 4.5l1.5-.5z"/></g>),
  eye: I(<g><path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"/><circle cx="8" cy="8" r="2"/></g>),
  eyeOff: I(<g><path d="M2 8s2.5-4.5 6-4.5c1.4 0 2.6.5 3.6 1.2M14 8s-1 1.7-2.7 3M2 2l12 12"/><path d="M9.5 9.5a2 2 0 0 1-3-3"/></g>),
  shield: I(<g><path d="M8 1.5l5 2v5c0 3-2.2 5-5 6-2.8-1-5-3-5-6v-5l5-2z"/><path d="M5.5 8l1.7 1.7L11 6"/></g>),
};

// ── Status dot ───────────────────────────────────────────────────────
const Dot = ({ c = C.green, size = 7, pulse }) => (
  <span style={{ width: size, height: size, borderRadius: "50%", background: c, display: "inline-block", flexShrink: 0,
    boxShadow: `0 0 0 ${size/2}px ${c}22`,
    animation: pulse ? "chh-pulse 1.6s ease-in-out infinite" : "none" }}/>
);

// ── Cat mark (the character in the references) ───────────────────────
const CatMark = ({ size = 32, dark }) => (
  <svg width={size} height={size} viewBox="0 0 40 40" style={{ display: "block" }}>
    <defs>
      <radialGradient id="catfur" cx="50%" cy="40%" r="65%">
        <stop offset="0%" stopColor={dark ? "#3a3a40" : "#3a3530"}/>
        <stop offset="100%" stopColor={dark ? "#1a1a1d" : "#1c1814"}/>
      </radialGradient>
    </defs>
    {/* head */}
    <path d="M8 14 L13 6 L16 12 Q20 10 24 12 L27 6 L32 14 Q34 22 30 28 Q24 34 20 34 Q16 34 10 28 Q6 22 8 14 Z"
      fill="url(#catfur)"/>
    {/* eye whites */}
    <ellipse cx="15" cy="20" rx="2.4" ry="2.8" fill="#fff7d6"/>
    <ellipse cx="25" cy="20" rx="2.4" ry="2.8" fill="#fff7d6"/>
    {/* pupils */}
    <ellipse cx="15" cy="20.5" rx="0.8" ry="1.6" fill="#1a1a1a"/>
    <ellipse cx="25" cy="20.5" rx="0.8" ry="1.6" fill="#1a1a1a"/>
    {/* nose/mouth */}
    <path d="M19 25 Q20 26 21 25 M20 25 V26.5 Q19 27.3 18.4 27 M20 26.5 Q21 27.3 21.6 27" stroke="#fff7d6" strokeWidth="0.6" fill="none" strokeLinecap="round"/>
    {/* whiskers */}
    <path d="M11 24 L14 24.4 M11 26 L14 25.4 M29 24 L26 24.4 M29 26 L26 25.4" stroke={dark ? "#666" : "#aaa"} strokeWidth="0.4"/>
    {/* inner ears */}
    <path d="M12 9 L13.5 11 L14.5 9.5" fill={dark ? "#5a3540" : "#7a4050"} opacity="0.7"/>
    <path d="M28 9 L26.5 11 L25.5 9.5" fill={dark ? "#5a3540" : "#7a4050"} opacity="0.7"/>
  </svg>
);

// ── Static data ──────────────────────────────────────────────────────
const PROXY_GROUPS = [
  { id: "ai",        name: "AI",        emoji: "✨", icon: "ai",   selected: "US-Auto", type: "select",   nodes: [
    { id: "US-Auto",  name: "US-Auto",   region: "US", flag: "🇺🇸", proto: "Trojan",    ping: 142 },
    { id: "JP-GPT",   name: "JP-GPT",    region: "JP", flag: "🇯🇵", proto: "VLESS",     ping: 64 },
    { id: "SG-Claude",name: "SG-Claude", region: "SG", flag: "🇸🇬", proto: "Hysteria2", ping: 88 },
  ]},
  { id: "social",    name: "Social",    emoji: "🐦", icon: "globe", selected: "Auto", type: "url-test", nodes: [
    { id: "Auto",     name: "Auto",      region: "—",  flag: "🌐", proto: "—",         ping: 56 },
    { id: "TW-1",     name: "TW-1",      region: "TW", flag: "🇹🇼", proto: "Trojan",    ping: 38 },
    { id: "JP-1",     name: "JP-1",      region: "JP", flag: "🇯🇵", proto: "VLESS",     ping: 56 },
  ]},
  { id: "streaming", name: "Streaming", emoji: "🎬", icon: "tv",    selected: "Auto", type: "url-test", nodes: [
    { id: "Auto",     name: "Auto",      region: "—",  flag: "🌐", proto: "—",         ping: 142 },
    { id: "US-Strm",  name: "US-Strm",   region: "US", flag: "🇺🇸", proto: "Trojan",    ping: 142 },
    { id: "JP-Strm",  name: "JP-Strm",   region: "JP", flag: "🇯🇵", proto: "VLESS",     ping: 62 },
    { id: "SG-Strm",  name: "SG-Strm",   region: "SG", flag: "🇸🇬", proto: "Hysteria2", ping: 88 },
  ]},
  { id: "google",    name: "Google",    emoji: "🅖", icon: "globe", selected: "Auto", type: "url-test", nodes: [
    { id: "Auto",     name: "Auto",      region: "—",  flag: "🌐", proto: "—",         ping: 88 },
    { id: "JP-G",     name: "JP-G",      region: "JP", flag: "🇯🇵", proto: "VLESS",     ping: 62 },
    { id: "SG-G",     name: "SG-G",      region: "SG", flag: "🇸🇬", proto: "Hysteria2", ping: 88 },
  ]},
  { id: "china",     name: "China",     emoji: "🇨🇳", icon: "flag",  selected: "DIRECT", type: "select",   nodes: [
    { id: "DIRECT",   name: "DIRECT",    region: "—",  flag: "↪︎", proto: "—",         ping: 0 },
  ]},
  { id: "manual",    name: "Manual",    emoji: "👋", icon: "hand",  selected: "reality", type: "select",   nodes: [
    { id: "reality",  name: "reality",   region: "TW", flag: "🇹🇼", proto: "VLESS",     ping: 38 },
    { id: "trojan-1", name: "trojan-1",  region: "JP", flag: "🇯🇵", proto: "Trojan",    ping: 64 },
  ]},
];

const RULES = [
  { type: "DOMAIN-SUFFIX",  match: "openai.com",       action: "AI",        hits: 318 },
  { type: "DOMAIN-SUFFIX",  match: "anthropic.com",    action: "AI",        hits: 187 },
  { type: "DOMAIN-KEYWORD", match: "google",           action: "Google",    hits: 1284 },
  { type: "DOMAIN-SUFFIX",  match: "youtube.com",      action: "Streaming", hits: 962 },
  { type: "DOMAIN-SUFFIX",  match: "twitter.com",      action: "Social",    hits: 412 },
  { type: "GEOIP",          match: "CN",               action: "DIRECT",    hits: 5210 },
  { type: "IP-CIDR",        match: "192.168.0.0/16",   action: "DIRECT",    hits: 88 },
  { type: "DOMAIN-SUFFIX",  match: "apple.com",        action: "DIRECT",    hits: 412 },
  { type: "DOMAIN-SUFFIX",  match: "github.com",       action: "DIRECT",    hits: 633 },
  { type: "PROCESS-NAME",   match: "Xcode",            action: "DIRECT",    hits: 14 },
  { type: "MATCH",          match: "—",                action: "Manual",    hits: 73 },
];

const RANKING = [
  { name: "DE-Server",    color: C.purple, val: 17.9 },
  { name: "US-OpenAI",    color: C.pink,   val: 7.3 },
  { name: "US-Streaming", color: C.lilac,  val: 2.5 },
  { name: "DIRECT",       color: C.faint,  val: 2.4 },
  { name: "FR-Canal",     color: C.cyan,   val: 2.2 },
  { name: "JP-GPT",       color: C.amber,  val: 1.3 },
  { name: "COMPATIBLE",   color: C.olive,  val: 0.4 },
];

// ── Layout primitives ────────────────────────────────────────────────
const Card = ({ t, children, padding = 14, style = {}, title, right, icon: Ico, iconColor }) => (
  <div style={{
    background: t.card, borderRadius: 12,
    border: `0.5px solid ${t.line}`,
    boxShadow: "0 0 0 0.5px rgba(0,0,0,0.02), 0 1px 2px rgba(0,0,0,0.03)",
    overflow: "hidden", ...style,
  }}>
    {title && (
      <div style={{
        padding: "11px 14px 8px", display: "flex", alignItems: "center", gap: 8,
        fontSize: 12.5, fontWeight: 600, color: t.text, letterSpacing: -0.1,
      }}>
        {Ico && <span style={{ color: iconColor || t.dim, display: "inline-flex" }}><Ico size={13}/></span>}
        <span style={{ flex: 1 }}>{title}</span>
        {right}
      </div>
    )}
    <div style={{ padding: title ? "0 14px 14px" : padding }}>{children}</div>
  </div>
);

const Stat = ({ t, label, value, icon: Ico, color = C.warm }) => (
  <div>
    <div style={{ fontSize: 10.5, fontWeight: 500, color: t.dim, display: "flex", alignItems: "center", gap: 4, marginBottom: 4 }}>
      {Ico && <Ico size={11}/>}{label}
    </div>
    <div className="serif" style={{ fontSize: 26, fontWeight: 500, color, fontVariantNumeric: "tabular-nums", letterSpacing: -0.4 }}>{value}</div>
  </div>
);

const Pill = ({ t, active, onClick, children, style }) => (
  <button onClick={onClick} style={{
    height: 26, padding: "0 11px", border: 0, borderRadius: 7,
    background: active ? t.pillBg : "transparent",
    color: t.text, fontSize: 12, fontWeight: active ? 600 : 500, cursor: "pointer",
    boxShadow: active ? "0 0 0 0.5px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)" : "none",
    ...style,
  }}>{children}</button>
);

const Seg = ({ t, value, onChange, options }) => (
  <div style={{
    display: "inline-flex", padding: 2, borderRadius: 8,
    background: t.fill, border: `0.5px solid ${t.line}`,
  }}>
    {options.map(o => (
      <Pill key={o.value} t={t} active={value === o.value} onClick={() => onChange(o.value)} style={{ height: 24, padding: "0 12px" }}>
        {o.label}
      </Pill>
    ))}
  </div>
);

// ── Sparkline ────────────────────────────────────────────────────────
const Spark = ({ data, color, fill, height = 70, dot = true }) => {
  const W = 360;
  const max = Math.max(1, ...data);
  const pts = data.map((v, i) => [(i / (data.length - 1)) * W, height - (v / max) * (height - 6) - 3]);
  const line = "M" + pts.map(p => p.join(",")).join(" L ");
  const area = line + ` L ${W},${height} L 0,${height} Z`;
  const last = pts[pts.length - 1];
  const gid = "sg" + Math.random().toString(36).slice(2, 7);
  return (
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" style={{ width: "100%", height, display: "block" }}>
      <defs><linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor={fill} stopOpacity="0.30"/>
        <stop offset="100%" stopColor={fill} stopOpacity="0"/>
      </linearGradient></defs>
      <path d={area} fill={`url(#${gid})`}/>
      <path d={line} fill="none" stroke={color} strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round"/>
      {dot && <circle cx={last[0]} cy={last[1]} r="2.4" fill={color}/>}
    </svg>
  );
};

// ── Bar chart for 7-day ──────────────────────────────────────────────
const Bars7 = ({ t, data }) => {
  const max = Math.max(...data.map(d => d.v));
  const avg = data.reduce((a, b) => a + b.v, 0) / data.length;
  const avgY = (1 - avg / max) * 100;
  return (
    <div style={{ position: "relative", height: 110, display: "flex", alignItems: "flex-end", gap: 8 }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: `${avgY}%`, borderTop: `1px dashed ${C.warm}`, opacity: 0.7 }}/>
      {data.map((d, i) => (
        <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
          <div style={{ width: "100%", height: 90, display: "flex", alignItems: "flex-end" }}>
            <div style={{ width: "100%", height: `${(d.v / max) * 100}%`, background: t.fillStrong, borderRadius: "3px 3px 0 0",
              borderBottom: d.today ? `2px solid ${C.warm}` : "none" }}/>
          </div>
          <span style={{ fontSize: 10.5, color: t.dim }}>{d.label}</span>
        </div>
      ))}
    </div>
  );
};

// ── Donut for traffic split ──────────────────────────────────────────
const Donut = ({ direct, proxy, t }) => {
  const total = direct + proxy;
  const pProxy = proxy / total;
  const R = 38, C2 = 2 * Math.PI * R;
  return (
    <svg width="120" height="120" viewBox="0 0 100 100">
      <defs>
        <linearGradient id="don" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor={C.cyan}/>
          <stop offset="50%" stopColor={C.lilac}/>
          <stop offset="100%" stopColor={C.pink}/>
        </linearGradient>
      </defs>
      <circle cx="50" cy="50" r={R} stroke={t.fillStrong} strokeWidth="8" fill="none"/>
      <circle cx="50" cy="50" r={R} stroke="url(#don)" strokeWidth="8" fill="none"
        strokeDasharray={`${pProxy * C2} ${C2}`} strokeDashoffset={C2 * 0.25} strokeLinecap="round"
        transform="rotate(-90 50 50)" style={{ transform: "rotate(-90deg)", transformOrigin: "50% 50%" }}/>
      <text x="50" y="48" textAnchor="middle" fontSize="9" fill={t.dim}>Total</text>
      <text x="50" y="60" textAnchor="middle" fontSize="13" fontWeight="700" fill={t.text} fontFamily="ui-sans-serif">{(total).toFixed(1)} MB</text>
    </svg>
  );
};

// ── Sidebar ──────────────────────────────────────────────────────────
const NavItem = ({ t, icon: Ico, label, active, onClick, accent }) => (
  <button onClick={onClick} style={{
    width: "calc(100% - 12px)", margin: "1px 6px", height: 28,
    display: "flex", alignItems: "center", gap: 10, padding: "0 10px",
    borderRadius: 7, border: 0, cursor: "pointer", textAlign: "left",
    background: active ? t.sideActive : "transparent",
    color: active ? t.text : t.dim,
    fontSize: 12.5, fontWeight: active ? 600 : 500,
  }}
  onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = t.sideHover; }}
  onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = "transparent"; }}>
    <span style={{ color: active ? (accent || C.blue) : t.dim, display: "inline-flex" }}><Ico size={14}/></span>
    <span>{label}</span>
  </button>
);

const SideHead = ({ t, children }) => (
  <div style={{ padding: "14px 16px 4px", fontSize: 10, fontWeight: 600, color: t.faint,
    letterSpacing: 0.4, textTransform: "uppercase" }}>{children}</div>
);

const Sidebar = ({ t, dark, screen, setScreen, collapsed, setCollapsed }) => {
  if (collapsed) return null;
  return (
    <div style={{
      width: 200, height: "100%", flexShrink: 0,
      background: t.side, borderRight: `0.5px solid ${t.line}`,
      display: "flex", flexDirection: "column",
      backdropFilter: "blur(40px) saturate(180%)",
      WebkitBackdropFilter: "blur(40px) saturate(180%)",
    }}>
      {/* title row with traffic lights + wordmark */}
      <div style={{ height: 44, padding: "0 14px", display: "flex", alignItems: "center", gap: 9 }}>
        <span style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57", border: "0.5px solid rgba(0,0,0,0.10)" }}/>
        <span style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e", border: "0.5px solid rgba(0,0,0,0.10)" }}/>
        <span style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840", border: "0.5px solid rgba(0,0,0,0.10)" }}/>
        <span style={{ flex: 1 }}/>
        <span className="serif" style={{ fontSize: 15, fontWeight: 500, color: t.text, letterSpacing: -0.1 }}>
          中華<span style={{ color: C.brass, marginLeft: 2 }}>·</span>
        </span>
      </div>

      <div className={"sc" + (dark ? " dk" : "")} style={{ flex: 1, overflowY: "auto", paddingBottom: 8 }}>
        <NavItem t={t} icon={Ic.grid}  label="Overview"     active={screen === "overview"}     onClick={() => setScreen("overview")}     accent={C.warm}/>
        <NavItem t={t} icon={Ic.chart} label="Traffic Stats" active={screen === "traffic"}      onClick={() => setScreen("traffic")}      accent={C.purple}/>
        <NavItem t={t} icon={Ic.link}  label="Connections"  active={screen === "connections"}  onClick={() => setScreen("connections")}  accent={C.blue}/>
        <NavItem t={t} icon={Ic.list}  label="Logs"         active={screen === "logs"}         onClick={() => setScreen("logs")}         accent={C.dim}/>

        <SideHead t={t}>Visualization</SideHead>
        <NavItem t={t} icon={Ic.topo}  label="Topology"     active={screen === "topology"}     onClick={() => setScreen("topology")}     accent={C.cyan}/>
        <NavItem t={t} icon={Ic.map}   label="Route Map"    active={screen === "routemap"}    onClick={() => setScreen("routemap")}    accent={C.green}/>

        <SideHead t={t}>Proxy</SideHead>
        <NavItem t={t} icon={Ic.globe} label="Proxies"      active={screen === "proxies"}      onClick={() => setScreen("proxies")}      accent={C.blue}/>
        <NavItem t={t} icon={Ic.rules} label="Rules"        active={screen === "rules"}        onClick={() => setScreen("rules")}        accent={C.amber}/>
        <NavItem t={t} icon={Ic.cube}  label="Providers"    active={screen === "providers"}    onClick={() => setScreen("providers")}    accent={C.purple}/>

        <SideHead t={t}>Config</SideHead>
        <NavItem t={t} icon={Ic.doc}    label="Profiles"    active={screen === "profiles"}    onClick={() => setScreen("profiles")}    accent={C.pink}/>
        <NavItem t={t} icon={Ic.sliders} label="Advanced"   active={screen === "advanced"}    onClick={() => setScreen("advanced")}    accent={C.olive}/>
      </div>

      {/* footer — settings only */}
      <div style={{ padding: 6, borderTop: `0.5px solid ${t.line}` }}>
        <button style={{
          width: "100%", height: 28, padding: "0 10px",
          display: "flex", alignItems: "center", gap: 10, borderRadius: 7,
          border: 0, background: "transparent", color: t.dim, fontSize: 12.5, fontWeight: 500,
          cursor: "pointer", textAlign: "left",
        }}
        onMouseEnter={(e) => e.currentTarget.style.background = t.sideHover}
        onMouseLeave={(e) => e.currentTarget.style.background = "transparent"}>
          <Ic.gear size={14}/>Settings
        </button>
      </div>
    </div>
  );
};

// ── Toolbar ──────────────────────────────────────────────────────────
const ToggleChip = ({ t, on, onClick, icon: Ico, label, color = C.warm, offColor }) => (
  <button onClick={onClick} title={label} style={{
    width: 30, height: 30, borderRadius: "50%", cursor: "pointer",
    border: 0, padding: 0,
    background: on
      ? `linear-gradient(135deg, ${color}, ${color}dd)`
      : (offColor || t.fill),
    color: on ? "#fff" : t.dim,
    boxShadow: on
      ? `0 0 0 0.5px ${color}66, 0 2px 6px ${color}40`
      : `inset 0 0 0 0.5px ${t.line}`,
    display: "inline-flex", alignItems: "center", justifyContent: "center",
    transition: "all 180ms ease",
    position: "relative",
  }}>
    <Ico size={13}/>
    {on && <span style={{
      position: "absolute", bottom: -1, right: -1,
      width: 8, height: 8, borderRadius: "50%",
      background: C.green, boxShadow: `0 0 0 1.5px ${t.bg}`,
    }}/>}
  </button>
);

const Toolbar = ({ t, dark, title, mode, setMode, profile, setProfile, collapsed, setCollapsed,
  sysProxy, setSysProxy, tunMode, setTunMode, anon, setAnon }) => (
  <div style={{
    height: 48, flexShrink: 0,
    display: "flex", alignItems: "center", padding: "0 14px", gap: 12,
    borderBottom: `0.5px solid ${t.line}`,
    background: t.bg,
  }}>
    <button onClick={() => setCollapsed(!collapsed)} style={{
      width: 28, height: 28, border: 0, borderRadius: 7,
      background: "transparent", color: t.dim, cursor: "pointer",
      display: "inline-flex", alignItems: "center", justifyContent: "center",
    }}><Ic.list size={14}/></button>
    <div className="serif" style={{ fontSize: 18, fontWeight: 500, color: t.text, letterSpacing: -0.2 }}>{title}</div>

    <div style={{ flex: 1 }}/>

    <button style={{
      width: 30, height: 28, border: 0, borderRadius: 7, background: "transparent", color: t.dim, cursor: "pointer",
      display: "inline-flex", alignItems: "center", justifyContent: "center",
    }}><Ic.bell size={14}/></button>

    {/* profile dropdown */}
    <button style={{
      height: 28, padding: "0 10px", border: 0, borderRadius: 8,
      background: t.pillBg, boxShadow: "0 0 0 0.5px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.04)",
      color: t.text, fontSize: 12, fontWeight: 500, cursor: "pointer",
      display: "inline-flex", alignItems: "center", gap: 6,
    }}>{profile} <Ic.chevUD size={11} c={t.dim}/></button>

    {/* outbound mode segmented */}
    <Seg t={t} value={mode} onChange={setMode} options={[
      { value: "Direct", label: "Direct" },
      { value: "Rule",   label: "Rule" },
      { value: "Global", label: "Global" },
    ]}/>

    {/* trailing toggles: System Proxy · TUN · Anonymous */}
    <div style={{ display: "inline-flex", gap: 6, marginLeft: 2 }}>
      <ToggleChip t={t} on={sysProxy} onClick={() => setSysProxy(!sysProxy)}
        icon={Ic.web} label={`System Proxy · ${sysProxy ? "ON" : "OFF"}`} color={C.patina}/>
      <ToggleChip t={t} on={tunMode} onClick={() => setTunMode(!tunMode)}
        icon={Ic.shield} label={`TUN Mode · ${tunMode ? "ON" : "OFF"}`} color={C.brass}/>
      <ToggleChip t={t} on={anon} onClick={() => setAnon(!anon)}
        icon={anon ? Ic.eyeOff : Ic.eye}
        label={`Anonymous Mode · ${anon ? "ON (info masked)" : "OFF"}`} color={C.ink}/>
    </div>
  </div>
);

// ── Overview ─────────────────────────────────────────────────────────
const Overview = ({ t, dark, traffic }) => {
  const dn = traffic.down[traffic.down.length - 1] / 1024;
  const up = traffic.up[traffic.up.length - 1] / 1024;
  const days = [
    { label: "Sat", v: 920, today: false },
    { label: "Fri", v: 1180, today: false },
    { label: "Thu", v: 760, today: false },
    { label: "Wed", v: 510, today: false },
    { label: "Tue", v: 420, today: false },
    { label: "Mon", v: 980, today: false },
    { label: "Sun", v: 1360, today: true },
  ];
  return (
    <div style={{ padding: "16px 18px", display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>

      {/* Running Status */}
      <Card t={t} title="Running Status" icon={Ic.power} iconColor={C.green}
        right={<Dot c={C.green} size={8} pulse/>}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginBottom: 16 }}>
          <Stat t={t} label="Uptime"      value="5:53" icon={Ic.power}  color={C.warm}/>
          <Stat t={t} label="Connections" value="45"   icon={Ic.link}   color={C.warm}/>
          <Stat t={t} label="Kernel Memory" value="62 MB" icon={Ic.cpu} color={C.warm}/>
        </div>
        <div style={{ borderTop: `0.5px solid ${t.lineSoft}`, paddingTop: 12,
          display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14 }}>
          <SubStat t={t} icon={Ic.desktop} label="System"  value="macOS 26.3"/>
          <SubStat t={t} icon={Ic.cube}    label="Version" value="26.7-beta.7 (134)"/>
          <SubStat t={t} icon={Ic.cpu}     label="Kernel"  value="alpha-smart-172b16e"/>
        </div>
      </Card>

      {/* Network Status */}
      <Card t={t} title="Network Status" icon={Ic.web} iconColor={C.purple}
        right={<button style={btnGhost(t)}><Ic.refresh size={12}/></button>}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginBottom: 16 }}>
          <Stat t={t} label="Internet" value="213 ms" icon={Ic.web}  color={C.warm}/>
          <Stat t={t} label="DNS"      value="48 ms"  icon={Ic.swap} color={C.warm}/>
          <Stat t={t} label="Router"   value="6 ms"   icon={Ic.cube} color={C.warm}/>
        </div>
        <div style={{ borderTop: `0.5px solid ${t.lineSoft}`, paddingTop: 12,
          display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14 }}>
          <SubStat t={t} icon={Ic.web}    label="Network"  value="Wi-Fi"/>
          <SubStat t={t} icon={Ic.cube}   label="Local IP" value={<span className="ch-mask">CN 海西…168.157.83</span>}/>
          <SubStat t={t} icon={Ic.globe}  label="Proxy IP" value={<span className="ch-mask">HK Hong…249.100.80</span>}/>
        </div>
      </Card>

      {/* Traffic Stats */}
      <Card t={t} title="Traffic Stats" icon={Ic.chart} iconColor={C.purple}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
              <span style={{ fontSize: 11, color: t.dim, display: "inline-flex", alignItems: "center", gap: 4 }}>
                <span style={{ color: C.purple }}>↑</span>Upload Speed
              </span>
            </div>
            <div style={{ fontSize: 22, fontWeight: 700, color: C.purple, fontVariantNumeric: "tabular-nums", letterSpacing: -0.3 }}>
              {up.toFixed(1)} <span style={{ fontSize: 14, fontWeight: 600 }}>KB/s</span>
            </div>
            <div style={{ marginTop: 6 }}>
              <Spark data={traffic.up} color={C.purple} fill={C.purple} height={56}/>
            </div>
          </div>
          <div>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
              <span style={{ fontSize: 11, color: t.dim, display: "inline-flex", alignItems: "center", gap: 4 }}>
                <span style={{ color: C.cyan }}>↓</span>Download Speed
              </span>
            </div>
            <div style={{ fontSize: 22, fontWeight: 700, color: C.cyan, fontVariantNumeric: "tabular-nums", letterSpacing: -0.3 }}>
              {dn.toFixed(1)} <span style={{ fontSize: 14, fontWeight: 600 }}>KB/s</span>
            </div>
            <div style={{ marginTop: 6 }}>
              <Spark data={traffic.down} color={C.cyan} fill={C.cyan} height={56}/>
            </div>
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8, paddingTop: 10,
          borderTop: `0.5px solid ${t.lineSoft}`, fontSize: 11, color: t.dim }}>
          <span>↑ Upload <strong style={{ color: t.text, fontWeight: 600 }}>410 KB</strong></span>
          <span>↓ Download <strong style={{ color: t.text, fontWeight: 600 }}>14.4 MB</strong></span>
        </div>
      </Card>

      {/* 7-Day Trend */}
      <Card t={t} title="7-Day Traffic Trend" icon={Ic.chart} iconColor={C.amber}
        right={<button style={btnGhost(t)}><Ic.refresh size={12}/></button>}>
        <div style={{ fontSize: 11, color: t.dim, marginBottom: 4 }}>Daily Avg</div>
        <div style={{ fontSize: 24, fontWeight: 700, color: t.text, letterSpacing: -0.3, marginBottom: 8 }}>883.5 MB</div>
        <Bars7 t={t} data={days}/>
      </Card>

      {/* Traffic Summary */}
      <Card t={t} title="Traffic Summary" icon={Ic.chart} iconColor={C.pink}
        style={{ gridColumn: "span 2" }}
        right={<>
          <Seg t={t} value="Today" onChange={() => {}} options={[
            { value: "Today", label: "Today" },
            { value: "Month", label: "This Month" },
            { value: "Last", label: "Last Month" },
          ]}/>
          <button style={{ ...btnGhost(t), marginLeft: 6 }}><Ic.refresh size={12}/></button>
        </>}>
        <div style={{ display: "grid", gridTemplateColumns: "auto 1.4fr 1fr", gap: 24, alignItems: "center" }}>
          <Donut direct={2.4} proxy={31.8} t={t}/>
          <div>
            <SummaryRow t={t} label="Upload"   value="15.9 MB" dotColor={C.purple}/>
            <SummaryRow t={t} label="Download" value="18.3 MB" dotColor={C.cyan}/>
            <div style={{ height: 1, background: t.lineSoft, margin: "10px 0" }}/>
            <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
              <span style={{ fontSize: 11, color: t.dim, display: "inline-flex", alignItems: "center", gap: 6 }}>
                <Dot c={C.faint} size={6}/> Direct <strong style={{ color: t.text, fontWeight: 600 }}>2.4 MB</strong>
              </span>
              <span style={{ fontSize: 11, color: t.dim, display: "inline-flex", alignItems: "center", gap: 6 }}>
                <Dot c={C.pink} size={6}/> Proxy <strong style={{ color: t.text, fontWeight: 600 }}>31.8 MB</strong>
              </span>
            </div>
            {/* split bar */}
            <div style={{ height: 6, borderRadius: 3, background: t.fillStrong, marginTop: 8, overflow: "hidden", display: "flex" }}>
              <div style={{ width: "7%", background: t.faint }}/>
              <div style={{ flex: 1, background: `linear-gradient(90deg, ${C.lilac}, ${C.pink})` }}/>
            </div>
          </div>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 8, fontSize: 10.5, fontWeight: 600,
              color: t.dim, textTransform: "uppercase", letterSpacing: 0.4 }}>
              <Ic.chart size={11}/>Ranking
              <div style={{ flex: 1 }}/>
              <Seg t={t} value="Proxy" onChange={() => {}} options={[
                { value: "Proxy",     label: "Proxy" },
                { value: "Process",   label: "Process" },
                { value: "Interface", label: "Interface" },
                { value: "Hostname",  label: "Hostname" },
              ]}/>
            </div>
            {RANKING.map(r => (
              <div key={r.name} style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 5, fontSize: 11 }}>
                <Dot c={r.color} size={6}/>
                <span style={{ color: t.text, width: 100 }}>{r.name}</span>
                <div style={{ flex: 1, height: 5, borderRadius: 2.5, background: t.fillStrong, overflow: "hidden" }}>
                  <div style={{ height: "100%", width: `${(r.val / 18) * 100}%`, background: r.color, opacity: 0.8 }}/>
                </div>
                <span style={{ color: t.dim, fontVariantNumeric: "tabular-nums", width: 50, textAlign: "right" }}>
                  {r.val < 1 ? `${(r.val * 1024).toFixed(0)} KB` : `${r.val.toFixed(1)} MB`}
                </span>
              </div>
            ))}
          </div>
        </div>
      </Card>
    </div>
  );
};

const SubStat = ({ t, icon: Ico, label, value }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
    <span style={{ fontSize: 10.5, color: t.dim, display: "inline-flex", alignItems: "center", gap: 4 }}>
      <Ico size={11}/>{label}
    </span>
    <span style={{ fontSize: 12, fontWeight: 600, color: t.text }}>{value}</span>
  </div>
);

const SummaryRow = ({ t, label, value, dotColor }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 0", fontSize: 12 }}>
    <Dot c={dotColor} size={6}/>
    <span style={{ color: t.dim }}>{label}</span>
    <div style={{ flex: 1 }}/>
    <span style={{ color: t.text, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>{value}</span>
  </div>
);

const btnGhost = (t) => ({
  width: 22, height: 22, border: 0, borderRadius: 6,
  background: "transparent", color: t.dim, cursor: "pointer",
  display: "inline-flex", alignItems: "center", justifyContent: "center",
});

// ── Proxies screen ───────────────────────────────────────────────────
const pingColor = (p, t) => p === 0 ? t.faint : p < 80 ? C.green : p < 150 ? C.amber : C.red;
const pingTier = (p) => p === 0 ? "—" : p < 80 ? "Fast" : p < 150 ? "OK" : "Slow";

// Build local mutable copy so latency tests can update
const initGroups = () => PROXY_GROUPS.map(g => ({
  ...g,
  nodes: g.nodes.map(n => ({ ...n, testing: false, lastTested: "2 min ago" }))
}));

const NodeCard = ({ t, n, active, onClick, onTest }) => {
  const pc = pingColor(n.ping, t);
  const pct = n.ping === 0 ? 0 : Math.max(8, Math.min(100, 100 - (n.ping / 250) * 100));
  return (
    <button onClick={onClick} style={{
      position: "relative", textAlign: "left", cursor: "pointer",
      background: active ? `${C.warm}10` : t.card,
      border: `0.5px solid ${active ? C.warm : t.line}`,
      borderRadius: 9, padding: "10px 11px",
      display: "flex", flexDirection: "column", gap: 7,
      boxShadow: active ? `0 0 0 1px ${C.warm}33, 0 1px 2px rgba(0,0,0,0.04)` : "0 0 0 0.5px rgba(0,0,0,0.02)",
      transition: "all 140ms ease",
    }}
    onMouseEnter={(e) => { if (!active) e.currentTarget.style.transform = "translateY(-1px)"; }}
    onMouseLeave={(e) => { e.currentTarget.style.transform = "none"; }}>
      {/* row 1: flag · name · check */}
      <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <span style={{ fontSize: 14, lineHeight: 1 }}>{n.flag}</span>
        <span style={{ fontSize: 12, color: t.text, fontWeight: active ? 600 : 500, flex: 1, minWidth: 0,
          overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{n.name}</span>
        {active && <span style={{ width: 14, height: 14, borderRadius: "50%", background: C.warm,
          display: "inline-flex", alignItems: "center", justifyContent: "center", color: "#fff", fontSize: 9, fontWeight: 700 }}>✓</span>}
      </div>
      {/* row 2: protocol · latency */}
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <span style={{ fontSize: 9.5, color: t.faint, padding: "1px 5px", borderRadius: 3,
          background: t.fill, fontFamily: "ui-monospace, SF Mono, Menlo", fontWeight: 600, letterSpacing: 0.2 }}>
          {n.proto}
        </span>
        <span style={{ flex: 1 }}/>
        {n.testing
          ? <span style={{ fontSize: 10.5, color: C.amber, fontWeight: 600, fontVariantNumeric: "tabular-nums",
              display: "inline-flex", alignItems: "center", gap: 4 }}>
              <span className="ch-spin" style={{ width: 8, height: 8, borderRadius: "50%",
                border: `1.5px solid ${C.amber}33`, borderTopColor: C.amber }}/>
              testing…
            </span>
          : <span style={{ fontSize: 10.5, color: pc, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>
              {n.ping === 0 ? "—" : `${n.ping} ms`}
            </span>}
      </div>
      {/* row 3: latency bar */}
      <div style={{ height: 3, borderRadius: 2, background: t.fill, overflow: "hidden" }}>
        <div style={{ height: "100%", width: n.testing ? "100%" : `${pct}%`,
          background: n.testing ? `linear-gradient(90deg, ${C.amber}00, ${C.amber}, ${C.amber}00)` : pc,
          opacity: n.ping === 0 ? 0 : 1,
          transition: "width 280ms ease, background 200ms ease",
          animation: n.testing ? "ch-shimmer 1.1s linear infinite" : "none",
          backgroundSize: n.testing ? "200% 100%" : "auto",
        }}/>
      </div>
    </button>
  );
};

const NodeRow = ({ t, n, active, onClick }) => {
  const pc = pingColor(n.ping, t);
  return (
    <button onClick={onClick} style={{
      width: "100%", textAlign: "left", cursor: "pointer", background: active ? `${C.warm}10` : "transparent",
      border: 0, borderRadius: 7,
      display: "grid", gridTemplateColumns: "16px 18px 1fr 90px 70px 70px",
      alignItems: "center", gap: 10, padding: "7px 10px",
    }}
    onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = t.fill; }}
    onMouseLeave={(e) => { e.currentTarget.style.background = active ? `${C.warm}10` : "transparent"; }}>
      <span style={{
        width: 13, height: 13, borderRadius: "50%",
        border: `1.4px solid ${active ? C.warm : t.line}`,
        background: active ? C.warm : "transparent",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}>{active && <span style={{ width: 4, height: 4, background: "#fff", borderRadius: "50%" }}/>}</span>
      <span style={{ fontSize: 14 }}>{n.flag}</span>
      <span style={{ fontSize: 12.5, color: t.text, fontWeight: active ? 600 : 500,
        overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{n.name}</span>
      <span style={{ fontSize: 10.5, color: t.faint, fontFamily: "ui-monospace, SF Mono, Menlo" }}>{n.proto}</span>
      <span style={{ fontSize: 10.5, color: t.dim }}>{n.lastTested}</span>
      <span style={{ fontSize: 11.5, color: pc, fontWeight: 700, fontVariantNumeric: "tabular-nums", textAlign: "right" }}>
        {n.testing ? "…" : n.ping === 0 ? "—" : `${n.ping} ms`}
      </span>
    </button>
  );
};

const ProxiesScreen = ({ t, dark }) => {
  const [groups, setGroups] = useState(initGroups);
  const [open, setOpen] = useState({ ai: true, social: true, streaming: false, google: false, china: false, manual: false });
  const [view, setView] = useState("grid"); // grid | list
  const [sort, setSort] = useState("latency"); // latency | name | default
  const [query, setQuery] = useState("");

  const select = (gid, nid) => setGroups(gs => gs.map(g => g.id === gid ? { ...g, selected: nid } : g));

  const testGroup = useCallback((gid) => {
    setGroups(gs => gs.map(g => g.id === gid
      ? { ...g, nodes: g.nodes.map(n => ({ ...n, testing: true })) } : g));
    // stagger results
    const targets = groups.find(g => g.id === gid)?.nodes || [];
    targets.forEach((n, i) => {
      setTimeout(() => {
        setGroups(gs => gs.map(g => g.id !== gid ? g : {
          ...g, nodes: g.nodes.map(x => x.id !== n.id ? x : {
            ...x, testing: false,
            ping: x.ping === 0 ? 0 : Math.max(20, Math.round(x.ping * (0.6 + Math.random() * 0.9))),
            lastTested: "just now",
          }),
        }));
      }, 350 + i * 180 + Math.random() * 200);
    });
  }, [groups]);

  const testAll = () => groups.forEach(g => testGroup(g.id));

  const sortNodes = (nodes) => {
    const arr = [...nodes];
    if (sort === "latency") arr.sort((a, b) => (a.ping || 9999) - (b.ping || 9999));
    else if (sort === "name") arr.sort((a, b) => a.name.localeCompare(b.name));
    return arr;
  };
  const filterNodes = (nodes) => query
    ? nodes.filter(n => (n.name + n.proto + n.region).toLowerCase().includes(query.toLowerCase()))
    : nodes;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", minHeight: 0 }}>
      {/* sticky toolbar */}
      <div style={{
        position: "sticky", top: 0, zIndex: 2,
        padding: "12px 18px", display: "flex", alignItems: "center", gap: 10,
        background: t.bg, borderBottom: `0.5px solid ${t.line}`,
      }}>
        {/* search */}
        <div style={{
          display: "inline-flex", alignItems: "center", gap: 6,
          height: 28, padding: "0 10px", borderRadius: 8,
          background: t.fill, border: `0.5px solid ${t.line}`, width: 220,
        }}>
          <Ic.search size={12} c={t.faint}/>
          <input value={query} onChange={(e) => setQuery(e.target.value)}
            placeholder="Search nodes…"
            style={{ border: 0, background: "transparent", outline: "none",
              fontSize: 12, color: t.text, flex: 1, fontFamily: "inherit" }}/>
          {query && <button onClick={() => setQuery("")} style={{
            border: 0, background: "transparent", color: t.faint, cursor: "pointer",
            fontSize: 14, lineHeight: 1, padding: 0,
          }}>×</button>}
        </div>

        {/* sort */}
        <Seg t={t} value={sort} onChange={setSort} options={[
          { value: "latency", label: "Latency" },
          { value: "name", label: "Name" },
          { value: "default", label: "Default" },
        ]}/>

        <div style={{ flex: 1 }}/>

        {/* view toggle */}
        <div style={{
          display: "inline-flex", padding: 2, borderRadius: 8,
          background: t.fill, border: `0.5px solid ${t.line}`,
        }}>
          <button onClick={() => setView("grid")} style={{
            width: 26, height: 24, border: 0, borderRadius: 6, cursor: "pointer",
            background: view === "grid" ? t.pillBg : "transparent",
            color: view === "grid" ? t.text : t.dim,
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            boxShadow: view === "grid" ? "0 0 0 0.5px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)" : "none",
          }}><Ic.grid size={11}/></button>
          <button onClick={() => setView("list")} style={{
            width: 26, height: 24, border: 0, borderRadius: 6, cursor: "pointer",
            background: view === "list" ? t.pillBg : "transparent",
            color: view === "list" ? t.text : t.dim,
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            boxShadow: view === "list" ? "0 0 0 0.5px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)" : "none",
          }}><Ic.list size={11}/></button>
        </div>

        {/* test all */}
        <button onClick={testAll} style={{
          height: 28, padding: "0 12px", border: 0, borderRadius: 8, cursor: "pointer",
          background: C.warm, color: "#fff", fontSize: 12, fontWeight: 600,
          display: "inline-flex", alignItems: "center", gap: 6,
          boxShadow: `0 1px 2px ${C.warm}55`,
        }}><Ic.spark size={12}/>Test all</button>
      </div>

      {/* groups */}
      <div style={{ flex: 1, overflowY: "auto", padding: "14px 18px",
        display: "flex", flexDirection: "column", gap: 12 }}
        className={"sc" + (dark ? " dk" : "")}>
        {groups.map(g => {
          const isOpen = open[g.id];
          const sel = g.nodes.find(n => n.id === g.selected);
          const visible = filterNodes(sortNodes(g.nodes));
          const minPing = Math.min(...g.nodes.filter(n => n.ping > 0).map(n => n.ping));
          const anyTesting = g.nodes.some(n => n.testing);
          if (query && visible.length === 0) return null;
          return (
            <Card key={g.id} t={t} padding={0}>
              {/* group header */}
              <div style={{
                display: "flex", alignItems: "center", gap: 12, padding: "11px 14px",
                borderBottom: isOpen ? `0.5px solid ${t.lineSoft}` : "none",
              }}>
                <button onClick={() => setOpen(o => ({ ...o, [g.id]: !o[g.id] }))} style={{
                  width: 22, height: 22, border: 0, borderRadius: 5, cursor: "pointer",
                  background: "transparent", color: t.faint,
                  display: "inline-flex", alignItems: "center", justifyContent: "center",
                  transform: isOpen ? "rotate(90deg)" : "none", transition: "transform 150ms ease",
                }}><Ic.chevR size={11}/></button>

                <span style={{ fontSize: 17, lineHeight: 1 }}>{g.emoji}</span>

                <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 13, fontWeight: 600, color: t.text }}>{g.name}</span>
                    <span style={{ fontSize: 10, color: t.faint, padding: "1px 5px", borderRadius: 3,
                      background: t.fill, fontFamily: "ui-monospace, SF Mono, Menlo", fontWeight: 600 }}>{g.type}</span>
                    <span style={{ fontSize: 10.5, color: t.faint }}>{g.nodes.length} nodes</span>
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, color: t.dim }}>
                    <span>Selected:</span>
                    <span style={{ fontSize: 12 }}>{sel?.flag}</span>
                    <span style={{ color: t.text, fontWeight: 500 }}>{sel?.name}</span>
                    {sel?.ping > 0 && <>
                      <span style={{ color: t.faint }}>·</span>
                      <span style={{ color: pingColor(sel.ping, t), fontWeight: 600,
                        fontVariantNumeric: "tabular-nums" }}>{sel.ping} ms</span>
                    </>}
                  </div>
                </div>

                <div style={{ flex: 1 }}/>

                {/* fastest pill */}
                {minPing > 0 && minPing < 9999 && (
                  <span style={{ fontSize: 10.5, color: pingColor(minPing, t), fontWeight: 600,
                    background: `${pingColor(minPing, t)}14`, padding: "3px 8px", borderRadius: 5,
                    fontVariantNumeric: "tabular-nums",
                    display: "inline-flex", alignItems: "center", gap: 5,
                  }}>
                    <Dot c={pingColor(minPing, t)} size={5}/>
                    fastest {minPing} ms
                  </span>
                )}

                {/* test group */}
                <button onClick={(e) => { e.stopPropagation(); testGroup(g.id); }}
                  disabled={anyTesting}
                  style={{
                    height: 26, padding: "0 10px", border: 0, borderRadius: 6, cursor: anyTesting ? "default" : "pointer",
                    background: t.fill, color: t.text, fontSize: 11, fontWeight: 500,
                    display: "inline-flex", alignItems: "center", gap: 5,
                    border: `0.5px solid ${t.line}`,
                    opacity: anyTesting ? 0.6 : 1,
                  }}>
                  <span className={anyTesting ? "ch-spin" : ""} style={{
                    display: "inline-flex",
                  }}><Ic.refresh size={11}/></span>
                  {anyTesting ? "Testing" : "Test"}
                </button>
              </div>

              {/* nodes */}
              {isOpen && (
                <div style={{ padding: view === "grid" ? 10 : 6 }}>
                  {visible.length === 0 && (
                    <div style={{ padding: "16px 8px", fontSize: 11.5, color: t.faint, textAlign: "center" }}>
                      No nodes match "{query}"
                    </div>
                  )}
                  {view === "grid" ? (
                    <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 8 }}>
                      {visible.map(n => (
                        <NodeCard key={n.id} t={t} n={n}
                          active={n.id === g.selected}
                          onClick={() => select(g.id, n.id)}/>
                      ))}
                    </div>
                  ) : (
                    <div style={{ display: "flex", flexDirection: "column", gap: 1 }}>
                      <div style={{
                        display: "grid", gridTemplateColumns: "16px 18px 1fr 90px 70px 70px",
                        gap: 10, padding: "4px 10px",
                        fontSize: 9.5, fontWeight: 600, color: t.faint, letterSpacing: 0.4, textTransform: "uppercase",
                      }}>
                        <span/><span/><span>Name</span><span>Protocol</span><span>Tested</span>
                        <span style={{ textAlign: "right" }}>Latency</span>
                      </div>
                      {visible.map(n => (
                        <NodeRow key={n.id} t={t} n={n}
                          active={n.id === g.selected}
                          onClick={() => select(g.id, n.id)}/>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
};

// ── Rules screen ─────────────────────────────────────────────────────
const RulesScreen = ({ t, dark }) => {
  const tColor = (type) => ({
    "DOMAIN-SUFFIX": C.blue, "DOMAIN-KEYWORD": C.purple, "GEOIP": C.pink,
    "IP-CIDR": C.amber, "PROCESS-NAME": C.red, "MATCH": t.faint,
  })[type] || t.faint;
  return (
    <div style={{ padding: "16px 18px" }}>
      <Card t={t} padding={0}>
        <div style={{
          display: "grid", gridTemplateColumns: "32px 130px 1fr 130px 70px",
          padding: "10px 16px", gap: 10,
          borderBottom: `0.5px solid ${t.line}`,
          fontSize: 10, fontWeight: 600, color: t.faint, textTransform: "uppercase", letterSpacing: 0.4,
        }}>
          <span>#</span><span>Type</span><span>Match</span><span>Action</span><span style={{ textAlign: "right" }}>Hits</span>
        </div>
        {RULES.map((r, i) => (
          <div key={i} style={{
            display: "grid", gridTemplateColumns: "32px 130px 1fr 130px 70px",
            padding: "8px 16px", gap: 10, alignItems: "center",
            borderTop: i ? `0.5px solid ${t.lineSoft}` : "none", fontSize: 12,
          }}>
            <span style={{ color: t.faint, fontVariantNumeric: "tabular-nums" }}>{i+1}</span>
            <span style={{ fontSize: 10.5, fontWeight: 700, color: tColor(r.type), fontFamily: "ui-monospace, SF Mono, Menlo" }}>{r.type}</span>
            <span className="ch-mask" style={{ color: t.text, fontFamily: "ui-monospace, SF Mono, Menlo", fontSize: 11.5 }}>{r.match}</span>
            <span style={{ color: t.text, fontWeight: 500 }}>{r.action}</span>
            <span style={{ color: t.dim, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{r.hits.toLocaleString()}</span>
          </div>
        ))}
      </Card>
    </div>
  );
};

// ── Connections (live) ───────────────────────────────────────────────
const HOSTS = ["api.openai.com:443", "anthropic.com:443", "claude.ai:443", "github.com:443",
  "raw.githubusercontent.com:443", "youtube.com:443", "i.ytimg.com:443", "fonts.gstatic.com:443",
  "icloud.com:443", "registry-1.docker.io:443", "ghcr.io:443", "objects.githubusercontent.com:443"];
const PROCS = ["Code Helper", "Safari", "Slack", "Spotify", "Music", "iTerm2", "Mail", "Xcode"];

const ConnectionsScreen = ({ t, dark }) => {
  const [conns, setConns] = useState(() => Array.from({length: 12}, makeConn));
  const [paused, setPaused] = useState(false);
  useEffect(() => {
    if (paused) return;
    const id = setInterval(() => {
      setConns(prev => {
        const next = [...prev];
        if (Math.random() < 0.6 && next.length < 30) next.unshift(makeConn());
        return next.map(c => ({ ...c,
          dn: c.live ? c.dn + Math.floor(Math.random() * 60000) : c.dn,
          up: c.live ? c.up + Math.floor(Math.random() * 5000) : c.up,
          dur: c.live ? c.dur + 1 : c.dur,
          live: c.live && Math.random() > 0.05,
        })).slice(0, 30);
      });
    }, 800);
    return () => clearInterval(id);
  }, [paused]);

  return (
    <div style={{ padding: "16px 18px", display: "flex", flexDirection: "column", gap: 10, height: "100%" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ fontSize: 11, color: t.dim }}>{conns.filter(c => c.live).length} active · {conns.length} total</span>
        <div style={{ flex: 1 }}/>
        <button onClick={() => setPaused(p => !p)} style={{ ...btnGhost(t), width: 28, height: 28 }}>
          {paused ? <Ic.play size={11}/> : <Ic.pause size={12}/>}
        </button>
        <button onClick={() => setConns([])} style={{ ...btnGhost(t), width: 28, height: 28 }}><Ic.trash size={12}/></button>
      </div>
      <Card t={t} padding={0} style={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
        <div style={{
          display: "grid", gridTemplateColumns: "12px 1.6fr 1fr 80px 80px 90px",
          padding: "10px 14px", gap: 10,
          borderBottom: `0.5px solid ${t.line}`,
          fontSize: 10, fontWeight: 600, color: t.faint, textTransform: "uppercase", letterSpacing: 0.4,
        }}>
          <span/><span>Host</span><span>Process</span>
          <span style={{ textAlign: "right" }}>Down</span>
          <span style={{ textAlign: "right" }}>Up</span>
          <span>Rule</span>
        </div>
        <div className={"sc" + (dark ? " dk" : "")} style={{ flex: 1, overflowY: "auto" }}>
          {conns.map(c => (
            <div key={c.id} style={{
              display: "grid", gridTemplateColumns: "12px 1.6fr 1fr 80px 80px 90px",
              padding: "7px 14px", gap: 10, alignItems: "center",
              borderTop: `0.5px solid ${t.lineSoft}`, fontSize: 11.5,
            }}>
              <Dot c={c.live ? C.green : t.faint} size={6} pulse={c.live}/>
              <span className="ch-mask" style={{ color: t.text, fontFamily: "ui-monospace, SF Mono, Menlo", fontSize: 11, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.host}</span>
              <span style={{ color: t.dim }}>{c.proc}</span>
              <span style={{ color: t.text, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{fmt(c.dn)}</span>
              <span style={{ color: t.text, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{fmt(c.up)}</span>
              <span style={{ color: c.action === "DIRECT" ? t.dim : C.blue, fontWeight: 500, fontSize: 11 }}>{c.action}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};

let _ci = 0;
function makeConn() {
  const host = HOSTS[Math.floor(Math.random() * HOSTS.length)];
  const proc = PROCS[Math.floor(Math.random() * PROCS.length)];
  const direct = host.includes("apple") || host.includes("icloud") || host.includes("github");
  return { id: ++_ci, host, proc,
    dn: Math.floor(Math.random() * 200000), up: Math.floor(Math.random() * 20000),
    dur: 0, live: true, action: direct ? "DIRECT" : "Auto" };
}
function fmt(b) { if (b < 1024) return `${b} B`; if (b < 1048576) return `${(b/1024).toFixed(1)} KB`; return `${(b/1048576).toFixed(1)} MB`; }

// ── Logs (terminal-ish) ──────────────────────────────────────────────
const LOG_TPL = [
  { lv: "info",  c: C.blue,  msg: "[TCP] api.openai.com:443 matched DOMAIN-SUFFIX → AI" },
  { lv: "info",  c: C.blue,  msg: "[DNS] resolved fonts.gstatic.com → 142.250.71.227" },
  { lv: "info",  c: C.blue,  msg: "[URLTest] TW-1 38ms · JP-1 56ms · best=TW-1" },
  { lv: "warn",  c: C.amber, msg: "[Proxy] DE-Server timeout, retrying" },
  { lv: "info",  c: C.blue,  msg: "[Cfg] subscription 'main' refreshed, 24 nodes" },
  { lv: "error", c: C.red,   msg: "[Conn] handshake failed: tls: certificate expired" },
  { lv: "info",  c: C.blue,  msg: "[Match] rule no.6 hit: GEOIP CN → DIRECT" },
];
const LogsScreen = ({ t, dark }) => {
  const [logs, setLogs] = useState(() => Array.from({length: 18}, mkLog));
  const ref = useRef(null);
  useEffect(() => {
    const id = setInterval(() => setLogs(p => [...p.slice(-200), mkLog()]), 1100);
    return () => clearInterval(id);
  }, []);
  useEffect(() => { if (ref.current) ref.current.scrollTop = ref.current.scrollHeight; }, [logs.length]);
  return (
    <div style={{ padding: "16px 18px", height: "100%" }}>
      <Card t={t} padding={0} style={{ height: "100%", display: "flex", flexDirection: "column" }}>
        <div ref={ref} className={"sc" + (dark ? " dk" : "")}
          style={{ flex: 1, overflowY: "auto", padding: 14,
            fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
            fontSize: 11, lineHeight: 1.7, background: t.cardSoft }}>
          {logs.map((l, i) => (
            <div key={i} style={{ display: "flex", gap: 10 }}>
              <span style={{ color: t.faint }}>{l.t}</span>
              <span style={{ color: l.c, width: 44, fontWeight: 700, textTransform: "uppercase" }}>{l.lv}</span>
              <span style={{ color: t.text }}>{l.msg}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};
let _li = 0;
function mkLog() {
  const tpl = LOG_TPL[Math.floor(Math.random() * LOG_TPL.length)];
  const d = new Date();
  const t = `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}:${String(d.getSeconds()).padStart(2,"0")}`;
  return { ...tpl, t, id: ++_li };
}

// ── Advanced screen ──────────────────────────────────────────────────
const AdvSection = ({ t, title, children }) => (
  <div style={{ marginBottom: 22 }}>
    <div className="serif" style={{
      fontSize: 13, fontWeight: 500, color: t.dim,
      padding: "0 4px 8px", letterSpacing: -0.05,
    }}>{title}</div>
    <div style={{
      background: t.card, borderRadius: 12,
      border: `0.5px solid ${t.line}`, overflow: "hidden",
      boxShadow: "0 0 0 0.5px rgba(14,42,42,0.02), 0 1px 2px rgba(14,42,42,0.03)",
    }}>{children}</div>
  </div>
);

const AdvRow = ({ t, icon: Ico, iconColor = C.patina, label, sub, children, last }) => (
  <div style={{
    display: "flex", alignItems: "center", gap: 12, padding: "11px 14px",
    borderBottom: last ? "none" : `0.5px solid ${t.lineSoft}`,
    minHeight: 44,
  }}>
    {Ico && (
      <span style={{
        width: 22, height: 22, borderRadius: 5,
        background: `${iconColor}18`, color: iconColor,
        display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
      }}><Ico size={12}/></span>
    )}
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 12.5, fontWeight: 500, color: t.text }}>{label}</div>
      {sub && <div style={{ fontSize: 10.5, color: t.faint, marginTop: 1 }}>{sub}</div>}
    </div>
    <div style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>{children}</div>
  </div>
);

const Switch = ({ on, onChange, color = C.patina }) => (
  <button onClick={() => onChange(!on)} style={{
    width: 36, height: 20, borderRadius: 10, border: 0, cursor: "pointer", padding: 0,
    background: on ? color : "rgba(14,42,42,0.18)",
    boxShadow: on ? `inset 0 0 0 0.5px ${color}` : "inset 0 0 0 0.5px rgba(14,42,42,0.10)",
    position: "relative", transition: "background 160ms ease",
  }}>
    <span style={{
      position: "absolute", top: 2, left: on ? 18 : 2,
      width: 16, height: 16, borderRadius: "50%", background: "#fff",
      boxShadow: "0 1px 2px rgba(0,0,0,0.20), 0 0 0 0.5px rgba(0,0,0,0.06)",
      transition: "left 160ms ease",
    }}/>
  </button>
);

const Stepper = ({ t, value, options, onChange }) => (
  <button onClick={() => {
    const i = options.findIndex(o => o.value === value);
    onChange(options[(i + 1) % options.length].value);
  }} style={{
    height: 24, padding: "0 8px 0 10px", borderRadius: 6,
    background: t.fill, border: `0.5px solid ${t.line}`, color: t.text,
    fontSize: 11.5, fontWeight: 500, cursor: "pointer",
    display: "inline-flex", alignItems: "center", gap: 6,
  }}>
    {options.find(o => o.value === value)?.label}
    <Ic.chevUD size={10} c={t.faint}/>
  </button>
);

const TextInput = ({ t, value, onChange, placeholder, mono, width = 180, type = "text", trailing }) => (
  <div style={{
    display: "inline-flex", alignItems: "center", gap: 4,
    height: 24, padding: "0 8px", borderRadius: 6,
    background: t.fill, border: `0.5px solid ${t.line}`, width,
  }}>
    <input type={type} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder}
      style={{
        border: 0, background: "transparent", outline: "none",
        fontSize: 11.5, color: t.text, flex: 1, minWidth: 0,
        fontFamily: mono ? "ui-monospace, SF Mono, Menlo" : "inherit",
      }}/>
    {trailing}
  </div>
);

const IpChip = ({ t, ip, tag, tagColor, onDelete }) => (
  <div style={{
    display: "flex", alignItems: "center", gap: 10, padding: "9px 12px",
    borderTop: `0.5px solid ${t.lineSoft}`,
  }}>
    <span style={{
      width: 22, height: 22, borderRadius: 5,
      background: `${tagColor}20`, color: tagColor,
      display: "inline-flex", alignItems: "center", justifyContent: "center",
    }}><Ic.shield size={11}/></span>
    <span className="ch-mask" style={{
      fontSize: 11.5, color: t.text,
      fontFamily: "ui-monospace, SF Mono, Menlo", flex: 1,
    }}>{ip}</span>
    {tag && (
      <span style={{
        fontSize: 10, fontWeight: 600, color: tagColor,
        padding: "2px 7px", borderRadius: 4, background: `${tagColor}18`,
      }}>{tag}</span>
    )}
    <button onClick={onDelete} style={{
      width: 20, height: 20, border: 0, borderRadius: 4, cursor: "pointer",
      background: "transparent", color: t.faint,
      display: "inline-flex", alignItems: "center", justifyContent: "center",
    }}>
      <span style={{ fontSize: 14, lineHeight: 1 }}>×</span>
    </button>
  </div>
);

const AdvancedScreen = ({ t, dark }) => {
  const [logLevel, setLogLevel] = useState("error");
  const [unifiedDelay, setUnifiedDelay] = useState(true);
  const [tcpConcurrent, setTcpConcurrent] = useState(true);
  const [ipv6, setIpv6] = useState(true);
  const [quic, setQuic] = useState("ext");
  const [lan, setLan] = useState(false);
  const [dnsMode, setDnsMode] = useState("smart");
  const [dnsHijack, setDnsHijack] = useState(true);
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const [showPass, setShowPass] = useState(false);
  const [bypass, setBypass] = useState([
    { ip: "127.0.0.0/8",     tag: "Default",   tagColor: C.patina, locked: true },
    { ip: "172.16.0.0/12",   tag: "Default",   tagColor: C.patina, locked: true },
    { ip: "10.0.0.0/8",      tag: "Default",   tagColor: C.patina, locked: true },
    { ip: "192.168.0.0/16",  tag: "Default",   tagColor: C.patina, locked: true },
    { ip: "fd00::/8",        tag: "Custom",    tagColor: C.brass,  locked: false },
    { ip: "100.64.0.0/10",   tag: "Tailscale", tagColor: C.brass,  locked: false },
  ]);
  const [newIp, setNewIp] = useState("");

  const addIp = () => {
    if (!newIp.trim()) return;
    setBypass(b => [...b, { ip: newIp.trim(), tag: "Custom", tagColor: C.brass, locked: false }]);
    setNewIp("");
  };

  return (
    <div style={{ padding: "20px 24px" }}>

      {/* Kernel logs */}
      <AdvSection t={t} title="Kernel logs">
        <AdvRow t={t} icon={Ic.list} iconColor={C.brass} label="Log level"
          sub="Verbose output is written to ~/Library/Logs/ChungHwa">
          <Stepper t={t} value={logLevel} onChange={setLogLevel} options={[
            { value: "silent", label: "Silent" },
            { value: "error",  label: "Error" },
            { value: "warn",   label: "Warning" },
            { value: "info",   label: "Info" },
            { value: "debug",  label: "Debug" },
          ]}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.doc} iconColor={C.patina} label="View kernel log" last>
          <button style={{
            width: 24, height: 24, border: 0, borderRadius: 5, cursor: "pointer",
            background: "transparent", color: t.dim,
            display: "inline-flex", alignItems: "center", justifyContent: "center",
          }}><Ic.outbound size={12}/></button>
        </AdvRow>
      </AdvSection>

      {/* Connection optimization */}
      <AdvSection t={t} title="Connection optimization">
        <AdvRow t={t} icon={Ic.refresh} iconColor={C.patina}
          label="Unified delay test"
          sub="Requires kernel restart">
          <Switch on={unifiedDelay} onChange={setUnifiedDelay}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.link} iconColor={C.brass}
          label="TCP concurrent connections"
          sub="Open multiple TCP streams to the chosen node">
          <Switch on={tcpConcurrent} onChange={setTcpConcurrent}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.globe} iconColor={C.patina}
          label="IPv6 support">
          <Switch on={ipv6} onChange={setIpv6}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.cube} iconColor={C.brass}
          label="Disable QUIC"
          sub="Some networks throttle QUIC; falling back to TCP improves stability"
          last>
          <Stepper t={t} value={quic} onChange={setQuic} options={[
            { value: "off",  label: "Never" },
            { value: "ext",  label: "Outside LAN only" },
            { value: "all",  label: "Always" },
          ]}/>
        </AdvRow>
      </AdvSection>

      {/* DNS */}
      <AdvSection t={t} title="DNS">
        <AdvRow t={t} icon={Ic.swap} iconColor={C.patina}
          label="Resolution mode"
          sub="Smart routes domestic to system, foreign to fake-ip">
          <Stepper t={t} value={dnsMode} onChange={setDnsMode} options={[
            { value: "system",  label: "System" },
            { value: "smart",   label: "Smart" },
            { value: "fake-ip", label: "Fake-IP" },
          ]}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.shield} iconColor={C.brass}
          label="Hijack port 53"
          sub="Capture all DNS traffic on the system">
          <Switch on={dnsHijack} onChange={setDnsHijack}/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.web} iconColor={C.patina}
          label="Upstream resolvers"
          sub="One per line; supports DoH, DoT, DoQ"
          last>
          <span style={{ fontSize: 11, color: t.dim, fontFamily: "ui-monospace, SF Mono, Menlo" }}>4 active</span>
          <button style={{
            width: 24, height: 24, border: 0, borderRadius: 5, cursor: "pointer",
            background: "transparent", color: t.dim,
            display: "inline-flex", alignItems: "center", justifyContent: "center",
          }}><Ic.chevR size={12}/></button>
        </AdvRow>
      </AdvSection>

      {/* LAN access */}
      <AdvSection t={t} title="LAN inbound">
        <AdvRow t={t} icon={Ic.web} iconColor={lan ? C.brass : C.patina}
          label="Allow connections from local network"
          sub={lan ? "Other devices can use this Mac as a gateway" : "Only this Mac can connect to the proxy"}
          last>
          <Switch on={lan} onChange={setLan}/>
        </AdvRow>
      </AdvSection>

      {/* Proxy auth */}
      <AdvSection t={t} title="Proxy authentication">
        <AdvRow t={t} icon={Ic.shield} iconColor={C.patina} label="Username">
          <TextInput t={t} value={user} onChange={setUser} placeholder="optional"/>
        </AdvRow>
        <AdvRow t={t} icon={Ic.shield} iconColor={C.brass} label="Password">
          <TextInput t={t} value={pass} onChange={setPass} placeholder="optional"
            type={showPass ? "text" : "password"} mono
            trailing={
              <button onClick={() => setShowPass(s => !s)} style={{
                width: 18, height: 18, border: 0, background: "transparent",
                color: t.faint, cursor: "pointer", display: "inline-flex",
                alignItems: "center", justifyContent: "center",
              }}>{showPass ? <Ic.eyeOff size={11}/> : <Ic.eye size={11}/>}</button>
            }/>
        </AdvRow>
        <div style={{
          padding: "8px 14px 12px", fontSize: 10.5, color: t.faint,
          borderTop: `0.5px solid ${t.lineSoft}`,
        }}>
          Local connections (<span style={{ fontFamily: "ui-monospace, SF Mono, Menlo" }}>127.0.0.0/8</span>) bypass authentication by default.
        </div>
      </AdvSection>

      {/* Bypass list */}
      <AdvSection t={t} title="IP ranges that bypass authentication">
        <div style={{ padding: "10px 12px", display: "flex", alignItems: "center", gap: 8 }}>
          <TextInput t={t} value={newIp} onChange={setNewIp}
            placeholder="e.g. 198.18.0.0/16" mono width={"100%"}/>
          <button onClick={addIp} style={{
            height: 24, padding: "0 12px", borderRadius: 6, border: 0, cursor: "pointer",
            background: C.brass, color: "#fff", fontSize: 11, fontWeight: 600,
            display: "inline-flex", alignItems: "center", gap: 4,
          }}><Ic.plus size={11}/>Add</button>
        </div>
        {bypass.map((b, i) => (
          <IpChip key={i} t={t} ip={b.ip} tag={b.tag} tagColor={b.tagColor}
            onDelete={() => !b.locked && setBypass(arr => arr.filter((_, j) => j !== i))}/>
        ))}
      </AdvSection>

      <div style={{ height: 40 }}/>
    </div>
  );
};

// ── Stub screens ─────────────────────────────────────────────────────
const StubScreen = ({ t, title, sub }) => (
  <div style={{ padding: "16px 18px" }}>
    <Card t={t}>
      <div style={{ padding: "40px 20px", textAlign: "center" }}>
        <div className="serif" style={{ fontSize: 22, fontWeight: 500, color: t.text, marginBottom: 6, letterSpacing: -0.3 }}>{title}</div>
        <div style={{ fontSize: 12, color: t.dim }}>{sub}</div>
      </div>
    </Card>
  </div>
);

// ── App ──────────────────────────────────────────────────────────────
function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const dark = !!tweaks.dark;
  const t = T(dark);
  const [screen, setScreen] = useState("overview");
  const [collapsed, setCollapsed] = useState(false);

  const [traffic, setTraffic] = useState({
    up: Array(60).fill(0).map(() => 4000 + Math.random() * 12000),
    down: Array(60).fill(0).map(() => 8000 + Math.random() * 18000),
  });
  useEffect(() => {
    const id = setInterval(() => setTraffic(prev => ({
      up: [...prev.up.slice(1), Math.max(2000, (prev.up.at(-1) || 8000) + (Math.random() - 0.5) * 6000)],
      down: [...prev.down.slice(1), Math.max(4000, (prev.down.at(-1) || 14000) + (Math.random() - 0.5) * 9000)],
    })), 700);
    return () => clearInterval(id);
  }, []);

  const titles = {
    overview: "ChungHwa Dashboard", traffic: "Traffic Stats", connections: "Connections", logs: "Logs",
    topology: "Topology", routemap: "Route Map",
    proxies: "Proxies", rules: "Rules", providers: "Providers",
    profiles: "Profiles", advanced: "Advanced",
  };

  const screenEl = (() => {
    switch (screen) {
      case "overview":    return <Overview t={t} dark={dark} traffic={traffic}/>;
      case "proxies":     return <ProxiesScreen t={t} dark={dark}/>;
      case "rules":       return <RulesScreen t={t} dark={dark}/>;
      case "connections": return <ConnectionsScreen t={t} dark={dark}/>;
      case "logs":        return <LogsScreen t={t} dark={dark}/>;
      case "traffic":     return <StubScreen t={t} title="Traffic Stats" sub="Detailed bandwidth, by hour, day, and month."/>;
      case "topology":    return <StubScreen t={t} title="Topology" sub="Visual proxy chain map."/>;
      case "routemap":    return <StubScreen t={t} title="Route Map" sub="Live geographic view of active connections."/>;
      case "providers":   return <StubScreen t={t} title="Providers" sub="Subscription sources and their nodes."/>;
      case "profiles":    return <StubScreen t={t} title="Profiles" sub="Active configuration files."/>;
      case "advanced":    return <AdvancedScreen t={t} dark={dark}/>;
    }
  })();

  return (
    <div style={{ position: "fixed", inset: 0, background: t.desk, padding: 28, boxSizing: "border-box" }}>
      <div style={{
        width: "100%", height: "100%", borderRadius: 14, overflow: "hidden",
        background: t.bg, display: "flex",
        boxShadow: "0 0 0 0.5px rgba(0,0,0,0.18), 0 30px 80px rgba(40,28,12,0.18), 0 8px 24px rgba(40,28,12,0.10)",
      }}>
        <Sidebar t={t} dark={dark} screen={screen} setScreen={setScreen} collapsed={collapsed} setCollapsed={setCollapsed}/>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
          <Toolbar t={t} dark={dark} title={titles[screen]}
            mode={tweaks.outboundMode} setMode={(v) => setTweak("outboundMode", v)}
            profile={tweaks.profile} setProfile={(v) => setTweak("profile", v)}
            collapsed={collapsed} setCollapsed={setCollapsed}
            sysProxy={!!tweaks.sysProxy} setSysProxy={(v) => setTweak("sysProxy", v)}
            tunMode={!!tweaks.tunMode}   setTunMode={(v) => setTweak("tunMode", v)}
            anon={!!tweaks.anon}         setAnon={(v) => setTweak("anon", v)}/>
      <div className={"sc ch-content" + (dark ? " dk" : "") + (tweaks.anon ? " ch-anon" : "")}
        style={{ flex: 1, overflowY: "auto", color: t.text }}>
            {tweaks.anon && (
              <div style={{
                padding: "8px 18px", display: "flex", alignItems: "center", gap: 8,
                background: `${C.brass}20`, borderBottom: `0.5px solid ${C.brass}55`,
                fontSize: 11.5, color: t.text,
              }}>
                <Ic.eyeOff size={12} c={C.brassDk}/>
                <span style={{ fontWeight: 600 }}>Anonymous mode</span>
                <span style={{ color: t.dim }}>· identifying information is masked. Hover any blurred field to reveal briefly.</span>
              </div>
            )}
            {screenEl}
          </div>
        </div>
      </div>

      <TweaksPanel title="Tweaks">
        <TweakToggle label="Dark mode" value={dark} onChange={(v) => setTweak("dark", v)}/>
        <TweakRadio label="Outbound" value={tweaks.outboundMode} onChange={(v) => setTweak("outboundMode", v)}
          options={[{ value: "Direct", label: "Direct" }, { value: "Rule", label: "Rule" }, { value: "Global", label: "Global" }]}/>
        <TweakSelect label="Profile" value={tweaks.profile} onChange={(v) => setTweak("profile", v)}
          options={["Backup", "Main", "Dev"]}/>
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App/>);
