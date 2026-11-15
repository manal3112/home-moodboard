// Home Moodboard AI: room briefs and "Suggest details" for new items.
// Runs as a Supabase Edge Function so the Anthropic API key never reaches the browser.
// Only people on the AI access list can call it (the can_use_ai() rule from update-3.sql).
//
// Setup (once): add the secret ANTHROPIC_API_KEY in Supabase → Edge Functions → Secrets,
// then deploy with:  supabase functions deploy ai --no-verify-jwt --project-ref <your project ref>
// (--no-verify-jwt because the membership check below verifies the caller itself.)

import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";

const MODEL = "claude-opus-5-5";
const BUCKET = "moodboard";
const MAX_BRIEF_IMAGES = 20;
const PRIO: Record<string, string> = { must: "Must-have", nice: "Nice-to-have", avoid: "Avoid" };
const KIND: Record<string, string> = { instagram: "Instagram post", image: "Photo", sketch: "Sketch", link: "Link", note: "Note" };

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

class UserError extends Error {}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const key = req.headers.get("apikey") || Deno.env.get("SUPABASE_ANON_KEY") || "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, key, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Only people on the AI access list (public.ai_users, managed by the board owner) may use the AI.
    const { data: allowed, error: accessErr } = await sb.rpc("can_use_ai");
    if (accessErr) return json({ error: "AI access isn't set up yet. Run update-3.sql in Supabase, then try again." }, 403);
    if (!allowed) return json({ error: "Your account doesn't have AI access. Ask the board owner to turn it on under Rooms & people." }, 403);
    if (!Deno.env.get("ANTHROPIC_API_KEY")) {
      return json({ error: "The AI key hasn't been added yet. In Supabase open Edge Functions → Secrets and add ANTHROPIC_API_KEY." }, 503);
    }
    const { data: userData } = await sb.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
    const email = (userData.user?.email ?? "").toLowerCase();

    const body = await req.json();
    if (body?.action === "autofill") return json(await autofill(body));
    if (body?.action === "brief") return json(await brief(sb, body, email));
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: friendlyError(e) }, e instanceof UserError ? 400 : 500);
  }
});

function friendlyError(e: unknown): string {
  if (e instanceof UserError) return e.message;
  if (e instanceof Anthropic.AuthenticationError) return "The Anthropic API key isn't valid. Check ANTHROPIC_API_KEY in Supabase → Edge Functions → Secrets.";
  if (e instanceof Anthropic.PermissionDeniedError) return "The Anthropic account doesn't allow this request. Check billing and credits at console.anthropic.com.";
  if (e instanceof Anthropic.RateLimitError) return "The AI is busy right now. Try again in a minute.";
  if (e instanceof Anthropic.BadRequestError) return "The AI couldn't process this request: " + e.message;
  if (e instanceof Anthropic.APIError) return `The AI service had a problem (${e.status}). Try again shortly.`;
  return e instanceof Error ? e.message : String(e);
}

const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY

type Schema = Record<string, unknown>;

/** One structured-output call to Claude, with automatic retry on a fallback model if Claude declines. */
async function ask(opts: {
  system: string;
  content: Anthropic.Beta.BetaContentBlockParam[];
  schema: Schema;
  effort: "low" | "medium" | "high";
}): Promise<Record<string, unknown>> {
  const stream = anthropic.beta.messages.stream({
    model: MODEL,
    max_tokens: 32000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: opts.system,
    output_config: { effort: opts.effort, format: { type: "json_schema", schema: opts.schema } },
    messages: [{ role: "user", content: opts.content }],
  });
  const msg = await stream.finalMessage();
  if (msg.stop_reason === "refusal") throw new UserError("The AI declined to answer this one.");
  if (msg.stop_reason === "max_tokens") throw new UserError("The answer was too long. Try again, or split the room into fewer items.");
  const text = msg.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  try {
    return JSON.parse(text);
  } catch {
    throw new UserError("The AI's answer came back in an unexpected format. Try again.");
  }
}

const strList = { type: "array", items: { type: "string" } };

