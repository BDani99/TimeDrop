import { useEffect, useRef, useState } from 'react';
import { buildAppUrl } from '../utils/linkParser';

// Hands off to an installed app via the app's own URL scheme, carrying the
// decryption key along in the fragment. The key is put into a navigation and
// nowhere else — not into state that gets rendered, not into a log.
//
// There is no reliable way to ask a browser "is this app installed?", so the
// standard trick applies: navigate, and if we are still here a moment later,
// nothing handled it. `document.hidden` is the tell — a successful handoff
// backgrounds the page.
export default function OpenInAppButton({ shareId, fromName, encryptionKey }) {
  const [failed, setFailed] = useState(false);
  const [pending, setPending] = useState(false);
  const timeoutRef = useRef(null);

  useEffect(() => {
    return () => window.clearTimeout(timeoutRef.current);
  }, []);

  function handleClick() {
    // A double-tap while the 1.2s "did it open?" timer is still pending
    // would re-navigate and stack a second timer on top of the first.
    if (pending) return;
    setPending(true);
    setFailed(false);
    const target = buildAppUrl({ shareId, fromName, encryptionKey });
    const startedAt = Date.now();

    window.location.href = target;

    timeoutRef.current = window.setTimeout(() => {
      setPending(false);
      // If the app opened, this tab went to the background and the timer
      // usually fires late as well — both checks guard against a false
      // "didn't work" on a slow device.
      if (document.hidden || Date.now() - startedAt > 2500) return;
      setFailed(true);
    }, 1200);
  }

  return (
    <>
      <button
        onClick={handleClick}
        disabled={pending}
        className="w-full rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-8 py-4 font-[var(--font-body)] text-base font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-70"
      >
        Open in TimeDrop
      </button>
      {failed && (
        <p className="mt-3 text-sm text-[var(--color-on-surface-variant)]">
          Nothing opened — you probably need the app first.
        </p>
      )}
    </>
  );
}
