import { useState } from 'react';
import { copyCurrentUrl } from '../utils/clipboardHelper';
import { storeUrlForCurrentOS } from '../utils/osDetector';

// For someone who does not have TimeDrop yet.
//
// The whole link — key and all — goes onto the clipboard before we send them
// to the store, because there is no way to carry it through an install
// otherwise: iOS has no install referrer, and the App Store does not pass
// anything through. On first launch the app looks at the clipboard once and
// *asks* whether to open what it found. It never reads it silently.
export default function GetTheAppButton() {
  const [copied, setCopied] = useState(false);

  async function handleClick() {
    const success = await copyCurrentUrl();
    setCopied(success);
    window.setTimeout(
      () => {
        window.location.href = storeUrlForCurrentOS();
      },
      success ? 900 : 0,
    );
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
      {copied
        ? 'Link saved — opening the app store…'
        : "Don't have the app? Get it"}
    </button>
  );
}
