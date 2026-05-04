// Static seed data for ChungHwa
// Original; not based on any specific product.

const PROXY_GROUPS = [
  {
    id: "auto",
    name: "Auto Select",
    type: "url-test",
    selected: "TPE-01",
    nodes: [
      { id: "TPE-01", name: "Taipei 01",   region: "TW", flag: "🇹🇼", proto: "Trojan",     ping: 38,  load: 12 },
      { id: "TPE-02", name: "Taipei 02",   region: "TW", flag: "🇹🇼", proto: "Trojan",     ping: 42,  load: 23 },
      { id: "TYO-01", name: "Tokyo 01",    region: "JP", flag: "🇯🇵", proto: "Hysteria2",  ping: 56,  load: 45 },
      { id: "TYO-02", name: "Tokyo 02",    region: "JP", flag: "🇯🇵", proto: "VLESS",      ping: 62,  load: 31 },
      { id: "SGP-01", name: "Singapore",   region: "SG", flag: "🇸🇬", proto: "VLESS",      ping: 88,  load: 18 },
      { id: "LAX-01", name: "Los Angeles", region: "US", flag: "🇺🇸", proto: "Trojan",     ping: 142, load: 64 },
      { id: "FRA-01", name: "Frankfurt",   region: "DE", flag: "🇩🇪", proto: "VLESS",      ping: 218, load: 7 },
      { id: "LON-01", name: "London",      region: "GB", flag: "🇬🇧", proto: "Hysteria2",  ping: 244, load: 11 },
    ],
  },
  {
    id: "streaming",
    name: "Streaming",
    type: "select",
    selected: "LAX-01",
    nodes: [
      { id: "LAX-01", name: "Los Angeles ⓜ", region: "US", flag: "🇺🇸", proto: "Trojan",  ping: 142, load: 64 },
      { id: "NYC-01", name: "New York",      region: "US", flag: "🇺🇸", proto: "VLESS",   ping: 168, load: 22 },
      { id: "TYO-02", name: "Tokyo 02",      region: "JP", flag: "🇯🇵", proto: "VLESS",   ping: 62,  load: 31 },
    ],
  },
  {
    id: "fallback",
    name: "Fallback",
    type: "fallback",
    selected: "TPE-01",
    nodes: [
      { id: "TPE-01", name: "Taipei 01", region: "TW", flag: "🇹🇼", proto: "Trojan", ping: 38,  load: 12 },
      { id: "SGP-01", name: "Singapore", region: "SG", flag: "🇸🇬", proto: "VLESS",  ping: 88,  load: 18 },
    ],
  },
];

const RULES = [
  { type: "DOMAIN-SUFFIX",  match: "github.com",       action: "DIRECT",  hits: 42 },
  { type: "DOMAIN-KEYWORD", match: "google",           action: "Auto Select", hits: 1284 },
  { type: "DOMAIN-SUFFIX",  match: "openai.com",       action: "Streaming", hits: 318 },
  { type: "DOMAIN-SUFFIX",  match: "youtube.com",      action: "Streaming", hits: 962 },
  { type: "GEOIP",          match: "CN",               action: "DIRECT",  hits: 5210 },
  { type: "IP-CIDR",        match: "192.168.0.0/16",   action: "DIRECT",  hits: 88 },
  { type: "DOMAIN-SUFFIX",  match: "apple.com",        action: "DIRECT",  hits: 412 },
  { type: "PROCESS-NAME",   match: "Xcode",            action: "DIRECT",  hits: 14 },
  { type: "DOMAIN-SUFFIX",  match: "icloud.com",       action: "DIRECT",  hits: 633 },
  { type: "DOMAIN-SUFFIX",  match: "anthropic.com",    action: "Auto Select", hits: 187 },
  { type: "MATCH",          match: "—",                action: "Fallback", hits: 73 },
];

const HOSTS = [
  "github.com", "raw.githubusercontent.com", "objects.githubusercontent.com",
  "api.openai.com", "chat.openai.com", "anthropic.com", "claude.ai",
  "youtube.com", "i.ytimg.com", "googlevideo.com",
  "cdn.apple.com", "swcdn.apple.com", "icloud.com",
  "doh.dns.sb", "1.1.1.1", "8.8.8.8",
  "registry-1.docker.io", "ghcr.io",
  "fonts.gstatic.com", "fonts.googleapis.com",
  "telemetry.local", "ntp.aliyun.com",
];

const PROCESSES = ["kernel_task", "Safari", "Code Helper", "Slack", "Spotify", "Xcode", "iTerm2", "Docker", "Music", "Mail"];

const APP_VERSION = "ChungHwa 1.4.0 (build 2026.05)";

window.CH_DATA = { PROXY_GROUPS, RULES, HOSTS, PROCESSES, APP_VERSION };
