import { APP_STORE_URL, PLAY_STORE_URL, detectOS } from '../../utils/osDetector';

const IOS = {
  href: APP_STORE_URL,
  label: 'Download for iPhone',
  otherLabel: 'On Android instead',
};
const ANDROID = {
  href: PLAY_STORE_URL,
  label: 'Get it on Android',
  otherLabel: 'On iPhone instead',
};

// On a desktop we cannot know which phone the reader owns, so both stores get
// equal weight — guessing there would hide the only link that matters. On a
// phone we do know, and showing an Android button to somebody holding an
// iPhone is a button that can only be wrong for them.
//
// The other platform stays reachable as a quiet secondary link rather than
// disappearing: sending the link on to somebody with the other kind of phone
// is a completely ordinary thing to do.
export default function StoreButtons({ align = 'center' }) {
  const os = detectOS();
  const centred = align === 'center';

  if (os === 'ios' || os === 'android') {
    const primary = os === 'ios' ? IOS : ANDROID;
    const secondary = os === 'ios' ? ANDROID : IOS;

    return (
      <div className={`flex flex-col gap-3 ${centred ? 'items-center' : 'items-start'}`}>
        <a
          href={primary.href}
          className="w-full rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-8 py-4 text-center text-base font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
        >
          {primary.label}
        </a>
        <a
          href={secondary.href}
          className="text-sm text-[var(--color-on-surface-variant)] underline underline-offset-4 transition-opacity hover:opacity-70"
        >
          {primary.otherLabel}
        </a>
      </div>
    );
  }

  return (
    <div
      className={`flex flex-col gap-3 sm:flex-row ${
        centred ? 'sm:justify-center' : ''
      }`}
    >
      <a
        href={IOS.href}
        className="rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-8 py-4 text-center text-base font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
      >
        {IOS.label}
      </a>
      <a
        href={ANDROID.href}
        className="rounded-full border px-8 py-4 text-center text-base font-semibold transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
        style={{
          borderColor: 'var(--color-outline-variant)',
          color: 'var(--color-primary)',
        }}
      >
        {ANDROID.label}
      </a>
    </div>
  );
}
