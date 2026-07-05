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

## C. Anything else?

→ ANSWER:
