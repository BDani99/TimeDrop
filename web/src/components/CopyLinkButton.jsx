import { useState } from 'react';
import { copyCurrentUrl } from '../utils/clipboardHelper';

// Secondary action for people who already have the app installed: copy the
// full link (with its #key) so the app's clipboard detection / "Redeem a
// Drop" sheet can pick it up. Copies verbatim — never reads or alters the
// hash fragment (the E2EE trust boundary).
export default function CopyLinkButton() {
  const [copied, setCopied] = useState(false);

  async function handleClick() {
    const ok = await copyCurrentUrl();
    setCopied(ok);
    window.setTimeout(() => setCopied(false), 2000);
  }

  return (
    <button
      onClick={handleClick}
      className="mt-3 w-full rounded-full border px-8 py-3 text-sm font-semibold transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
      style={{
        borderColor: 'var(--color-outline-variant)',
        color: 'var(--color-primary)',
        backgroundColor: 'transparent',
      }}
    >
      {copied ? 'Link copied — open it in the app' : 'Already have the app? Copy link'}
    </button>
  );
}
