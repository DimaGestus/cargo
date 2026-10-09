import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const APP_ORIGIN = "https://dimagestus.github.io";
const APP_URL = "https://dimagestus.github.io/cargo/";
const WORKSPACE_ID = "4dc0b1f4-0870-49cc-acbd-52003431ba2a";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sign in first." }, 401);

  let body: { email?: string; category?: string };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid request." }, 400); }

  const email = String(body.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);

  const category = body.category ?? "transport";
  if (!["sales", "transport"].includes(category)) return json({ error: "Choose Sales or Transport." }, 400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: userResult, error: userError } = await callerClient.auth.getUser();
  if (userError || !userResult.user) return json({ error: "Your sign-in has expired. Sign in again." }, 401);
  const user = userResult.user;

  const { data: membership, error: memberError } = await admin
    .from("workspace_members")
    .select("workspace_id, role")
    .eq("workspace_id", WORKSPACE_ID)
    .eq("user_id", user.id)
    .maybeSingle();
  if (memberError) return json({ error: "Could not verify team access." }, 500);
  if (!membership || !["owner", "admin"].includes(membership.role)) {
    return json({ error: "Only a team administrator can invite colleagues." }, 403);
  }
  if (email === String(user.email || "").toLowerCase()) return json({ error: "That is already your account." }, 400);

  const { data: invite, error: inviteError } = await admin
    .from("workspace_invites")
    .insert({ workspace_id: WORKSPACE_ID, email, role: "dispatcher", employee_category: category, invited_by: user.id })
    .select("id")
    .single();
  if (inviteError) {
    if (inviteError.code === "23505") return json({ error: "There is already a pending invitation for that email." }, 409);
    return json({ error: "Could not create the team invitation." }, 500);
  }

  const { error: authInviteError } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: APP_URL });
  if (!authInviteError) return json({ ok: true, message: "Invitation sent." });

  // If this email already has a Supabase account, add that existing identity to the workspace.
  const { data: usersPage, error: listError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const existing = !listError ? usersPage.users.find((item) => String(item.email || "").toLowerCase() === email) : undefined;
  if (existing) {
    const { error: memberInsertError } = await admin.from("workspace_members").upsert({
      workspace_id: WORKSPACE_ID, user_id: existing.id, role: "dispatcher", employee_category: category, invited_by: user.id,
    }, { onConflict: "workspace_id,user_id", ignoreDuplicates: true });
    if (!memberInsertError) {
      await admin.from("workspace_invites").update({
        status: "accepted", accepted_by: existing.id, accepted_at: new Date().toISOString(),
      }).eq("id", invite.id);
      return json({ ok: true, message: "Existing account added to the team. Ask them to sign in with this email." });
    }
  }

  if (authInviteError.status === 429 || /rate|email|smtp|mail/i.test(authInviteError.message)) {
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: "invite", email, options: { redirectTo: APP_URL },
    });
    if (!linkError && link?.properties?.action_link) {
      return json({ ok: true, invitation_url: link.properties.action_link,
        message: "Email delivery is unavailable. Copy this personal invitation link and send it only to " + email + ". They can set their password and join your team." });
    }
  }
  await admin.from("workspace_invites").delete().eq("id", invite.id);
  return json({ error: "Invitation email failed: " + authInviteError.message }, authInviteError.status === 429 ? 429 : 400);
});