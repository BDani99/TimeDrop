import { useReveal } from '../../hooks/useReveal';

// Three claims, all of which the app actually keeps. Nothing here is
// aspirational: the payload is withheld server-side until the unlock time, the
// key travels in the URL fragment so it never reaches us, and proximity is
// checked on the device before anything is decrypted.
const POINTS = [
  {
    icon: '🔒',
    title: 'We cannot watch it',
    body: 'Your memory is encrypted on your phone. The key travels inside the link and never reaches our servers, so nobody here can open what you sent.',
  },
  {
    icon: '🗺️',
    title: 'It only opens there',
    body: 'Not a notification that says "you are near". They have to actually go and stand in the place you chose.',
  },
  {
    icon: '⏳',
    title: 'Locked until the day',
    body: 'The video is not hidden behind a screen before then — it is not sent at all. There is nothing to peek at.',
  },
];

function Point({ point, index }) {
  const { ref, style } = useReveal({ delay: index * 120 });

  return (
    <li ref={ref} style={style} className="text-left">
      <div className="mb-4 text-3xl" aria-hidden="true">
        {point.icon}
      </div>
      <h3 className="mb-2 font-[var(--font-display)] text-xl font-bold text-[var(--color-on-surface)]">
        {point.title}
      </h3>
      <p className="text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        {point.body}
      </p>
    </li>
  );
}

export default function WhyDifferent() {
  const heading = useReveal();

  return (
    <section
      className="w-full py-24"
      style={{ backgroundColor: 'var(--color-surface-container-low)' }}
    >
      <div className="mx-auto w-full max-w-5xl px-6">
        <h2
          ref={heading.ref}
          style={heading.style}
          className="mb-14 text-center font-[var(--font-display)] text-3xl font-bold text-[var(--color-on-surface)] sm:text-4xl"
        >
          Why it feels different
        </h2>

        <ul className="grid list-none gap-10 p-0 sm:grid-cols-3">
          {POINTS.map((point, i) => (
            <Point key={point.title} point={point} index={i} />
          ))}
        </ul>
      </div>
    </section>
  );
}
