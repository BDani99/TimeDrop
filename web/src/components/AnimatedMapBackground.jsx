// Decorative only — dark glassmorphism backdrop with blurred "bokeh"
// circles evoking captured light. Deliberately diverges from the mobile
// app's warm/light "Golden Hour" palette (see terv.md §4's explicit dark
// glassmorphism spec for the web landing page).
export default function AnimatedMapBackground() {
  return (
    <div className="fixed inset-0 -z-10 overflow-hidden bg-[#0b0d12]">
      <div
        className="absolute inset-0 opacity-[0.08]"
        style={{
          backgroundImage:
            'linear-gradient(#fff 1px, transparent 1px), linear-gradient(90deg, #fff 1px, transparent 1px)',
          backgroundSize: '48px 48px',
        }}
      />
      <div className="absolute -top-32 -left-24 h-96 w-96 rounded-full bg-[#ff8264] opacity-20 blur-[100px] animate-pulse" />
      <div
        className="absolute top-1/3 -right-24 h-[28rem] w-[28rem] rounded-full bg-[#a33d25] opacity-25 blur-[120px] animate-pulse"
        style={{ animationDelay: '1.5s' }}
      />
      <div
        className="absolute bottom-0 left-1/4 h-80 w-80 rounded-full bg-[#fecaa3] opacity-10 blur-[110px] animate-pulse"
        style={{ animationDelay: '3s' }}
      />
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-[#0b0d12]" />
    </div>
  );
}
