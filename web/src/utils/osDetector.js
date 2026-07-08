export const APP_STORE_URL = 'https://apps.apple.com/app/timedrop/id0000000000';
export const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.timedrop.app';

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
