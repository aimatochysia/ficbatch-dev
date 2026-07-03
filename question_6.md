# question_6.md — Iteration 6 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_6_done.md` (closed), and
create `question_7.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 5 shipped: Android sync folder (all-files access + hourly debug
sync), the placeholder-metadata fix (root cause + repair on open and in sync),
the mouse click-through shield, randomized AO3 request jitter + 429 abort,
required-tags text hidden, dark-mode nav links un-boxed, 7 app color themes,
and 4 reading themes. Version is 1.3.0+4. **Builds are now manual-only** —
tell me when you want artifacts or a release and I'll trigger them.

---

## A. Scope for iteration 6

- [ ] **A. Verification round: I trigger an artifacts build now, you test
      iteration 5 on Android + Windows (especially: placeholder repair, sync
      folder on Android, themes, download error messages), and I fix what you
      find (Recommended — iteration 5 touched a lot of user-visible behavior;
      validating beats piling on more).**
- [ ] B. Quality round: remaining tab widget tests, RadioGroup migration,
      info-lint cleanup.
- [ ] C. Both A and B.
- [ ] D. Something else.

→ ANSWER:

---

## B. Report your testing findings

Per platform, with the exact snackbar/error text where relevant (downloads now
say *why* they fail — that text is the diagnosis).

→ ANSWER:

---

## C. Sync-folder verdict (after you try it on two devices)

- [ ] **A. Works — keep hourly periodic sync as the permanent cadence
      (Recommended if it proves reliable; it's cheap).**
- [ ] B. Works — but revert to launch-only + manual Sync Now (quieter).
- [ ] C. Add sync-on-focus too (re-import when the window regains focus).
- [ ] D. Problems found (describe below).

→ ANSWER:

---

## D. Cut a release?

Say the word and I'll trigger the full release workflow (all five platforms,
release notes) as v1.3.0. Until you do, nothing builds automatically.

- [ ] A. Yes — release v1.3.0 now.
- [ ] **B. After my testing round confirms iteration 5 (Recommended).**

→ ANSWER:

---

## E. Anything else?

→ ANSWER:
