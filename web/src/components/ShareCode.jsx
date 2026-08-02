import { useState } from 'react';

// The six-character code, shown large enough to read out over the phone or
// copy by hand.
//
// It is the reliable fallback for everything the link cannot survive: a chat
// app that truncated it, a screenshot, a message forwarded as plain text.
//
// The caption stops at "find", not "open". Whether the code alone is enough
// to open this memory depends on a choice the sender made, and this page has
// no backend to ask — so it promises only the part that is always true.
export default function ShareCode({ shareId }) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(shareId);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard refused (insecure context, permissions) — the code is
      // on screen and can be typed, so there is nothing to recover from.
    }
  }

  return (
    <div className="mt-8">
      <p className="mb-2 font-mono text-xs uppercase tracking-widest text-[var(--color-on-surface-variant)]/60">
        Share code
      </p>
      <button
        onClick={handleCopy}
        className="font-mono text-2xl font-bold tracking-[0.35em] text-[var(--color-on-surface)] transition-opacity hover:opacity-70"
        title="Copy the code"
      >
        {shareId}
      </button>
      <p className="mt-2 text-xs text-[var(--color-on-surface-variant)]">
        {copied ? 'Code copied.' : 'Enter this in TimeDrop to find the memory.'}
      </p>
    </div>
  );
}
