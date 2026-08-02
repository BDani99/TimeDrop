import { APP_STORE_URL, PLAY_STORE_URL } from '../../utils/osDetector';

// Both stores, always both — the landing page is as likely to be opened on a
// desktop as on a phone, and guessing wrong hides the only link that matters.
export default function StoreButtons({ align = 'center' }) {
  return (
    <div
      className={`flex flex-col gap-3 sm:flex-row ${
        align === 'center' ? 'sm:justify-center' : ''
      }`}
    >
      <a
        href={APP_STORE_URL}
        className="rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-8 py-4 text-center text-base font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
      >
        Download for iPhone
      </a>
      <a
        href={PLAY_STORE_URL}
        className="rounded-full border px-8 py-4 text-center text-base font-semibold transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
        style={{
          borderColor: 'var(--color-outline-variant)',
          color: 'var(--color-primary)',
        }}
      >
        Get it on Android
      </a>
    </div>
  );
}
