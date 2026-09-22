# World Traveller Project

Idea by Antonis Karakonstantakis

Initial version made by Florian Kaltenbrunner

## What this is

World Traveller is a "Google Maps"-style platform where anyone can drop a
pin on a place they've visited and attach the photos they took there. It's
free to use, and was originally aimed at photographers who are great
behind the camera but don't have the marketing reach (or the travel
budget) to get their landscape and travel photography seen.

The project started as a desktop app and has since grown into a full
multi-user web application with accounts, an admin system, and social
features. Everything below explains, in plain language, what has actually
been built on top of the original idea.

---

## Where things stand today

### It's a real website now, not just a desktop app

The app runs as a website, hosted on Netlify and connected straight to
this GitHub repository: every time new code is pushed, the live site
rebuilds itself automatically within a couple of minutes, with no manual
upload step. Anyone can open it from a browser, on a computer or on a
phone (Android or iPhone alike), without installing anything. From a
phone's browser it can also be "added to the home screen" so it opens and
feels like a regular installed app, complete with its own icon.

Getting a Flutter project — which is normally a desktop/mobile app
framework — to build correctly on a web hosting service like Netlify
turned out to need its own small piece of plumbing (Netlify's servers
don't have Flutter installed by default, so a build plugin was added to
fetch it automatically on every deploy). That, plus a cleanup of the
Git history after a stray large file briefly broke pushing to GitHub,
are documented in detail in `INFRASTRUTTURA.md`, alongside everything
else that lives outside the code itself (Netlify settings, the Supabase
project, GitHub).

### Photos live in the cloud, not on one person's computer

Originally photos and their info were stored locally. Now everything —
the pins on the map, the photos themselves, and every person's account —
lives in a shared cloud database and file storage (Supabase). That's what
makes it a real multi-user platform: what one person uploads, everybody
else can immediately see.

### Real accounts, with usernames

Signing up now asks for a unique username, not just an email and
password — that username is what shows up next to every photo someone
posts, so a picture always has a face (or at least a name) attached to
it. People can rename themselves later from their account page, and can
also sign in with a Google account if they'd rather not set a password
at all.

### Only the person who posted a picture can touch it — plus admins

Every photo remembers who uploaded it. Editing or deleting a picture is
only allowed for whoever posted it originally — nobody can quietly change
or remove someone else's memory. On top of that there is now a proper
administrator role, granted through the database rather than hard-coded
to one fixed email address, so admin rights can be handed to (or taken
away from) any account without touching the code. Administrators can
step in and edit or delete anyone's content when needed, and have their
own panel inside the app to manage the whole community: they can see
every registered traveller, block an account (which signs that person
out immediately and keeps them from logging back in until unblocked), or
wipe everything a problematic account has posted.

Blocking is enforced live — if an admin blocks somebody who is actively
using the app at that exact moment, they get signed out within a second
or two, not just the next time they try to log in.

### Finding people, not just places

Beyond browsing the map, people can now search for other travellers by
their username, open their page to see everything they've posted, and
tap a "Contact" button to see how to reach them (their email address, in
a small popup, without exposing it anywhere public). Every photo's detail
view also shows who posted it, with a direct link to that person's page.

### Favouriting photos, and a "my memories" view

Every photo has a heart button to save it as a favourite, and there is a
dedicated screen listing everything a person has liked, as well as a
separate one showing only what they personally posted — useful for
finding your own uploads again without scrolling through everyone else's.

### The map itself got several practical fixes

Pins that aren't selected are now black instead of a pale colour, simply
so they're actually visible against the map underneath instead of
blending in. Adding more photos to a place that already has a pin now
goes through the exact same guided flow as creating a brand new memory
(confirm the spot on the map, choose the pictures, fill in the details),
instead of a shortcut that skipped the confirmation step. And if a photo
ever ends up mapped to the wrong city entirely, there is now a "Wrong
place?" button right in the edit screen that opens a small map to search
for and drop the pin on the correct spot — moving the whole place, and
every photo attached to it, at once.

The side panel that lists all the pictures for a selected place can now
expand much wider than before, so it's actually useful for browsing
instead of showing a couple of tiny thumbnails, and the arrow to expand
it is now a large, clearly visible button instead of a nearly invisible
sliver at the edge of the screen.

Opening a single photo now shows it much bigger, with a scrollable strip
of thumbnails alongside it for the other photos taken at that same place,
so jumping between them doesn't require going back to the map each time.

### Video support was removed

The original video player feature has been taken out entirely, along
with every related file and dependency, to keep the app focused on
photos.

### Everything is in English now

The interface was a mix of Italian and English in places; it has all
been rewritten in English throughout, including internal comments in the
code itself.

---

## Supported platforms today

Since the app is now a website, it effectively works anywhere a modern
browser runs — desktop, Android and iPhone included, the last two via a
regular mobile browser (with the option to add it to the home screen for
an app-like feel). The original native desktop builds (Windows, Linux)
and the idea of dedicated native Android/iOS store apps are still
possible avenues if ever needed, but are a separate, larger effort from
publishing the web version, and haven't been pursued further for now.

---

## Project history (original notes, kept for context)

The section below is the original brief this project started from,
written when it was still a local desktop prototype. It's kept here as a
record of the starting point rather than as a description of how the app
works today.

> Currently, the Windows code structure uses a POINT (which likely
> represents the map coordinates where the photo is uploaded) and
> DIMENSIONS (height and width to define photo size). The platform also
> supports responsive scaling so images adapt to different screen sizes.

Original proposed improvements at the time (most of these have since
been implemented, in one form or another, as described above):

- Interactive map pins that highlight on click and open a gallery of
  everything pinned there.
- General UI/UX polish: typography, backgrounds, cleaner labels.
- Window controls (minimize/maximize/resize) for the desktop build.
- A "photo story" text area below the rating, for the story behind a
  shot.
- Turning the star rating's companion "mood rating" into something more
  emotional — "how this photo makes you feel".
- A visible scrollbar in the full-screen photo view.
- Better responsive form layouts across screen sizes.
- Clear titles per location and per photo.
- A proper "no results found" state for search.
- A location-tagging workflow when uploading: a text field plus an
  interactive map pin.

---

## Where to look for more detail

- `INFRASTRUTTURA.md` — everything that makes the app work but isn't
  visible in the code: the Netlify hosting setup, the GitHub repository
  quirks, and the full Supabase configuration (database tables,
  permissions, storage, authentication).
- `SETUP_GUIDE.md` — step-by-step instructions for setting all of the
  above up from scratch, including creating the first administrator
  account.
- `SUPABASE_SETUP.sql` and `SUPABASE_SETUP_V2.sql` — the exact database
  scripts to run, in order, on a fresh Supabase project.
