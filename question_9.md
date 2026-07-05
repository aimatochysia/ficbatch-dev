# question_9.md — Iteration 9 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_9_done.md` (closed), and
create `question_10.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 8 shipped in **v0.7.5**: in-app update checking on every platform
(launch prompt + Settings), the LAN Sync nearby-device list with tap-to-sync
and downloaded-work transfer, the visible red bookmark dot + jump button,
and the Windows installer's New Folder button.

---

## A. Your v0.7.5 testing findings

Worth hitting this round:

- **In-app updater**: Settings → Updates → "Check for Updates Now" on
  v0.7.5 should say you're current; when the next release exists it should
  offer the right installer. (Android: this update from an older *signed*
  build should finally install in place — one last uninstall only if you're
  coming from a pre-v0.7.2 unsigned build.)
- **LAN sync**: do both devices appear under "Nearby devices"? Does tapping
  one sync immediately? Does a work downloaded on device A open offline on
  device B after a sync?
- **Bookmark dot**: is the red dot visible at your saved spot, and does the
  arrow-down button jump back to it (online and offline)?

→ ANSWER:

---

## B. Ideation — the full catalog (tick any; effort noted)

From a fresh pass over the code and views. **Recommended bundle first.**

### Daily-reading comfort (Recommended as the iteration-9 core)
- [ ] **B1. "Continue Reading" card on Home** — last-opened work with a
      progress bar, one tap straight into the reader. The data
      (`lastUserOpened`, progress) already exists; Home currently only shows
      stats + batch import. *(low effort, highest daily value)*
- [ ] **B2. Library filters** — filter chips: downloaded / favorites /
      has-update / completed + by fandom/rating from stored tags. Tags are
      stored but there's no way to filter by them. *(medium)*
- [ ] **B3. Reading status per work** — To read / Reading / Finished /
      Dropped label (beyond the favorite star), settable from the card menu,
      filterable, synced like everything else. *(medium)*
- [ ] **B4. Auto-hide reader buttons** — the reader now stacks 5 floating
      buttons; hide them while scrolling, reveal on tap, for immersive
      reading. *(medium)*
- [ ] **B5. Safety backup before merges** — snapshot the library JSON to a
      backups folder before any import/replace/reset, keep the last 5.
      Cheap insurance now that three sync paths write to the store. *(low)*

### Capability unlocks
- [ ] B6. **Restricted-works support** — downloads/metadata use plain HTTP
      with no cookies, so login-restricted works always fail. Pass the
      browse webview's AO3 session cookies to the downloader/parser: log in
      once in Browse, restricted works then download fine. *(medium-high,
      biggest capability gap vs. a browser)*
- [ ] B7. **EPUB export/share** — AO3 serves EPUBs at a known URL; add
      "Save as EPUB" per work (and bulk) so the library opens in other
      reader apps. *(low-medium)*
- [ ] B8. **Series support** — parse AO3 series metadata, group/sort by
      series in the library. *(medium)*
- [ ] B9. Auto-download new chapters when an update is detected (for
      auto-download categories), not just notify. *(low-medium)*
- [ ] B10. Kudos from the reader (needs B6's cookies). *(medium)*

### Reader extras
- [ ] B11. Multiple named bookmarks per work (list + jump + delete) on top
      of the anchor system. *(medium)*
- [ ] B12. Tap zones / volume keys to page up/down + a chapter progress %
      indicator. *(medium)*
- [ ] B13. Read-aloud TTS. *(high)*

### Sync polish
- [ ] B14. Encrypt LAN sync frames (key derived from the pairing code) —
      exports currently cross the Wi-Fi in plaintext. *(medium)*
- [ ] B15. Sync status surface — one Home/app-bar indicator: last folder +
      LAN sync, tap to sync everything now. *(low)*
- [ ] B16. Updates badge on the bottom-nav Updates tab. *(low)*

### Engineering
- [ ] B17. Extract the reader's anchor/marker JS to `assets/js` and test it
      with jsdom (like the listing injector) — the trickiest code in the app
      currently has zero direct tests. *(medium, recommended alongside any
      reader work)*
- [ ] B18. In-app diagnostics screen (recent log ring buffer, copy button) —
      makes your bug reports one screenshot instead of guesswork. *(low)*
- [ ] B19. Refresh onboarding to mention LAN sync/updater (it predates
      both). *(low)*

→ ANSWER (tick above and/or write):

---

## C. Anything else?

→ ANSWER:
