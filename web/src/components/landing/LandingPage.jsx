import Hero from './Hero';
import HowItWorks from './HowItWorks';
import WhyDifferent from './WhyDifferent';
import ClosingCta from './ClosingCta';

// What the domain shows to somebody who arrived without a drop link — a
// search result, a screenshot, someone typing the name in. It used to be a
// single card with two sentences, which explained the tagline and nothing
// else.
//
// The drop link route (/c/{code}) does NOT come through here and is
// deliberately untouched: that page has one job, and adding a product pitch to
// the moment somebody learns a memory is waiting for them would be a mistake.
export default function LandingPage() {
  return (
    <main className="flex w-full flex-col items-center">
      <Hero />
      <HowItWorks />
      <WhyDifferent />
      <ClosingCta />

      <footer className="w-full px-6 pb-12 text-center text-sm text-[var(--color-on-surface-variant)]/70">
        <nav className="mb-3 flex justify-center gap-6">
          <a href="/privacy" className="hover:underline">
            Privacy
          </a>
          <a href="/terms" className="hover:underline">
            Terms
          </a>
        </nav>
        <p>TimeDrop</p>
      </footer>
    </main>
  );
}
