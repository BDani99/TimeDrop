import StoreButtons from './StoreButtons';
import { useReveal } from '../../hooks/useReveal';

export default function Hero() {
  const title = useReveal();
  const body = useReveal({ delay: 120 });
  const cta = useReveal({ delay: 240 });

  return (
    <section className="flex min-h-[88vh] flex-col items-center justify-center px-6 py-20 text-center">
      <div
        className="mx-auto mb-8 flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-[#ff8264] to-[#a33d25] shadow-lg shadow-[#a33d25]/30"
        aria-hidden="true"
      >
        <span className="text-3xl">⏳</span>
      </div>

      <h1
        ref={title.ref}
        style={title.style}
        className="max-w-3xl font-[var(--font-display)] text-4xl font-bold leading-tight text-[var(--color-on-surface)] sm:text-6xl"
      >
        Leave a moment where it happened.
      </h1>

      <p
        ref={body.ref}
        style={body.style}
        className="mt-6 max-w-xl text-lg leading-relaxed text-[var(--color-on-surface-variant)]"
      >
        TimeDrop seals a video to a time and a place. It stays closed until the
        day you chose — and it only opens for the person you left it for, once
        they are standing there.
      </p>

      <div ref={cta.ref} style={cta.style} className="mt-10 w-full max-w-md">
        <StoreButtons />
      </div>
    </section>
  );
}
