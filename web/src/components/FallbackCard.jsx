export default function FallbackCard() {
  return (
    <div className="w-full max-w-md rounded-[32px] border border-white/10 bg-white/[0.06] p-8 text-center shadow-2xl backdrop-blur-2xl sm:p-10">
      <h1 className="mb-3 font-[var(--font-display)] text-3xl font-bold text-white">
        TimeDrop
      </h1>
      <p className="text-base leading-relaxed text-white/60">
        Lock a moment in time and place, and hand your loved one a link that
        only opens when — and where — it's meant to.
      </p>
    </div>
  );
}
