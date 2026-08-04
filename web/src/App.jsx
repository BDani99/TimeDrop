import AnimatedMapBackground from './components/AnimatedMapBackground';
import LandingCard from './components/LandingCard';
import LandingPage from './components/landing/LandingPage';
import PrivacyPage from './components/legal/PrivacyPage';
import TermsPage from './components/legal/TermsPage';
import { parseCurrentLocation } from './utils/linkParser';

// This is the entire zero-backend trust boundary: parse the URL client-side
// only, on mount, once. No fetch/XHR/WebSocket calls exist anywhere in this
// app.
//
// The hash fragment (the E2EE decryption key) is read in exactly two places
// and leaves in exactly two ways: into the `timedrop://` handoff URL, and onto
// the clipboard as part of the verbatim page URL. It is never rendered, never
// logged, and never sent over the network. Do not add analytics/Sentry/GA to
// this app without first stripping query and hash from whatever it captures.
// The legal pages. Read straight off the pathname rather than through
// linkParser, which is deliberately about one thing — the share link and the
// key in its fragment — and should not grow into a router.
//
// vercel.json already rewrites every non-.well-known path to index.html, so
// these need no server-side configuration.
const LEGAL_ROUTES = {
  '/privacy': PrivacyPage,
  '/terms': TermsPage,
};

function legalPageForPath() {
  // Tolerate a trailing slash; anything else is not a legal page.
  const path = window.location.pathname.replace(/\/+$/, '') || '/';
  return LEGAL_ROUTES[path] ?? null;
}

function App() {
  const location = parseCurrentLocation();

  // Privacy and Terms are checked first, and not only for tidiness: both stores
  // reject a submission whose policy link does not resolve to a policy, and
  // before this existed /privacy and /terms simply re-rendered the landing
  // page — the footer link looked like it did nothing.
  const LegalPageComponent = legalPageForPath();
  if (LegalPageComponent) {
    return (
      <div className="min-h-screen w-full">
        <LegalPageComponent />
      </div>
    );
  }

  // Two different pages, and the difference is not cosmetic. A drop link gets
  // one centred card and nothing to read past it. Everything else gets the
  // scrolling product page.
  if (location.isShareLink) {
    return (
      <div className="flex min-h-screen w-full flex-col items-center justify-center px-6 py-16">
        <AnimatedMapBackground />
        <LandingCard
          shareId={location.shareId}
          fromName={location.fromName}
          encryptionKey={location.encryptionKey}
        />
      </div>
    );
  }

  return (
    <div className="min-h-screen w-full">
      <AnimatedMapBackground />
      <LandingPage />
    </div>
  );
}

export default App;
