import { useReveal } from '../../hooks/useReveal';

const STEPS = [
  {
    icon: '🎥',
    title: 'Record it',
    body: 'A video, a handwritten note, a few photos. Whatever the moment actually was.',
  },
  {
    icon: '📍',
    title: 'Seal it to a time and a place',
    body: 'Pick the spot on the map and the day it should open. Then it is out of your hands.',
  },
  {
    icon: '🧭',
    title: 'They go and find it',
    body: 'On the day, a map leads them close and a radar takes them the last fifty metres. It opens where you left it.',
  },
];

function Step({ step, index }) {
  const { ref, style } = useReveal({ delay: index * 120 });

  return (
    <li
      ref={ref}
      // The card's colours come from CSS variables, which Tailwind's border
      // and background utilities cannot read — hence the inline style.
      style={{
        ...style,
        borderColor: 'var(--color-outline-variant)',
        backgroundColor: 'var(--color-surface-container-lowest)',
        boxShadow: '0 8px 40px -8px rgba(163, 61, 37, 0.12)',
      }}
      className="rounded-[28px] border p-8 text-left"
    >
      <div className="mb-5 flex items-center gap-4">
        <span
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-lg"
          style={{
            backgroundColor: 'var(--color-secondary-container)',
            color: 'var(--color-primary)',
          }}
          aria-hidden="true"
        >
          {step.icon}
        </span>
        <span className="font-mono text-xs uppercase tracking-widest text-[var(--color-on-surface-variant)]/60">
          Step {index + 1}
        </span>
      </div>
      <h3 className="mb-2 font-[var(--font-display)] text-2xl font-bold text-[var(--color-on-surface)]">
        {step.title}
      </h3>
      <p className="text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        {step.body}
      </p>
    </li>
  );
}

export default function HowItWorks() {
  const heading = useReveal();

  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-24">
      <h2
        ref={heading.ref}
        style={heading.style}
        className="mb-14 text-center font-[var(--font-display)] text-3xl font-bold text-[var(--color-on-surface)] sm:text-4xl"
      >
        How it works
      </h2>

      <ul className="grid list-none gap-6 p-0 sm:grid-cols-3">
        {STEPS.map((step, i) => (
          <Step key={step.title} step={step} index={i} />
        ))}
      </ul>
    </section>
  );
}
