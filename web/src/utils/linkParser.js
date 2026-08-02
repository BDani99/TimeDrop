// Parses the current page URL client-side only.
//
// This file is allowed to READ the hash fragment (the E2EE decryption key),
// because the "Open in TimeDrop" button has to carry the key across to the
// app. It must never be sent anywhere: no fetch, no analytics, no logging, no
// putting it in the DOM as text. It goes into an href for the app's own
// scheme and nowhere else. Everything here runs in the browser; the server
// never receives a fragment at all.
const SHARE_PATH_PATTERN = /^\/c\/([A-Za-z0-9]{6})$/;

export const APP_SCHEME = 'timedrop';

export function parseCurrentLocation() {
  const match = window.location.pathname.match(SHARE_PATH_PATTERN);
  if (!match) {
    return { isShareLink: false };
  }

  const params = new URLSearchParams(window.location.search);
  const fromName = params.get('from');

  // Leading '#' stripped; empty string when the link arrived without a key.
  const encryptionKey = window.location.hash.replace(/^#/, '');

  return {
    isShareLink: true,
    shareId: match[1],
    fromName: fromName ? decodeURIComponent(fromName) : null,
    encryptionKey: encryptionKey || null,
  };
}

/// The app's own URL, used to hand off from this page to an installed app.
///
/// The https link cannot do this: the browser is already on that domain, so
/// following a link to it does not re-trigger Universal/App Link handling — it
/// just reloads this page.
export function buildAppUrl({ shareId, fromName, encryptionKey }) {
  let url = `${APP_SCHEME}://c/${shareId}`;
  if (fromName) {
    url += `?from=${encodeURIComponent(fromName)}`;
  }
  if (encryptionKey) {
    url += `#${encryptionKey}`;
  }
  return url;
}
