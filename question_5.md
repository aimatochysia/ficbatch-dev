# question_5.md — Iteration 5 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_5_done.md` (closed), and
create `question_6.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 4 shipped: **sync-folder cross-device sync**, headless DOM tests for
the injector JS (which caught a real bug), the toolchain/dependency
modernization (Flutter 3.44.4, hive→hive_ce, http 1.x, notifications 19), and
release v1.2.0 prep with `RELEASE_NOTES.md`. You said you'd manually test the
release artifacts — this round is intentionally light so your testing drives it.

---

## A. Scope for iteration 5

- [ ] **A. Bug-fix round: whatever your manual testing of v1.2.0 surfaces, plus
      small leftovers (remaining tab widget tests, RadioGroup migration in
      advanced search) (Recommended — after four heavy iterations the highest
      value is stabilizing what shipped against real-device feedback.)**
- [ ] B. Mobile sync folder: Android SAF folder access so phones can join the
      sync folder directly (desktop-only today).
- [ ] C. Start the Rust/iroh P2P sync spike from the research addendum.
- [ ] D. Something else (describe below).

→ ANSWER:

---

## B. Report your manual-testing findings

List anything broken/odd per platform (Android / Windows / Linux / macOS /
iOS), ideally with steps. I'll triage and fix in priority order.

→ ANSWER:

---

## C. Sync-folder polish (if you tested it)

- [ ] **A. Works as-is; no changes needed yet (Recommended default until your
      testing says otherwise.)**
- [ ] B. Add sync-on-app-focus (re-import when the window regains focus, not
      just at launch).
- [ ] C. Add a conflict indicator / last-device-synced info in Settings.
- [ ] D. Problems found (describe below).

→ ANSWER:

---

## D. Anything else?

→ ANSWER:
