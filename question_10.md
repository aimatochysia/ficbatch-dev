# question_10.md — Iteration 10 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_10_done.md` (closed),
and create `question_11.md`. Recommended options are first, with
justification; if you skip a question I take the **(Recommended)** option.

Iteration 9 shipped (unreleased — say the word and I'll cut it as v0.7.6 or
any tag you prefer): library filter chips + tag picker, series support
(cards, Series sort; existing works pick it up on next sync),
auto-download of detected updates, rolling 5-slot backups with restore in
Settings, and auto-hiding reader buttons.

---

## A. Your testing findings

Worth hitting this round:

- **Filters**: chips + tag picker, combined with search and category tabs.
- **Series**: run a sync, then check cards show "Series · Part N" and the
  Series sort groups parts in order.
- **Auto-download**: enable an auto-download category (or the global
  toggle), sync a work with new chapters — the fresh copy should appear
  without a manual download.
- **Backups**: Settings → Backups after an import/sync; try a restore
  (it's undoable — a fresh backup is taken first).
- **Reader**: buttons vanish while scrolling and return ~1s after you stop.

→ ANSWER:

---

## B. Held-over ideas — pull any into iteration 10?

- [ ] **A. None — react to findings and stabilize (Recommended after two
      feature-heavy iterations).**
- [ ] B. Reading statuses (To read / Reading / Finished / Dropped) +
      status filter chips (the filter row is ready for it).
- [ ] C. Restricted-works support (pass the Browse login cookies to the
      downloader — the biggest remaining capability gap).
- [ ] D. EPUB export/share per work.
- [ ] E. "Continue Reading" card on Home.

→ ANSWER:

---

## C. New ideas from this round (Claude's picks — tick any)

- [ ] **C1. Uninstall-proof backups on Android (Recommended).** Backups
      currently live in app-private storage — an uninstall (like the
      signature switch you just did) deletes library AND backups. Option to
      keep snapshots in a user-visible folder (Documents/FicBatch, using
      the all-files permission folder sync already asks for). *(low)*
- [ ] **C2. Import from any AO3 listing URL.** Paste a bookmarks page /
      search / tag listing into batch import and it pulls every work id
      (paginated) — turns "populate my library from my AO3 bookmarks" into
      one paste. *(medium)*
- [ ] C3. Chapter delta in Updates — show "+2 chapters" (old vs new count
      is already stored) and make tapping a notification land on the
      Updates tab. *(low)*
- [ ] C4. Tag blocklist — never show works with chosen tags in browse
      listings and the library (classic fandom squick filter; the injector
      and filter row make this natural now). *(medium)*
- [ ] C5. Settings in sync — include reader prefs/theme/filters in export
      v3 so a new device restores *everything*, not just the library.
      *(low)*
- [ ] C6. New-device onboarding: "copy from a nearby device" step that
      drives LAN sync during first run instead of starting empty. *(medium)*
- [ ] C7. Reader find-in-work (search text within the open work, jump to
      matches — pairs with the anchor JS). *(medium)*
- [ ] C8. App icon/branding pass before the version creeps toward 1.0.
      *(low, one-time)*

→ ANSWER:

---

## D. Anything else?

→ ANSWER:
