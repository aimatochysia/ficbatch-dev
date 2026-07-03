# FicBatch v0.7.1

Follow-up to the overhaul release: cross-device sync on Android, fixes for
everything found in manual testing, personalization themes, and a leaner
codebase.

## ✨ New

- **Sync folder on Android** — pick a folder (grant "All files access" when
  prompted) and pair it with Syncthing/Dropbox to sync your library, reading
  progress and history with your desktop. Plus an hourly background sync
  while the app is open.
- **App Color themes** — seven Material 3 personalities (Violet, Ocean,
  Forest, Rose, Amber, Crimson, Mono) tinting the whole UI in light & dark.
- **Reading themes** — Sepia joined by Night (true black), Soft gray and
  Paper, in-reader and as a Settings default.

## 🐛 Fixed (from manual-testing reports)

- **Works saved too fast from browse** no longer end up as "Work #123 /
  Unknown" — the reader repairs placeholder metadata automatically on open,
  sync repairs it too, and progress saves can no longer overwrite good
  metadata with placeholders.
- **Physical mouse on Android**: clicking a popup menu item no longer
  clicks through into the website underneath.
- **History updates instantly** — the History tab live-updates, and closing
  the reader records your final chapter immediately.
- **Downloads tell you why they fail** (rate limit with wait time, deleted
  work, login-restricted work, network/file errors) instead of a generic
  "failed"; all AO3 requests now pace themselves with randomized delays and
  bulk downloads stop when AO3 asks to slow down (HTTP 429).
- The rating/warning symbol squares no longer show their text labels.
- Dark mode: navigation links lost their boxed dark-grey backgrounds.

## 🧰 Under the hood

- Dead-code sweep: ~500 lines of unused/superseded code removed.
- Deprecation cleanup incl. the new RadioGroup API; 22 style lints fixed.
- New widget tests for the History/Updates/Library tabs on a real Hive store.
- Builds are manual-only now (no auto-builds on every commit).

**Note for Android:** notifications need Android 13+; folder sync asks for
"All files access". iOS build requires iOS 14+.
