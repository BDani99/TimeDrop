import { Component } from 'react';

// This page is often the only thing standing between a recipient and their
// memory (see LandingCard: "reaching here means something went wrong" is
// already the fallback state for a resolved link). Without a boundary, any
// uncaught render error blanks the entire page to white with no recovery —
// the worst possible outcome for a page whose whole job is to hand someone
// off to their drop. This catches that case and offers a way to retry
// instead.
class ErrorBoundary extends Component {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error, info) {
    // No analytics/Sentry in this app by design (see App.jsx) — this is the
    // only record of a render failure, so it goes to the console.
    console.error('Unhandled render error', error, info);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-screen w-full flex-col items-center justify-center gap-4 px-6 text-center">
          <p className="text-base text-[var(--color-on-surface-variant)]">
            Something went wrong. Try opening the link again.
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

export default ErrorBoundary;
