// TODO(release): replace the App Store id — it is a placeholder and the link
// 404s until the app record exists in App Store Connect. See teendo.md.
export const APP_STORE_URL = 'https://apps.apple.com/app/timedrop/id0000000000';

// Must match `applicationId` in mobile/android/app/build.gradle.kts. It used
// to read com.timedrop.app, which is not this app and never was — the button
// sent every Android recipient to a Play Store 404.
export const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.timedrop.timedrop_mobile';

export function detectOS() {
  const ua = window.navigator.userAgent || '';
  if (/iPad|iPhone|iPod/.test(ua) && !window.MSStream) return 'ios';
  if (/Android/.test(ua)) return 'android';
  return 'desktop';
}

export function storeUrlForCurrentOS() {
  const os = detectOS();
  if (os === 'ios') return APP_STORE_URL;
  if (os === 'android') return PLAY_STORE_URL;
  return PLAY_STORE_URL;
}
