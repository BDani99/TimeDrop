import DownloadButton from './DownloadButton';
import CopyLinkButton from './CopyLinkButton';

// "Memory Card" pattern from design/DESIGN.md, mirrored from the mobile
// app's memoryCardDecoration(): 32px rounded corners, ambient orange-tinted
// shadow, 1px rose-gold border, cream/white surface.
export default function LandingCard({ shareId, fromName }) {
  const headline = fromName
    ? `${fromName} left you a time capsule.`
    : 'Someone left you a time capsule.';

  return (
    <div
      className="w-full max-w-md rounded-[32px] border p-8 text-center sm:p-10"
      style={{
        backgroundColor: 'var(--color-surface-container-lowest)',
        borderColor: 'var(--color-outline-variant)',
        boxShadow: '0 8px 40px -8px rgba(163, 61, 37, 0.16)',
      }}
    >
      <div className="mx-auto mb-6 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-[#ff8264] to-[#a33d25] shadow-lg shadow-[#a33d25]/30">
        <span className="text-2xl">🔒</span>
      </div>

      <h1 className="mb-3 font-[var(--font-display)] text-3xl font-bold leading-tight text-[var(--color-on-surface)] sm:text-4xl">
        {headline}
      </h1>

      <p className="mb-8 text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        A moment, sealed in time and place. Get the TimeDrop app to see when
        and where it unlocks.
      </p>

      <DownloadButton />
      <CopyLinkButton />

      <p className="mt-6 font-mono text-xs tracking-widest text-[var(--color-on-surface-variant)]/60 uppercase">
        Share code {shareId}
      </p>
    </div>
  );
}
