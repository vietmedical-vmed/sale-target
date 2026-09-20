const ALLOWED_ORIGINS = [
  "https://vietmedical-vmed.github.io",
  "http://localhost:5173",
  "http://localhost:4173",
];

export function getAllowedOrigin(req: Request): string {
  const origin = req.headers.get("origin") ?? "";
  return ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
}

export function corsHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

export const cors = corsHeaders(ALLOWED_ORIGINS[0]);

export function json(body: unknown, status = 200, req?: Request) {
  const origin = req ? getAllowedOrigin(req) : ALLOWED_ORIGINS[0];
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}
