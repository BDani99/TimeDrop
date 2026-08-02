import OpenInAppButton from './OpenInAppButton';
import GetTheAppButton from './GetTheAppButton';
import ShareCode from './ShareCode';

// "Memory Card" pattern from design/DESIGN.md, mirrored from the mobile
// app's memoryCardDecoration(): 32px rounded corners, ambient orange-tinted
// shadow, 1px rose-gold border, cream/white surface.
//
// Most recipients never see this page: tapping the link in a chat app opens
// TimeDrop directly. Reaching here means one of three things went wrong or
// differently — the app is not installed, App Link verification has not taken
// effect, or they are on a desktop. So the page has exactly two jobs: get an
// installed app to open, and make sure someone who has to install it first
// does not lose the memory on the way.
export default function LandingCard({ shareId, fromName, encryptionKey }) {
  const headline = fromName
    ? `${fromName} left you a time capsule.`
    : 'Someone left you a time capsule.';

  return (
    <div
      className="w-full max-w-md rounded-[32px] border p-8 text-center sm:p-10"
      style={{
        backgroundColor: 'var(--color-surface-container-lowest)',
        borderColor: 'var(--color-outline-variant)',
        boxShadow: '0 8px 40px -8px rgba(163, 61, 37, 0.16)',
      }}
    >
      <div className="mx-auto mb-6 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-[#ff8264] to-[#a33d25] shadow-lg shadow-[#a33d25]/30">
        <span className="text-2xl">🔒</span>
      </div>

      <h1 className="mb-3 font-[var(--font-display)] text-3xl font-bold leading-tight text-[var(--color-on-surface)] sm:text-4xl">
        {headline}
      </h1>

      <p className="mb-8 text-base leading-relaxed text-[var(--color-on-surface-variant)]">
        A moment, sealed in time and place. Open it in TimeDrop to see when and
        where it unlocks.
      </p>

      <OpenInAppButton
        shareId={shareId}
        fromName={fromName}
        encryptionKey={encryptionKey}
      />
      <GetTheAppButton />

      <ShareCode shareId={shareId} />
    </div>
  );
}
