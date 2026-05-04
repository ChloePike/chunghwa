// Minimal, SF Symbols-flavored stroke icons. Currentcolor inherits from parent.
// All built from simple primitives — circles, lines, rounded rects.

const Ico = ({ size = 16, stroke = 1.5, children, style = {} }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill="none"
       stroke="currentColor" strokeWidth={stroke}
       strokeLinecap="round" strokeLinejoin="round"
       style={{ display: "block", ...style }}>{children}</svg>
);

const Icons = {
  dashboard: (p) => <Ico {...p}><rect x="2" y="2" width="5" height="5" rx="1.2"/><rect x="9" y="2" width="5" height="5" rx="1.2"/><rect x="2" y="9" width="5" height="5" rx="1.2"/><rect x="9" y="9" width="5" height="5" rx="1.2"/></Ico>,
  globe: (p) => <Ico {...p}><circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12"/></Ico>,
  rules: (p) => <Ico {...p}><path d="M3 4h10M3 8h7M3 12h10"/><circle cx="13" cy="8" r="1.2" fill="currentColor"/></Ico>,
  link: (p) => <Ico {...p}><path d="M6 8a2.5 2.5 0 0 1 2.5-2.5h2.5a2.5 2.5 0 0 1 0 5h-1"/><path d="M10 8a2.5 2.5 0 0 1-2.5 2.5H5a2.5 2.5 0 0 1 0-5h1"/></Ico>,
  log: (p) => <Ico {...p}><path d="M3 3h10v10H3z"/><path d="M5.5 6h5M5.5 8.5h5M5.5 11h3"/></Ico>,
  gear: (p) => <Ico {...p}><circle cx="8" cy="8" r="2"/><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4"/></Ico>,
  bolt: (p) => <Ico {...p}><path d="M9 2L4 9h3.5l-1 5L12 7H8.5L9 2z" fill="currentColor" stroke="none"/></Ico>,
  upload: (p) => <Ico {...p}><path d="M8 13V4M4.5 7.5L8 4l3.5 3.5"/></Ico>,
  download: (p) => <Ico {...p}><path d="M8 3v9M4.5 8.5L8 12l3.5-3.5"/></Ico>,
  search: (p) => <Ico {...p}><circle cx="7" cy="7" r="4"/><path d="M10 10l3.5 3.5"/></Ico>,
  plus: (p) => <Ico {...p}><path d="M8 3v10M3 8h10"/></Ico>,
  minus: (p) => <Ico {...p}><path d="M3 8h10"/></Ico>,
  filter: (p) => <Ico {...p}><path d="M2 3h12l-4.5 5.5V13l-3 1.5V8.5L2 3z"/></Ico>,
  refresh: (p) => <Ico {...p}><path d="M13 7A5 5 0 1 0 13 9"/><path d="M13 3v4h-4"/></Ico>,
  pause: (p) => <Ico {...p}><rect x="4" y="3" width="2.5" height="10" rx="0.5"/><rect x="9.5" y="3" width="2.5" height="10" rx="0.5"/></Ico>,
  play: (p) => <Ico {...p}><path d="M5 3l7 5-7 5V3z" fill="currentColor"/></Ico>,
  trash: (p) => <Ico {...p}><path d="M3 4.5h10M6 4.5V3h4v1.5M5 4.5l.5 9h5l.5-9"/></Ico>,
  copy: (p) => <Ico {...p}><rect x="3" y="3" width="8" height="8" rx="1.2"/><path d="M5.5 13h6a1.5 1.5 0 0 0 1.5-1.5v-6"/></Ico>,
  chevR: (p) => <Ico {...p}><path d="M6 3l5 5-5 5"/></Ico>,
  chevD: (p) => <Ico {...p}><path d="M3 6l5 5 5-5"/></Ico>,
  check: (p) => <Ico {...p}><path d="M3 8l3 3 7-7"/></Ico>,
  shield: (p) => <Ico {...p}><path d="M8 1.5l5.5 2v5c0 3-2.2 5.5-5.5 6-3.3-.5-5.5-3-5.5-6v-5l5.5-2z"/></Ico>,
  bars: (p) => <Ico {...p}><path d="M3 13V8M7 13V5M11 13V3"/></Ico>,
  wifi: (p) => <Ico {...p}><path d="M2 6c3.5-3.5 8.5-3.5 12 0M4 8.5c2.5-2.5 5.5-2.5 8 0M6 11c1.5-1.5 2.5-1.5 4 0"/><circle cx="8" cy="13" r="0.6" fill="currentColor"/></Ico>,
  ssh: (p) => <Ico {...p}><rect x="2" y="3" width="12" height="9" rx="1.5"/><path d="M5 7l2 1.5L5 10M8.5 10h2.5"/></Ico>,
  flag: (p) => <Ico {...p}><path d="M3.5 14V2M3.5 3h8l-1.5 2.5L11.5 8h-8"/></Ico>,
  pin: (p) => <Ico {...p}><path d="M8 1.5v6M5 7.5h6L9.5 10v3.5L8 14.5 6.5 13.5V10L5 7.5z"/></Ico>,
  arrowOut: (p) => <Ico {...p}><path d="M5 11l6-6M7 5h4v4"/></Ico>,
  ellipsis: (p) => <Ico {...p}><circle cx="3.5" cy="8" r="0.9" fill="currentColor"/><circle cx="8" cy="8" r="0.9" fill="currentColor"/><circle cx="12.5" cy="8" r="0.9" fill="currentColor"/></Ico>,
  sun: (p) => <Ico {...p}><circle cx="8" cy="8" r="2.5"/><path d="M8 1.5v1.5M8 13v1.5M14.5 8H13M3 8H1.5M12.6 3.4l-1.1 1.1M4.5 11.5l-1.1 1.1M12.6 12.6l-1.1-1.1M4.5 4.5L3.4 3.4"/></Ico>,
  moon: (p) => <Ico {...p}><path d="M13 9.5A5.5 5.5 0 0 1 6.5 3a5.5 5.5 0 1 0 6.5 6.5z"/></Ico>,
};

window.Icons = Icons;
window.Ico = Ico;
