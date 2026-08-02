import { useEffect, useRef, useState } from 'react';

/**
 * Fades and lifts an element into place the first time it scrolls into view.
 *
 * An IntersectionObserver rather than a scroll handler: the browser does the
 * work off the main thread, and there is no listener firing sixty times a
 * second on a page that animates three things.
 *
 * Reveals once and then disconnects. Content that fades back out when you
 * scroll past it is a nuisance, not an effect.
 *
 * Honours `prefers-reduced-motion` by starting in the revealed state, so the
 * page is complete and readable for anyone who has asked for less movement.
 */
export function useReveal({ delay = 0 } = {}) {
  const ref = useRef(null);
  const prefersReducedMotion =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  const [revealed, setRevealed] = useState(Boolean(prefersReducedMotion));

  useEffect(() => {
    if (revealed) return undefined;
    const node = ref.current;
    if (!node) return undefined;

    // No IntersectionObserver (very old browser): show everything rather than
    // leaving the page permanently blank.
    if (typeof IntersectionObserver === 'undefined') {
      setRevealed(true);
      return undefined;
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        setRevealed(true);
      },
      // Fires a little before the element reaches the viewport, so the motion
      // is already underway by the time it is properly on screen.
      { rootMargin: '0px 0px -12% 0px', threshold: 0.05 },
    );

    observer.observe(node);
    return () => observer.disconnect();
  }, [revealed]);

  const style = {
    opacity: revealed ? 1 : 0,
    transform: revealed ? 'none' : 'translateY(24px)',
    transition: prefersReducedMotion
      ? 'none'
      : 'opacity 700ms cubic-bezier(0.22, 1, 0.36, 1), transform 700ms cubic-bezier(0.22, 1, 0.36, 1)',
    transitionDelay: `${delay}ms`,
  };

  return { ref, style };
}
