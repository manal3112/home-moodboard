# Home Moodboard

A shared board for the design studio: live Instagram posts you can scroll and play, photos and screenshots, sketches and photo markups, links, and notes. Everything is filtered by room, type and priority, and everyone can comment. You add and edit everything from the page itself. No code changes are needed after setup.

Files:

- `index.html`: the whole app (one file, no build step)
- `schema.sql`: the database, file storage and access rules for Supabase

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

## Day-to-day use

- **+ Add** opens the form: Instagram, Photo, Sketch, Link or Note. Give each item a room, a type, a priority and a "why I like it" note.
- **Instagram**: paste one link, or a whole list of links (one per line) to add them all at once. Optionally attach a screenshot as a backup in case the post is later deleted or made private.
- **Paste anywhere**: paste an Instagram link, a web link or a copied image anywhere on the board, and the add form opens with it filled in. You can also drag image files onto the page.
- **Sketch**: draw freehand, or load a photo and mark it up with pen and highlighter. On any photo card, **Draw on this** saves a marked-up copy as a new card.
- **Board / Feed**: Board is a grid; Feed is a single Instagram-style column.
- **Rooms & people**: rename, reorder, add or remove rooms, and manage who has access.
- Changes appear for everyone within a second or two. No reload needed.

To change the title, subtitle or the list of item types, edit `CONFIG` at the top of `index.html` and upload the file again. That's the only part that needs a re-upload.

## Good to know

- Only posts from **public** Instagram accounts can be embedded. If a post goes private or is deleted, the card shows your backup screenshot instead.
- Ad blockers and some privacy settings (Safari's, Brave's) can block Instagram embeds. The card then shows a link and your screenshot.
- Images over ~1.5 MB are shrunk in the browser before upload. The free Supabase plan includes 1 GB of file storage, which is a few thousand photos.
- Photos and data are private: only signed-in members can see them, and image links expire after a week.
