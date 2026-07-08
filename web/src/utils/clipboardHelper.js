// Copies the current page URL VERBATIM, hash fragment included. This is the
// E2EE trust boundary for the web app: the fragment holds the decryption
// key and must never be read, logged, or altered here — only copied as-is
// so the mobile app can extract it after the user pastes/opens it there.
export async function copyCurrentUrl() {
  const url = window.location.href;

  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(url);
      return true;
    } catch {
      // fall through to the legacy fallback below
    }
  }

  try {
    const textarea = document.createElement('textarea');
    textarea.value = url;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    const success = document.execCommand('copy');
    document.body.removeChild(textarea);
    return success;
  } catch {
    return false;
  }
}