/* ---------------- Suggest details for an item being added ---------------- */
async function autofill(body: {
  image?: { media_type: string; data: string };
  context?: string;
  rooms?: string[];
  types?: string[];
}) {
  const rooms = (body.rooms ?? []).slice(0, 50).map(String);
  const types = (body.types ?? []).slice(0, 50).map(String);
  const content: Anthropic.Beta.BetaContentBlockParam[] = [];
  const img = body.image;
  if (img?.data && ["image/jpeg", "image/png", "image/webp", "image/gif"].includes(img.media_type)) {
    if (img.data.length > 6_000_000) throw new UserError("That image is too large to analyse.");
    content.push({ type: "image", source: { type: "base64", media_type: img.media_type as "image/jpeg", data: img.data } });
  }
  const ctx = String(body.context ?? "").slice(0, 4000);
  if (!content.length && !ctx.trim()) throw new UserError("Add a photo, a screenshot or some text first, so the AI has something to look at.");
  content.push({
    type: "text",
    text: [
      "Suggest details for this item on our home moodboard.",
      ctx ? `What we know about it:\n${ctx}` : "",
      `Rooms (pick exactly one, or "Whole home"): ${[...rooms, "Whole home"].join(" | ")}`,
      `Types (pick exactly one, or "" if none fits): ${types.join(" | ")}`,
    ].filter(Boolean).join("\n\n"),
  });
  const out = await ask({
    system:
      "You help a family in Ahmedabad, India, keep a moodboard for the interior designers of their new apartment. " +
      "Given a photo, screenshot or link, describe what it shows in the words an interior designer would use. " +
      "title: a short name for the object or idea, 2-6 words, like 'Cane-back teak dining chair' (no quotes, no trailing period). " +
      "why: one or two sentences on what is appealing about it - form, material, colour, craft technique, proportion - written in first person plural ('We like...'). " +
      "Only describe what you can actually see or read. If the image is mostly unreadable, say so briefly in why.",
    content,
    schema: {
      type: "object",
      properties: { title: { type: "string" }, room: { type: "string" }, type: { type: "string" }, why: { type: "string" } },
      required: ["title", "room", "type", "why"],
      additionalProperties: false,
    },
    effort: "low",
  });
  return out;
}

/* ---------------- Room brief ---------------- */
type Item = {
  id: string; kind: string; title: string; url: string | null; note: string; room_id: string | null; type: string | null;
  priority: string; image_path: string | null; created_by: string | null; created_at: string; updated_at: string;
  meta?: { preview?: { title?: string; description?: string }; markup_of?: string } | null;
};
type Comment = { id: string; item_id: string; author: string; body: string; parent_id?: string | null; created_at: string };

