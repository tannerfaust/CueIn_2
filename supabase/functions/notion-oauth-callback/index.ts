import { corsHeaders } from "../_shared/notion.ts";

const appCallbackURI = "cuein://notion/callback";

Deno.serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const source = new URL(req.url);
  const target = new URL(appCallbackURI);

  for (const key of ["code", "state", "error", "error_description"]) {
    const value = source.searchParams.get(key);
    if (value) target.searchParams.set(key, value);
  }

  if (!target.searchParams.has("code") && !target.searchParams.has("error")) {
    target.searchParams.set("error", "missing_oauth_callback_data");
  }

  return Response.redirect(target.toString(), 302);
});
