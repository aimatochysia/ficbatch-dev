# question_7.md — Iteration 7 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_7_done.md` (closed), and
create `question_8.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 6 shipped: the dead-code sweep (~500 lines removed; only the
explicitly future-use toolbar save button kept), the RadioGroup migration +
22 lint fixes, widget tests for the History/Updates/Library tabs, and the
**v0.7.1 release** (version 0.7.1+5, tag `v0.7.1`) which I triggered per your
answer — grab the installers from the Releases page.

---

## A. Your v0.7.1 testing findings

Per platform, with exact snackbar/error text where relevant. Things worth
hitting: sync folder on Android two-device (grant "All files access"),
placeholder repair (open an old "Work #123" record), app color + reading
themes, download failure messages, mouse popup clicks on Android.

→ ANSWER:

---

## B. Sync-folder verdict

- [ ] **A. Works — keep hourly periodic sync (Recommended if reliable).**
- [ ] B. Works — revert to launch-only + manual Sync Now.
- [ ] C. Add sync-on-focus too.
- [ ] D. Problems found (describe in A).

→ ANSWER:

---

## C. Remaining polish backlog — pick what I should do next round

- [ ] **A. Manual `use_build_context_synchronously` cleanup — the last 12 style
      lints, needs careful mounted-guard placement (Recommended: closes out
      the lint backlog entirely).**
- [ ] B. Reader/browse UX ideas of yours (describe below).
- [ ] C. Rust/iroh P2P sync spike (from the research doc).
- [ ] D. Nothing — purely react to my testing findings.

→ ANSWER:

---

## D. Anything else?

→ ANSWER:
