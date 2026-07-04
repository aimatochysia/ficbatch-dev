# FicBatch v0.7.3

Iteration 7: sync without wires, bookmarks that survive the online/offline
switch, and a fully clean codebase.

## ✨ New

- **LAN Sync** — turn it on (Settings → LAN Sync) on two devices on the same
  Wi-Fi and your library, reading progress and history merge automatically
  within seconds. No server, no internet, no shared folder needed. Set the
  same optional pairing code on both devices to keep other FicBatch users on
  the network out. iOS asks for local-network permission the first time.
- **Bookmark button in the reader** — tap the bookmark button to save the
  exact text at mid-screen as your position, instantly. The automatic
  tracking uses the same text anchor in the background, and restoring
  scrolls that text back to mid-screen — so your spot now lines up between
  the online and the downloaded copy of a work.
- **5 new app colors** — Sakura (pink), Mint (green), Indigo, Coral and
  Olive join the seven existing Material 3 themes.
- **Exit warning on mobile** — pressing back at the main screen asks before
  closing the app.

## 🧰 Under the hood

- The last 12 style lints are gone — `flutter analyze` is completely clean
  for the first time.
- New socket-level tests for the LAN sync handshake (merge + pairing-code
  rejection) against a real Hive store; 30 tests total.

**Note for Android:** notifications need Android 13+; folder sync asks for
"All files access". iOS build requires iOS 14+.
