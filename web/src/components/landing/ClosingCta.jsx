import StoreButtons from './StoreButtons';
import { useReveal } from '../../hooks/useReveal';

export default function ClosingCta() {
  const { ref, style } = useReveal();

  return (
    <section className="mx-auto w-full max-w-3xl px-6 py-24 text-center">
      <div ref={ref} style={style}>
        <h2 className="mb-4 font-[var(--font-display)] text-3xl font-bold text-[var(--color-on-surface)] sm:text-4xl">
          Somewhere out there is a moment worth leaving.
        </h2>
        <p className="mb-10 text-lg leading-relaxed text-[var(--color-on-surface-variant)]">
          Your first drop is free.
        </p>
        <StoreButtons />
      </div>
    </section>
  );
}
