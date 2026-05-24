import {
  adminClient,
  corsHeaders,
  encryptToken,
  json,
  linearRequest,
  requireUser,
} from "../_shared/linear.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = adminClient();
    const user = await requireUser(req, admin);
    const { code, state } = await req.json().catch(() => ({}));
    if (!code || !state) {
      return json({ error: "Missing OAuth callback data" }, 400);
    }

    const { data: stateRow, error: stateError } = await admin
      .from("linear_oauth_states")
      .select("*")
      .eq("user_id", user.id)
      .eq("state", state)
      .is("consumed_at", null)
      .maybeSingle();
    if (stateError) return json({ error: stateError.message }, 500);
    if (!stateRow || new Date(stateRow.expires_at).getTime() < Date.now()) {
      return json({ error: "Invalid or expired OAuth state" }, 400);
    }

    const clientId = Deno.env.get("LINEAR_CLIENT_ID");
    const clientSecret = Deno.env.get("LINEAR_CLIENT_SECRET");
    if (!clientId || !clientSecret) {
      return json({ error: "Linear OAuth credentials are not configured" }, 500);
    }

    const tokenResponse = await fetch("https://api.linear.app/oauth/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: stateRow.redirect_uri,
        client_id: clientId,
        client_secret: clientSecret,
      }).toString(),
    });
    const tokenBody = await tokenResponse.json().catch(() => ({}));
    if (!tokenResponse.ok) {
      return json({ error: tokenBody?.error_description ?? tokenBody?.message ?? "Linear OAuth failed" }, 400);
    }

    const accessToken = tokenBody.access_token as string;
    const encrypted = await encryptToken(accessToken);

    // Fetch user and workspace details via Linear GraphQL API
    const viewerQuery = `
      query {
        viewer {
          id
          name
        }
        organization {
          id
          name
        }
      }
    `;
    const profile = await linearRequest<{ viewer: { id: string; name: string }; organization: { id: string; name: string } }>(
      accessToken,
      viewerQuery
    );

    const workspaceId = profile.organization.id;
    const workspaceName = profile.organization.name;
    const ownerUserId = profile.viewer.id;

    const { data: connection, error: upsertError } = await admin
      .from("linear_connections")
      .upsert({
        user_id: user.id,
        workspace_id: workspaceId,
        workspace_name: workspaceName ?? null,
        owner_user_id: ownerUserId ?? null,
        encrypted_access_token: encrypted.encryptedAccessToken,
        token_nonce: encrypted.tokenNonce,
        status: "active",
        last_error: null,
        disconnected_at: null,
      }, { onConflict: "user_id,workspace_id" })
      .select("id, workspace_id, workspace_name, status, last_synced_at")
      .single();
    if (upsertError) return json({ error: upsertError.message }, 500);

    await admin
      .from("linear_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", stateRow.id);

    return json({ connection }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