async function brief(sb: SupabaseClient, body: { room_id?: string | null }, email: string) {
  const roomId = body.room_id || null;
  const [{ data: rooms }, { data: members }] = await Promise.all([
    sb.from("rooms").select("id,name"),
    sb.from("members").select("email,name"),
  ]);
  const roomName = roomId ? rooms?.find((r) => r.id === roomId)?.name : "Whole home";
  if (!roomName) throw new UserError("That room no longer exists.");
  const nameOf = (e: string | null) => {
    const m = members?.find((x) => x.email === (e ?? "").toLowerCase());
    return (m?.name && String(m.name).trim()) || (e ?? "someone").split("@")[0];
  };

  let q = sb.from("items").select("*").order("created_at", { ascending: false });
  q = roomId ? q.eq("room_id", roomId) : q.is("room_id", null);
  const { data: itemsRaw, error } = await q;
  if (error) throw error;
  const items = (itemsRaw ?? []) as Item[];
  if (!items.length) throw new UserError(`There's nothing in ${roomName} yet.`);
  const order = { must: 0, nice: 1, avoid: 2 } as Record<string, number>;
  items.sort((a, b) => (order[a.priority] ?? 1) - (order[b.priority] ?? 1) || b.created_at.localeCompare(a.created_at));

  const { data: commentsRaw } = await sb.from("comments").select("*").in("item_id", items.map((i) => i.id)).order("created_at");
  const comments = (commentsRaw ?? []) as Comment[];

  // Signed links (10 minutes) let Claude fetch the private photos directly.
  const withImg = items.filter((i) => i.image_path && /\.(jpe?g|png|webp|gif)$/i.test(i.image_path)).slice(0, MAX_BRIEF_IMAGES);
  const urls = new Map<string, string>();
  if (withImg.length) {
    const { data } = await sb.storage.from(BUCKET).createSignedUrls(withImg.map((i) => i.image_path!), 600);
    for (const d of data ?? []) if (d.signedUrl && d.path) urls.set(d.path, d.signedUrl);
  }
  const titles = new Map(items.map((i) => [i.id, i.title || i.meta?.preview?.title || KIND[i.kind] || "item"]));

  const content: Anthropic.Beta.BetaContentBlockParam[] = [{
    type: "text",
    text: `Here is everything on our moodboard for: ${roomName}. There are ${items.length} items` +
      (items.length > withImg.length && withImg.length === MAX_BRIEF_IMAGES ? ` (pictures included for the first ${MAX_BRIEF_IMAGES})` : "") + ".",
  }];
  items.forEach((it, n) => {
    const lines = [
      `ITEM ${n + 1}: "${titles.get(it.id)}"`,
      `${KIND[it.kind] ?? it.kind} · ${PRIO[it.priority] ?? it.priority}${it.type ? " · " + it.type : ""} · added by ${nameOf(it.created_by)}`,
    ];
    if (it.meta?.markup_of) lines.push(`This is a marked-up drawing on "${titles.get(it.meta.markup_of) ?? "another item"}".`);
    if (it.kind === "note") lines.push(`Note: ${it.note}`);
    else if (it.note) lines.push(`Why we like it: ${it.note}`);
    if (it.meta?.preview?.title || it.meta?.preview?.description) lines.push(`Link preview: ${[it.meta.preview.title, it.meta.preview.description].filter(Boolean).join(" - ")}`);
    if (it.url) lines.push(`Link: ${it.url}`);
    if (it.kind === "instagram") lines.push(urls.has(it.image_path ?? "") ? "(The picture below is a screenshot of the Instagram post.)" : "(Instagram post: no screenshot available, so judge it only from the notes.)");
    const cs = comments.filter((c) => c.item_id === it.id);
    if (cs.length) lines.push("Comments:\n" + cs.map((c) => `${c.parent_id ? "  ↳ " : "- "}${nameOf(c.author)}: ${c.body}`).join("\n"));
    content.push({ type: "text", text: lines.join("\n") });
    const u = it.image_path ? urls.get(it.image_path) : undefined;
    if (u) content.push({ type: "image", source: { type: "url", url: u } });
  });
  content.push({ type: "text", text: `Write the brief for ${roomName}.` });

  const out = await ask({
    system:
      "You help a family in Ahmedabad, India, brief the interior architects designing their new apartment. " +
      "They collect inspiration on a shared moodboard: photos, Instagram screenshots, sketches, links and notes, each marked Must-have, Nice-to-have or Avoid, with comments from the family and the studio. " +
      "Turn one room's items into a clear brief the architects can act on. Look closely at the pictures: name furniture types, materials, finishes, colours, patterns, craft techniques (e.g. block print, cane, jaali, inlay) and lighting. " +
      "Rules: use only what is on the board; give Must-haves the most weight; treat Avoid items as things to steer clear of; " +
      "when you refer to a specific item, use its title in quotes; point out contradictions between items or comments; " +
      "put unresolved questions from the comments in open_questions. Each list point is one short sentence. Keep each list to the points that matter (usually 2-6). " +
      "Leave a list empty rather than inventing content. overview is 2-4 sentences in plain English.",
    content,
    schema: {
      type: "object",
      properties: {
        overview: { type: "string" },
        style: strList,
        materials: strList,
        must_haves: strList,
        avoid: strList,
        open_questions: strList,
      },
      required: ["overview", "style", "materials", "must_haves", "avoid", "open_questions"],
      additionalProperties: false,
    },
    effort: "medium",
  });

  const latest = items.reduce((m, i) => (i.updated_at > m ? i.updated_at : m), "");
  const value = { ...out, room: roomName, generated_at: new Date().toISOString(), by: email, item_count: items.length, latest };
  const { error: saveErr } = await sb.from("settings").upsert({ key: "brief:" + (roomId ?? "home"), value, updated_at: value.generated_at });
  if (saveErr) throw saveErr;
  return value;
}
