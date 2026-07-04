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

## B. What should iteration 9 focus on?

- [ ] **A. React to your testing findings only — the last two iterations
      added a lot of moving parts; stabilize before adding more
      (Recommended).**
- [ ] B. Library UX round 2 (e.g. tag filtering/search inside a work's tags,
      reading stats, collections beyond categories).
- [ ] C. Sync round 3 (conflict handling improvements, sync status
      indicator in the app bar, more files per LAN pass).
- [ ] D. Something else (describe below).

→ ANSWER:

---

## C. Anything else?

→ ANSWER:
