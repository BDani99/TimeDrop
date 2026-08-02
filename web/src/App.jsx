import AnimatedMapBackground from './components/AnimatedMapBackground';
import LandingCard from './components/LandingCard';
import FallbackCard from './components/FallbackCard';
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
function App() {
  const location = parseCurrentLocation();

  return (
    <div className="flex min-h-screen w-full flex-col items-center justify-center px-6 py-16">
      <AnimatedMapBackground />
      {location.isShareLink ? (
        <LandingCard
          shareId={location.shareId}
          fromName={location.fromName}
          encryptionKey={location.encryptionKey}
        />
      ) : (
        <FallbackCard />
      )}
    </div>
  );
}

export default App;
