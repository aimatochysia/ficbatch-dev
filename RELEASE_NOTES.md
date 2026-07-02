# FicBatch v1.2.0

The first release after the full review-and-overhaul cycle (iterations 1–4).
Everything below is new or fixed since the previous release.

## ✨ New features

- **Cross-device sync (Sync Folder)** — auto-export your library, reading
  progress and history to a folder of your choice and merge-import on launch;
  pair the folder with Syncthing/Dropbox/iCloud to sync every device.
  Exports now include reading history (format v2).
- **Library search, sort & multi-select** — search by title/author/tag; sort
  by recently added, title, last read, word count, or favorites first;
  long-press/select mode with bulk move, download and remove.
- **Favorites** — star works from cards or the context menu, sort favorites
  first.
- **Full reader settings** — line height, font family (serif/sans/mono),
  sepia reading theme, chapter-jump toggle; editable in-reader and from
  Settings, persisted everywhere.
- **Downloads settings** — pick/re-pick a download folder on desktop (with
  migration), global auto-download toggle, download throttle selector, and
  Clear All Downloads.
- **Native file dialogs** for library export/import (JSON paste box remains
  as a fallback).
- **First-run onboarding** with a replay option in Settings.
- **System theme mode** (follows your OS light/dark) alongside Light/Dark.
- **Data management** — Clear Reading History, and a typed-confirmation
  Reset App Data.

## 🐛 Fixes

- **Browse tab slow/blank screen** — the page now appears as soon as it
  loads (enhancements apply afterwards), a spinner always shows while
  loading, and a watchdog force-reveals if anything hangs.
- **Imported works finally carry full metadata** — tags, summary,
  word/chapter counts, kudos/hits/comments, published/updated dates (the
  metadata scraper previously returned only title/author).
- **Update sync hardened** — robust AO3 date parsing shared with the
  importer; sync also refreshes word counts, stats, summary and tags.
- **Android 13+ notifications** — runtime permission request plus manifest
  fixes so update notifications actually appear; background sync survives
  reboots.
- Removing a work from its last category no longer silently deletes it.
- Duplicate saves now notify "already in category" instead of silently
  re-saving.
- Reading history unified (one schema, capped at 500) and now shows the
  chapter you stopped at.

## 🧰 Under the hood

- Flutter **3.44.4** / Dart 3.12, modern dependencies (webview_flutter 4.14,
  flutter_local_notifications 19, http 1.x), storage migrated to the
  maintained **hive_ce** (existing data stays readable).
- CI now runs analyze + tests + headless DOM tests of the AO3 injector
  JS on every push; per-push artifact builds for Android/Windows/Linux.
- Web platform support removed — FicBatch's value is the local library and
  offline reading; for browsing only, AO3 itself is the web app.
- Deprecation cleanup (`withOpacity` → `withValues`, Material 3 defaults) and
  a much larger test suite (unit, widget, Hive round-trip, jsdom).

**Full changelog:** see the commit history of the
`claude/flutter-review-roadmap-160ll5` branch.
