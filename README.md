# Home Moodboard

A shared board for the design studio: live Instagram posts you can scroll and play, photos and screenshots, sketches and photo markups, links, and notes. Everything is filtered by room, type and priority, and everyone can comment. You add and edit everything from the page itself. No code changes are needed after setup.

Files:

- `index.html`: the whole app (one file, no build step)
- `schema.sql`: the database, file storage and access rules for Supabase (for a new setup)
- `supabase/functions/ai/index.ts`: the AI helper (room briefs and "Suggest details"), run by Supabase so the AI key stays private
- `update-2.sql`: a one-time update for boards set up before documents, the floor plan and replies were added
- `update-3.sql`: a one-time update that adds upvotes and the AI access list

## Try it first (2 minutes)

Run a local server in this folder and open it:

```
python3 -m http.server 8000
# then open http://localhost:8000
```

With no Supabase details filled in, the board runs in **demo mode**: everything is saved only in that browser. Instagram embeds need the page served over http(s), so opening the file directly (file://) won't show them.

## Set up for sharing (about 30 minutes, once)

### 1. Create the Supabase project
1. Sign up at supabase.com and create a new project (the free plan is plenty). Pick a region close to you.
2. Open **SQL Editor → New query**. Paste all of `schema.sql`, change `YOUR_EMAIL@example.com` at the bottom to your email, and click **Run**.
3. Open **Project Settings → API Keys**. Copy the **Project URL** and the **publishable key** (older projects call it the "anon public" key).
4. At the top of `index.html`, fill in:
   ```js
   SUPABASE_URL: "https://xxxx.supabase.co",
   SUPABASE_KEY: "sb_publishable_...",
   ```
   The publishable key is meant to be public. The database rules only let people on your member list read or change anything.

### 2. Make sign-in emails reach the studio
Supabase's built-in email sender only delivers to members of your Supabase team, and only a few emails an hour. To email the architects, add your own sender under **Authentication → Emails → SMTP Settings**. The quickest options:

- **Gmail**: turn on 2-step verification, create an App Password (Google Account → Security → App passwords). In Supabase use host `smtp.gmail.com`, port `465`, username = your Gmail address, password = the app password, sender = your Gmail address.
- **Brevo** (free, 300 emails a day): create an account, verify your sender email, then copy its SMTP host, login and key into Supabase.

### 3. Put the page online
Any static host works. Two easy ones:

- **Netlify Drop**: go to app.netlify.com/drop and drag this folder in. You get a URL like `https://something.netlify.app`. Rename the site in its settings if you like.
- **GitHub Pages**: push the folder to a repo, then Settings → Pages → deploy from the main branch.

### 4. Tell Supabase where the site lives
In **Authentication → URL Configuration**:
- **Site URL**: your hosted URL, e.g. `https://our-home-board.netlify.app`
- **Redirect URLs**: add the same URL, plus `http://localhost:8000` if you want to test locally

### 5. Sign in and invite the studio
1. Open your hosted URL, enter your email and click the link you receive.
2. Click **Rooms & people**, add each architect's email, then **Copy link** and send it to them.
3. They enter their email on the page, click the link in their inbox, and they're in.

## Updating a board that's already set up

If your board was set up before November 2026, run the updates once, in order: in Supabase open **SQL Editor → New query**, paste all of `update-2.sql`, click **Run**, then do the same with `update-3.sql`. Until then the board shows a yellow banner naming the file still to run, and the features that need it stay switched off. Everything else keeps working.

## AI features (optional)

Two buttons use Claude (Anthropic's AI):

- **✨ Room brief**: pick a room (or open **By room**) and click it. The AI reads that room's pictures, notes and comments and writes a one-page brief for the studio: style and mood, colours and materials, must-haves, things to avoid, and open questions. It's saved for everyone; click **Rewrite brief** when the room changes, and **Copy as text** to paste it into WhatsApp or an email.
- **✨ Suggest details**: in the add or edit form, it fills the empty title, room, type and "why I like it" fields from the picture.

The AI can't see inside Instagram posts (they're Instagram's own frame), so it uses their screenshots and your notes. Attach screenshots to the posts that matter.

**Who can use it:** only people ticked **AI** under **Rooms & people**. At first that's just the board owner (the first email added in `schema.sql`), and only the owner can tick or untick people. The AI helper itself checks this list, so hiding the buttons isn't the only protection. Everyone can read a saved brief.

Setup, once:

1. At **console.anthropic.com**, create an account, add some credit under **Billing**, and create an API key under **API keys**. Keep the key private: don't paste it into chats, emails or `index.html`.
2. In Supabase, open **Edge Functions → Secrets**, add a secret named `ANTHROPIC_API_KEY`, and paste the key as its value.
3. Deploy the helper from this folder (needs the Supabase CLI and a one-time `supabase login`):
   ```
   supabase functions deploy ai --no-verify-jwt --project-ref bbbxjegctpvyxozgoxab
   ```
   `--no-verify-jwt` is intended: the helper checks that the caller is on the member list itself.

Cost: you pay Anthropic per use. Each brief or suggestion is a single request, and nothing runs unless someone clicks a button. To spend less, change `MODEL` at the top of `supabase/functions/ai/index.ts` to a smaller model and deploy again.

## Day-to-day use

- **+ Add** opens the form: Instagram, Photo, Sketch, Link or Note. Give each item a room, a type, a priority and a "why I like it" note.
- **Instagram**: paste one link, or a whole list of links (one per line) to add them all at once. Optionally attach a screenshot as a backup in case the post is later deleted or made private.
- **Paste anywhere**: paste an Instagram link, a web link or a copied image anywhere on the board, and the add form opens with it filled in. You can also drag image files onto the page.
- **Instagram cover**: to show a particular photo from a carousel (say photo 4), screenshot that photo, attach it, and tick **Show the screenshot as the cover**. Clicking the cover plays the live post.
- **Links**: the page's picture, title and description are fetched automatically. YouTube links play on the card.
- **Sketch**: draw freehand, or load a photo and mark it up with pen and highlighter.
- **Draw on this**: anyone can scribble on any post. The drawing is saved with that post (open the post to see its markups). For an Instagram post or a link without a picture, you'll be asked for a screenshot to draw on.
- **Comments**: reply to any comment, and type **@** to tag someone. **For you** (top of the page) lists comments that tag you, replies to you, and comments on things you added, with a red count for new ones.
- **Documents**: a shared folder for drawings, PDFs, quotes, spreadsheets and CAD files (up to 50 MB each). Drag files onto the page or click **+ Upload**. Anyone can open, rename, file under a room, or delete them.
- **Floor plan**: in **Rooms & people**, upload the layout as an image and mark where each room is. The plan then shows above the board: click a room to filter, and rooms with matching items light up when you filter by type, priority or search.
- **Board / Feed / By room**: Board is a grid; Feed is a single Instagram-style column; By room is a summary with a row of thumbnails per room, must-haves first.
- **Upvotes**: click **▲** on any card to upvote it (again to undo). Hover to see who upvoted. **Most upvoted** is the default sort and works within any filter. So that cards don't jump while you vote, the order updates when you press **↻ Re-sort** or reload.
- **New**: items other people added since your last visit get a "New" tag, and the **New** button filters to just those.
- **Rooms & people**: rename, reorder, add or remove rooms, upload the floor plan, manage who has access, and give each person a name for @tags.
- Changes appear for everyone within a second or two. No reload needed.

To change the title, subtitle or the list of item types, edit `CONFIG` at the top of `index.html` and upload the file again. That's the only part that needs a re-upload.

## Good to know

- Instagram's like and comment buttons inside an embedded post can't be removed: the embed is Instagram's own frame. Clicking them just opens instagram.com; nothing is posted from the board.
- Tagging someone doesn't email them (that would need a mail server). They see it under **For you** next time they open the board.
- Link previews are fetched through microlink.io, and pictures some sites block are fetched through wsrv.nl. Both see only the link's web address. The picture is then stored privately in your Supabase.
- Only posts from **public** Instagram accounts can be embedded. If a post goes private or is deleted, the card shows your backup screenshot instead.
- Ad blockers and some privacy settings (Safari's, Brave's) can block Instagram embeds. The card then shows a link and your screenshot.
- Images over ~1.5 MB are shrunk in the browser before upload. The free Supabase plan includes 1 GB of file storage, which is a few thousand photos.
- Photos and data are private: only signed-in members can see them, and image links expire after a week.
