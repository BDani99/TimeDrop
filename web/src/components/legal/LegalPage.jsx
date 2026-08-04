// Shared shell for /terms and /privacy.
//
// Deliberately plain: no reveal animations, no gradients, no map behind it.
// These two pages exist to be read and to be checked by a store reviewer, and
// every bit of motion is something between the reader and a sentence they may
// need to rely on later.
export default function LegalPage({ title, updated, children }) {
  return (
    <main className="relative z-10 mx-auto w-full max-w-3xl px-6 py-16">
      <a
        href="/"
        className="text-sm text-[var(--color-primary)] hover:underline"
      >
        ← TimeDrop
      </a>

      <h1 className="mt-8 font-[var(--font-display)] text-4xl font-bold text-[var(--color-on-surface)]">
        {title}
      </h1>
      <p className="mt-2 text-sm text-[var(--color-on-surface-variant)]/70">
        Last updated: {updated}
      </p>

      <div className="mt-10 flex flex-col gap-8">{children}</div>

      <footer className="mt-16 border-t pt-8 text-sm text-[var(--color-on-surface-variant)]/70"
        style={{ borderColor: 'var(--color-outline-variant)' }}
      >
        <nav className="flex gap-6">
          <a href="/privacy" className="hover:underline">
            Privacy
          </a>
          <a href="/terms" className="hover:underline">
            Terms
          </a>
          <a href="/" className="hover:underline">
            Home
          </a>
        </nav>
      </footer>
    </main>
  );
}

export function Section({ heading, children }) {
  return (
    <section>
      <h2 className="mb-3 font-[var(--font-display)] text-2xl font-bold text-[var(--color-on-surface)]">
        {heading}
      </h2>
      <div className="flex flex-col gap-4 text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        {children}
      </div>
    </section>
  );
}

// A claim that a reader is entitled to see stated bluntly rather than buried in
// a paragraph — the code-unlock caveat, the "we cannot recover this" warning.
export function Callout({ children }) {
  return (
    <p
      className="rounded-2xl border px-5 py-4"
      style={{
        borderColor: 'var(--color-outline-variant)',
        backgroundColor: 'var(--color-surface-container-low)',
      }}
    >
      {children}
    </p>
  );
}

export function List({ children }) {
  return (
    <ul className="flex list-disc flex-col gap-2 pl-5 marker:text-[var(--color-outline-variant)]">
      {children}
    </ul>
  );
}
