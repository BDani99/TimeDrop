// Parses the current page URL client-side only. Never reads/logs/transmits
// the hash fragment (the E2EE decryption key) anywhere — see clipboardHelper.js.
const SHARE_PATH_PATTERN = /^\/c\/([A-Za-z0-9]{6})$/;

export function parseCurrentLocation() {
  const match = window.location.pathname.match(SHARE_PATH_PATTERN);
  if (!match) {
    return { isShareLink: false };
  }

  const params = new URLSearchParams(window.location.search);
  const fromName = params.get('from');

  return {
    isShareLink: true,
    shareId: match[1],
    fromName: fromName ? decodeURIComponent(fromName) : null,
  };
}
