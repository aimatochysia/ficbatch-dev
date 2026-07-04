# FicBatch v0.7.5

Iteration 8: updates from inside the app, LAN sync you can see and that
carries your downloads, and a bookmark you can actually find again.

## ✨ New

- **In-app updates** — FicBatch now checks GitHub for a newer release on
  launch (turn it off in Settings → Updates) and asks before updating;
  "Check for Updates Now" is there too. It hands you the right installer
  for your platform, and installing over the previous version keeps your
  library and settings.
- **LAN Sync shows nearby devices** — Settings → LAN Sync lists every
  FicBatch it can see on your Wi-Fi (name, last seen, last synced). Tap a
  device to sync with it immediately.
- **LAN Sync moves your downloads too** — devices now trade downloaded
  works they're missing (25 per pass), so your other device reads offline
  without re-downloading from AO3.
- **The bookmark is visible now** — a small red dot sits in the left margin
  at your saved spot (after restore and after bookmarking), and a new
  arrow-down button jumps straight back to it.
- **Windows installer** — the folder picker finally has a New Folder button.

## 📌 Android update note

If updating still asks you to uninstall: that's the one-time signature
switch from the old unsigned builds. Uninstall once, install v0.7.5, and
every update after this installs in place with your data kept — including
through the new in-app updater.

**Notes:** notifications need Android 13+; folder sync asks for "All files
access"; iOS build requires iOS 14+.
