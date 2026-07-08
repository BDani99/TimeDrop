import AnimatedMapBackground from './components/AnimatedMapBackground';
import LandingCard from './components/LandingCard';
import FallbackCard from './components/FallbackCard';
import { parseCurrentLocation } from './utils/linkParser';

// This is the entire zero-backend trust boundary: parse the URL client-side
// only, on mount, once. No fetch/XHR/WebSocket calls exist anywhere in this
// app, and the hash fragment (the E2EE decryption key) is never read here —
// only DownloadButton's copyCurrentUrl() touches it, and only to copy the
// full URL verbatim. Do not add analytics/Sentry/GA to this file without
// first stripping query/hash from whatever it captures.
function App() {
  const location = parseCurrentLocation();

  return (
    <div className="flex min-h-screen w-full flex-col items-center justify-center px-6 py-16">
      <AnimatedMapBackground />
      {location.isShareLink ? (
        <LandingCard shareId={location.shareId} fromName={location.fromName} />
      ) : (
        <FallbackCard />
      )}
    </div>
  );
}

export default App;
