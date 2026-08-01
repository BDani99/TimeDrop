// Shared CORS handling.
//
// Native Flutter clients send no `Origin` header at all, so a missing origin
// is allowed. Browser callers are restricted to the TimeDrop web app, which is
// the only page that legitimately invokes these functions from a browser.
const ALLOWED_ORIGINS = [
  'https://time-drop-pink.vercel.app',
];

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin');

  // No Origin → a native app, not a browser. Nothing to restrict.
  if (!origin) {
    return {
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
    };
  }

  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

/// Returns a 204 pre-flight response, or null when this isn't a pre-flight.
export function handlePreflight(req: Request): Response | null {
  if (req.method !== 'OPTIONS') return null;
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}
