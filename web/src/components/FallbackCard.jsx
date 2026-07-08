export default function FallbackCard() {
  return (
    <div
      className="w-full max-w-md rounded-[32px] border p-8 text-center sm:p-10"
      style={{
        backgroundColor: 'var(--color-surface-container-lowest)',
        borderColor: 'var(--color-outline-variant)',
        boxShadow: '0 8px 40px -8px rgba(163, 61, 37, 0.16)',
      }}
    >
      <h1 className="mb-3 font-[var(--font-display)] text-3xl font-bold text-[var(--color-on-surface)]">
        TimeDrop
      </h1>
      <p className="text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        Lock a moment in time and place, and hand your loved one a link that
        only opens when — and where — it's meant to.
      </p>
    </div>
  );
}
