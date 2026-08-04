import LegalPage, { Section, Callout, List } from './LegalPage';

// See the note at the top of PrivacyPage.jsx — same rules apply. The billing
// section mirrors what the paywall actually sells (monthly + annual
// subscription, consumable drop packs), and the retention section must stay in
// step with migrations 0024 and 0031.
//
// [[LEGAL_ENTITY]] / [[REGISTERED_ADDRESS]] / [[GOVERNING_LAW]] / [[COURTS]]
// are the only deliberate placeholders. Grep for `[[` before publishing.
export default function TermsPage() {
  return (
    <LegalPage title="Terms of Service" updated="3 August 2026">
      <Section heading="The agreement">
        <p>
          These terms are between you and [[LEGAL_ENTITY]],
          [[REGISTERED_ADDRESS]] (&ldquo;we&rdquo;, &ldquo;us&rdquo;). By using
          TimeDrop you accept them. If you do not, please do not use the app.
        </p>
        <p>
          You must be at least 13 years old to use TimeDrop, and old enough to
          agree to a contract where you live.
        </p>
      </Section>

      <Section heading="What TimeDrop does">
        <p>
          TimeDrop stores a video, photos and a note, encrypted, and releases
          them to a person you choose once two conditions are met: a date you
          set has arrived, and that person is physically at the place you chose.
          How we handle the data is set out in our{' '}
          <a href="/privacy" className="text-[var(--color-primary)] hover:underline">
            Privacy Policy
          </a>
          .
        </p>
      </Section>

      <Section heading="Your content">
        <p>
          What you record stays yours. You give us only the permission we need
          to run the service: to store your encrypted memory and deliver it to
          the recipient you chose. We do not claim any other right to it, we do
          not use it to promote TimeDrop, and — with the one exception described
          in the Privacy Policy — we could not read it if we wanted to.
        </p>
        <p>
          You are responsible for what you send. By sealing a drop you confirm
          you have the right to record and share it, including the consent of
          anyone in it.
        </p>
      </Section>

      <Section heading="What you may not do">
        <List>
          <li>
            send anything unlawful, harassing, threatening, or sexual content
            involving minors
          </li>
          <li>use TimeDrop to stalk, intimidate or track another person</li>
          <li>
            attempt to open memories that were not left for you, or to break the
            unlock conditions
          </li>
          <li>
            attack, overload or reverse-engineer the service, or automate
            accounts
          </li>
        </List>
        <p>
          We may suspend or delete an account that does these things, and we
          will cooperate with law enforcement where we are required to.
        </p>
      </Section>

      <Section heading="Encryption, and what it costs you">
        <Callout>
          Because your memory is encrypted with a key we do not hold, we cannot
          recover it for you. If the share link is lost, the memory cannot be
          opened by anyone — not by the recipient, not by you, and not by us.
          There is no password reset for a drop. Keep the link until it has been
          opened.
        </Callout>
        <p>
          The same is true of your account: if you never link it to Apple or
          Google and you lose the device, the memories on it are gone. The app
          warns you about this, and linking takes a few seconds.
        </p>
      </Section>

      <Section heading="Drops, subscriptions and payment">
        <p>
          Sending a memory costs one drop. New accounts get a free allowance.
          Beyond that you can buy drops in packs, or subscribe to TimeDrop Pro,
          which grants a set number of drops each month.
        </p>
        <List>
          <li>
            Subscriptions renew automatically until cancelled, and are billed
            through your App Store or Google Play account. Cancel any time in
            the store&apos;s subscription settings — cancelling stops the next
            renewal and leaves the current period running.
          </li>
          <li>
            Drop packs are one-off purchases. Bought drops do not expire.
          </li>
          <li>
            All payments are handled by Apple or Google. Refunds follow their
            policies and are requested from them, not from us.
          </li>
          <li>
            Prices are shown in the app in your local currency and may change;
            a change never applies to a purchase you have already made.
          </li>
        </List>
      </Section>

      <Section heading="How long memories are kept">
        <p>
          Memories sent using the free allowance are deleted one month after
          they open. Memories sent using a paid drop are kept, and once you have
          made any purchase your free drops are kept as well, permanently,
          including after you cancel a subscription. The full rule is in the{' '}
          <a href="/privacy" className="text-[var(--color-primary)] hover:underline">
            Privacy Policy
          </a>
          .
        </p>
      </Section>

      <Section heading="Availability">
        <p>
          We work to keep TimeDrop running, but we do not promise it will be
          available without interruption, that a memory will unlock at a precise
          second, or that GPS will behave in every building and every street.
          The service is provided as it is, without warranties beyond those your
          local law gives you and we cannot exclude.
        </p>
        <p>
          Nothing in these terms limits our liability for death or personal
          injury caused by our negligence, for fraud, or for anything else that
          cannot be limited by law. Subject to that, our total liability to you
          is limited to what you have paid us in the twelve months before the
          claim.
        </p>
      </Section>

      <Section heading="Ending it">
        <p>
          You can stop using TimeDrop at any time and delete your account from
          Settings. Deleting your account also stops every link you have already
          shared from working. We may end your access if you break these terms.
        </p>
      </Section>

      <Section heading="Changes to these terms">
        <p>
          If we change these terms materially we will tell you in the app before
          the change takes effect. Continuing to use TimeDrop afterwards means
          you accept the new version.
        </p>
      </Section>

      <Section heading="Law and contact">
        <p>
          These terms are governed by the law of [[GOVERNING_LAW]], and disputes
          go to the courts of [[COURTS]]. If you are a consumer, this does not
          take away the protection of the mandatory law of the country you live
          in.
        </p>
        <p>
          Questions:{' '}
          <a
            href="mailto:support@timedrop.app"
            className="text-[var(--color-primary)] hover:underline"
          >
            support@timedrop.app
          </a>
          .
        </p>
      </Section>
    </LegalPage>
  );
}
