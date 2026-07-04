# question_8.md — Iteration 8 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_8_done.md` (closed), and
create `question_9.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 7 shipped in **v0.7.3**: LAN auto-sync (same-Wi-Fi devices merge
automatically, optional pairing code), the reader bookmark button +
mid-screen text anchors (online/offline positions align now), back-press
exit confirmation, 5 new app colors, and a fully clean `flutter analyze`.

---

## A. Your v0.7.3 testing findings

The two headline features need two-device testing:

- **LAN sync**: enable on both devices (Settings → LAN Sync), same Wi-Fi.
  They should merge within ~15s of both being open; "Sync Now" forces an
  announce. Try with and without a pairing code. On iOS accept the
  local-network prompt. Note: phone hotspots often block device-to-device
  traffic ("client isolation") — a normal router is the fair test.
- **Bookmarks**: read online, tap the bookmark button, then open the same
  work offline (and vice versa) — it should land on the same words at
  mid-screen. Also check History reflects the bookmarked chapter right away.

→ ANSWER:

---

## B. LAN sync follow-ups — what should v2 do?

- [ ] **A. Nothing yet — validate v1 first (Recommended: the discovery/
      merge core needs real-network testing before layering more on).**
- [ ] B. "Add device by IP" fallback for networks that block UDP broadcast
      (the hook `syncWithPeer` already exists).
- [ ] C. Show discovered devices live in Settings (peer list with last-seen).
- [ ] D. Sync downloaded chapter files too, not just metadata/progress
      (bigger transfers; needs progress UI).

→ ANSWER:

---

## C. Reader/bookmark polish

- [ ] **A. Nothing — see how the mid-screen anchor feels first
      (Recommended).**
- [ ] B. Multiple named bookmarks per work (list + jump), not just the
      single reading position.
- [ ] C. Show a subtle flash/highlight on the restored paragraph so you can
      see where you left off.
- [ ] D. Ideas of yours (describe below).

→ ANSWER:

---

## D. Anything else?

→ ANSWER:
