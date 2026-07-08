import { useState } from 'react';
import { copyCurrentUrl } from '../utils/clipboardHelper';
import { storeUrlForCurrentOS } from '../utils/osDetector';

export default function DownloadButton() {
  const [copied, setCopied] = useState(false);

  async function handleClick() {
    const success = await copyCurrentUrl();
    setCopied(success);
    window.setTimeout(() => {
      window.location.href = storeUrlForCurrentOS();
    }, success ? 900 : 0);
  }

  return (
    <button
      onClick={handleClick}
      className="w-full rounded-full bg-gradient-to-r from-[#ff8264] to-[#a33d25] px-8 py-4 font-[var(--font-body)] text-base font-semibold text-white shadow-[0_8px_40px_-8px_rgba(163,61,37,0.6)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]"
    >
      {copied ? 'Copied — opening the app store…' : 'Copy code & download app'}
    </button>
  );
}
