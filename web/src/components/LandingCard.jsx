import DownloadButton from './DownloadButton';

export default function LandingCard({ shareId, fromName }) {
  const headline = fromName
    ? `${fromName} left you a time capsule.`
    : 'Someone left you a time capsule.';

  return (
    <div className="w-full max-w-md rounded-[32px] border border-white/10 bg-white/[0.06] p-8 text-center shadow-2xl backdrop-blur-2xl sm:p-10">
      <div className="mx-auto mb-6 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-[#ff8264] to-[#a33d25] shadow-lg shadow-[#a33d25]/30">
        <span className="text-2xl">🔒</span>
      </div>

      <h1 className="mb-3 font-[var(--font-display)] text-3xl font-bold leading-tight text-white sm:text-4xl">
        {headline}
      </h1>

      <p className="mb-8 text-base leading-relaxed text-white/60">
        A moment, sealed in time and place. Get the TimeDrop app to see when
        and where it unlocks.
      </p>

      <DownloadButton />

      <p className="mt-6 font-mono text-xs tracking-widest text-white/40 uppercase">
        Share code {shareId}
      </p>
    </div>
  );
}
