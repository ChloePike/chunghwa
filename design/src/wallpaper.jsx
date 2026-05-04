// Sequoia-inspired abstract gradient wallpapers, light & dark
// Pure CSS — no images. Layered radial gradients to simulate Liquid Glass backdrop.

function ChWallpaper({ variant = "aurora-dark", intensity = "medium" }) {
  const styles = {
    "aurora-dark": {
      background: `
        radial-gradient(1200px 800px at 8% 12%, oklch(0.55 0.18 280) 0%, transparent 55%),
        radial-gradient(1100px 900px at 95% 18%, oklch(0.50 0.20 340) 0%, transparent 50%),
        radial-gradient(900px 700px at 78% 88%, oklch(0.55 0.16 220) 0%, transparent 55%),
        radial-gradient(1000px 800px at 18% 92%, oklch(0.45 0.16 300) 0%, transparent 50%),
        linear-gradient(135deg, oklch(0.18 0.04 280), oklch(0.13 0.05 260))
      `,
    },
    "aurora-light": {
      background: `
        radial-gradient(1200px 800px at 8% 12%, oklch(0.85 0.10 230) 0%, transparent 55%),
        radial-gradient(1100px 900px at 95% 18%, oklch(0.86 0.10 320) 0%, transparent 50%),
        radial-gradient(900px 700px at 78% 88%, oklch(0.88 0.08 180) 0%, transparent 55%),
        radial-gradient(1000px 800px at 18% 92%, oklch(0.84 0.10 280) 0%, transparent 50%),
        linear-gradient(135deg, oklch(0.94 0.02 240), oklch(0.92 0.03 280))
      `,
    },
    "midnight": {
      background: `
        radial-gradient(1400px 1000px at 50% -10%, oklch(0.30 0.12 260) 0%, transparent 60%),
        radial-gradient(900px 700px at 90% 90%, oklch(0.25 0.10 300) 0%, transparent 55%),
        linear-gradient(180deg, oklch(0.12 0.03 260), oklch(0.07 0.02 260))
      `,
    },
    "linen": {
      background: `
        radial-gradient(1400px 1000px at 50% 10%, oklch(0.97 0.02 80) 0%, transparent 60%),
        radial-gradient(900px 700px at 90% 90%, oklch(0.92 0.04 50) 0%, transparent 55%),
        linear-gradient(180deg, oklch(0.96 0.01 70), oklch(0.93 0.02 60))
      `,
    },
  };

  return (
    <div style={{
      position: "absolute", inset: 0,
      ...styles[variant],
    }}>
      {/* faint grain */}
      <div style={{
        position: "absolute", inset: 0,
        opacity: 0.08, mixBlendMode: "overlay",
        backgroundImage: `url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/><feColorMatrix values='0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.6 0'/></filter><rect width='100%25' height='100%25' filter='url(%23n)' opacity='0.6'/></svg>")`,
      }} />
    </div>
  );
}

window.ChWallpaper = ChWallpaper;
