// Unit tests for the webhook's pure helpers.
//
// These cover the parts most likely to break quietly: user resolution (a wrong
// answer silently drops a paid purchase), the timing-safe comparison, and
// timestamp parsing (a bad anchor breaks every future monthly grant).
//
// Run with: deno test supabase/functions/revenuecat-webhook/index_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { msToIso, resolveUserId, timingSafeEqual } from './index.ts';

const UUID = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

Deno.test('resolveUserId: uses app_user_id when it is a uuid', () => {
  assertEquals(resolveUserId({ app_user_id: UUID }), UUID);
});

Deno.test('resolveUserId: falls back to a uuid in aliases', () => {
  // The shape RevenueCat sends before the client has called logIn().
  assertEquals(
    resolveUserId({
      app_user_id: '$RCAnonymousID:8a9b0c1d',
      aliases: ['$RCAnonymousID:8a9b0c1d', UUID],
    }),
    UUID,
  );
});

Deno.test('resolveUserId: null when nothing maps to a Supabase user', () => {
  assertEquals(resolveUserId({ app_user_id: '$RCAnonymousID:8a9b0c1d' }), null);
  assertEquals(resolveUserId({}), null);
  assertEquals(resolveUserId({ app_user_id: 'not-a-uuid', aliases: ['also-not'] }), null);
});

Deno.test('resolveUserId: ignores a non-array aliases field', () => {
  assertEquals(resolveUserId({ app_user_id: 'x', aliases: 'nope' }), null);
});

Deno.test('timingSafeEqual: matches only identical strings', () => {
  assertEquals(timingSafeEqual('secret-value', 'secret-value'), true);
  assertEquals(timingSafeEqual('secret-value', 'secret-valuf'), false);
  // A shared prefix must not pass — the whole point of the comparison.
  assertEquals(timingSafeEqual('secret-value', 'secret'), false);
  assertEquals(timingSafeEqual('', ''), true);
  assertEquals(timingSafeEqual('a', ''), false);
});

Deno.test('msToIso: converts epoch millis and rejects anything else', () => {
  assertEquals(msToIso(0), '1970-01-01T00:00:00.000Z');
  assertEquals(msToIso(1785499029171), new Date(1785499029171).toISOString());
  assertEquals(msToIso(null), null);
  assertEquals(msToIso(undefined), null);
  assertEquals(msToIso('1785499029171'), null);
  assertEquals(msToIso(Number.NaN), null);
});
