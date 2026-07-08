// Decorative only — cream "Golden Hour" backdrop with soft peach/terracotta
// "ambient glow" bokeh, matching the mobile app's design system 1:1
// (design/DESIGN.md's "Organic Blurs" + Ambient Glow shadows) instead of
// diverging into a separate dark theme.
export default function AnimatedMapBackground() {
  return (
    <div className="fixed inset-0 -z-10 overflow-hidden bg-[var(--color-surface)]">
      <div className="absolute -top-32 -left-24 h-96 w-96 rounded-full bg-[#ff8264] opacity-25 blur-[100px] animate-pulse" />
      <div
        className="absolute top-1/3 -right-24 h-[28rem] w-[28rem] rounded-full bg-[#fecaa3] opacity-40 blur-[120px] animate-pulse"
        style={{ animationDelay: '1.5s' }}
      />
      <div
        className="absolute bottom-0 left-1/4 h-80 w-80 rounded-full bg-[#a33d25] opacity-[0.08] blur-[110px] animate-pulse"
        style={{ animationDelay: '3s' }}
      />
    </div>
  );
}
