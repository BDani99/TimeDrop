import LegalPage, { Section, Callout, List } from './LegalPage';

// Written against what the code and the database actually do, not against a
// template. Every factual claim here was checked: the schema of
// `time_capsules` / `received_capsules` / `user_settings`, the retention rules
// in migrations 0024 and 0031, the code-unlock opt-in in 0030, and the
// single-shot clipboard read in LocalPrefsService.
//
// If you change any of those, this page is part of the change. In particular:
// weakening or extending what the server can read is not a backend detail, it
// is a promise made on this page.
//
// [[LEGAL_ENTITY]] and [[REGISTERED_ADDRESS]] are the only deliberate
// placeholders on this page. Grep for `[[` across this folder before
// publishing — the Terms page has two more.
export default function PrivacyPage() {
  return (
    <LegalPage title="Privacy Policy" updated="3 August 2026">
      <Section heading="Who we are">
        <p>
          TimeDrop is operated by [[LEGAL_ENTITY]], [[REGISTERED_ADDRESS]]. For
          anything in this policy, including any request about your data, write
          to{' '}
          <a
            href="mailto:support@timedrop.app"
            className="text-[var(--color-primary)] hover:underline"
          >
            support@timedrop.app
          </a>
          .
        </p>
        <p>
          This policy covers the TimeDrop mobile app and this website. It
          describes what we hold, why, and for how long — including the parts
          that are less flattering to us.
        </p>
      </Section>

      <Section heading="Your account">
        <p>
          You can use TimeDrop without giving us a name, an email address or a
          phone number. On first launch the app creates an anonymous account,
          and that is enough to send and receive memories.
        </p>
        <p>
          You may later link the account to Apple or Google so it survives a
          lost phone. If you do, we receive the account identifier from that
          provider — and your email address, unless you use Apple&apos;s private
          relay. We do not receive your password.
        </p>
      </Section>

      <Section heading="What is in a memory, and what we can see">
        <p>
          When you seal a drop, the video, the photos and the note are encrypted
          on your phone before anything is uploaded. The decryption key is put
          in the part of the share link after the <code>#</code>, which browsers
          never transmit to a server. We store the encrypted result and cannot
          read it.
        </p>
        <p>
          Some things about a drop are <strong>not</strong> encrypted, because
          the service needs them to work:
        </p>
        <List>
          <li>
            the coordinates you chose and the city name derived from them — the
            recipient&apos;s app has to know where to send them
          </li>
          <li>the date and time it unlocks</li>
          <li>the six-character share code</li>
          <li>the sender name you typed, if you typed one</li>
        </List>
        <p>
          So we can tell that someone left something at a particular place on a
          particular date. We cannot tell what it was.
        </p>

        <Callout>
          <strong>One exception, and we would rather state it than bury it.</strong>{' '}
          For each drop, the sender can turn on &ldquo;openable with the code
          alone&rdquo;, so a recipient whose link got mangled can still get in
          by typing the code. When that is on, the key is stored on our servers
          alongside the memory, which means{' '}
          <strong>we are technically able to decrypt that one drop</strong>. It
          is off unless the sender switches it on, and it applies only to the
          drop they switched it on for. Everything else stays end-to-end
          encrypted.
        </Callout>
      </Section>

      <Section heading="Memories you receive">
        <p>
          When a drop reaches you, we store your own copy of its decryption key
          so your Vault can replay it later, together with the place, the unlock
          time, whether and when you opened it, and how far away you were when
          it unlocked. That last number exists so the keepsake card can still
          say it years later.
        </p>
      </Section>

      <Section heading="Everything else we store">
        <List>
          <li>
            <strong>Settings</strong> — your display name, whether you finished
            onboarding, your onboarding answers, and a push notification token
            so we can remind you when a memory is ready.
          </li>
          <li>
            <strong>Drops and purchases</strong> — how many drops you have left,
            your subscription state, and a ledger of how the balance changed.
            Purchases are processed by Apple or Google and reported to us
            through RevenueCat; we never see your card details.
          </li>
          <li>
            <strong>Feedback</strong> — if you write to us from inside the app,
            we keep the message with your app version and platform.
          </li>
          <li>
            <strong>A security log</strong> — a record of sensitive actions such
            as account linking and deletion.
          </li>
        </List>
      </Section>

      <Section heading="Permissions the app asks for">
        <List>
          <li>
            <strong>Camera and microphone</strong> — to record the memory. Only
            while you are recording.
          </li>
          <li>
            <strong>Location, while you are using the app</strong> — to place a
            drop where you are standing, and to tell you how far you are from
            one left for you. TimeDrop does not track your location in the
            background.
          </li>
          <li>
            <strong>Photos</strong> — only for the pictures you choose to
            attach.
          </li>
          <li>
            <strong>Notifications</strong> — to tell you when a memory is ready.
          </li>
        </List>
      </Section>

      <Section heading="The clipboard">
        <p>
          Exactly once in the app&apos;s lifetime — on the very first launch
          after installation — TimeDrop looks at your clipboard, to pick up a
          share link left there by this website while you were on your way to
          the app store. If what it finds is not a TimeDrop link, it is
          discarded and never leaves your device. After that first check the app
          never reads your clipboard again.
        </p>
      </Section>

      <Section heading="How long we keep things">
        <p>
          Drops made with the free allowance are deleted one month after they
          open. Since a free drop can be set to open at most two months out,
          that is about three months from sealing to deletion, with a full month
          for the recipient to watch it.
        </p>
        <p>
          <strong>
            If you have ever paid us — a subscription or a single drop pack —
            this does not apply to you.
          </strong>{' '}
          From then on your free drops are kept like any other, permanently, and
          that does not change if you later cancel. We are not going to delete
          something belonging to someone who paid us, and we are not going to
          make that conditional on them still paying.
        </p>
        <p>
          Drops made with a paid drop are never purged on a schedule. Neither is
          anything you explicitly kept.
        </p>
      </Section>

      <Section heading="Deleting your account">
        <p>
          Settings → Delete account erases your account, your settings, the
          memories you created and the record of the ones you received, along
          with the stored media. It cannot be undone.
        </p>
        <Callout>
          Deleting your account also breaks every link you have already shared:
          the people you sent memories to will no longer be able to open them,
          including memories they have not seen yet.
        </Callout>
      </Section>

      <Section heading="Who else processes your data">
        <List>
          <li>
            <strong>Supabase</strong> — database, storage and authentication.
          </li>
          <li>
            <strong>RevenueCat</strong> — purchase validation.
          </li>
          <li>
            <strong>Apple and Google</strong> — payments, and sign-in if you
            link your account.
          </li>
          <li>
            <strong>Vercel</strong> — hosting for this website.
          </li>
        </List>
        <p>
          We do not sell your data, and we do not share it with advertisers.
        </p>
      </Section>

      <Section heading="No tracking on this website">
        <p>
          This site has no analytics, no advertising tags and no third-party
          scripts. The drop page reads the link in your browser and makes no
          network requests at all — which is also why the decryption key in the
          link never reaches us, even when you open a memory in a browser.
        </p>
      </Section>

      <Section heading="Your rights">
        <p>
          If you are in the European Economic Area or the United Kingdom, you
          have the right to access, correct, export or erase your personal data,
          to object to or restrict its processing, and to complain to your data
          protection authority. Erasure is available directly in the app; for
          anything else write to support@timedrop.app and we will respond within
          one month.
        </p>
        <p>
          Our legal bases are performing the contract with you (delivering the
          memories you send and receive), our legitimate interest in keeping the
          service secure and working, and your consent for device permissions
          and notifications — which you can withdraw at any time in your
          device&apos;s settings.
        </p>
      </Section>

      <Section heading="Children">
        <p>
          TimeDrop is not intended for children under 13, and we do not
          knowingly collect their data. If you believe a child has given us
          personal data, write to us and we will remove it.
        </p>
      </Section>

      <Section heading="Changes">
        <p>
          If we change this policy in a way that affects what we do with your
          data, we will update the date at the top and tell you in the app
          before the change takes effect.
        </p>
      </Section>
    </LegalPage>
  );
}
