# question_3.md — Iteration 3 decisions

**How this works:** Edit this file to answer. For each question, mark your choice
by putting an `x` in the `[ ]` next to a lettered option (e.g. `[x] B.`), or
write free text after `→ ANSWER:`. On your next commit I'll implement the agreed
scope, rename this file to `question_3_done.md` (closed — never reopened), and
create `question_4.md`.

Recommended options are listed **first** with a short justification. If you skip
a question I'll take the **(Recommended)** option.

Iteration 2 shipped **Phase 2** (download folder picker + downloads settings,
native file export/import, Android 13+ notifications, sync hardening, the
`withOpacity` sweep). This round is **Phase 3 — onboarding & polish** plus the
remaining data-management items. See `CLAUDE.md` §6–§7.

---

## A. Scope & ordering for iteration 3

- [x] **A. All of Phase 3 (onboarding, duplicate-in-category notice, reset/clear
      data), split into separate commits (Recommended — Phase 3 is small and
      mostly UI; doing it together finishes the user-facing roadmap and leaves
      only the test/infra hardening of Phase 4.)**
- [ ] B. Onboarding only this round; defer the smaller polish items.
- [ ] C. Skip onboarding; do the data-management + duplicate-notice polish only.
- [ ] D. Jump to Phase 4 (widget tests, dependency modernization) instead.

→ ANSWER: A is fine

---

## B. Onboarding flow content

First-run onboarding (scenario 1). What should the 3-step guide cover, and what
should it actually *do* at the end?

- [ ] **A. 3 info pages (what FicBatch is → library/offline/sync → reading) and,
      on desktop only, an optional "choose download folder" step; then mark
      onboarding complete (Recommended — informative without blocking; folder
      pick is desktop-only to match the Phase 2 design, and nothing forces
      permissions the user may not want yet.)**
- [ ] B. Same pages, and also request the notification permission during
      onboarding (more upfront, but asks for a permission before there's
      anything to notify about).
- [x] C. Minimal: a single welcome screen with a "Get started" button.

→ ANSWER: C with slight variation of only the important bits, like library, reading, save to library, downloading works

---

## C. When is onboarding considered "done"?

- [x] **A. Show once, tracked by an `onboarding_complete` flag; add a "Replay
      onboarding" entry in Settings (Recommended — standard behavior, and replay
      is handy for new users on a shared device or after a reset.)**
- [ ] B. Show once, no replay option.
- [ ] C. Show on every launch until the user picks a download folder / dismisses.

→ ANSWER:A, if not done choose something as default

---

## D. "Reset app data" scope

A destructive Settings action. What should it clear?

- [x] **A. Two separate actions — "Clear reading history" and "Reset app data"
      (wipes library, categories, settings, updates, and downloads) — each with
      a typed/explicit confirmation (Recommended — separates the common, safe
      action from the nuclear one, and a strong confirm prevents accidents.)**
- [ ] B. One "Reset everything" action with a confirmation.
- [ ] C. Reset app data but never touch downloaded files on disk.

→ ANSWER:A is best

---

## E. Duplicate-in-category notice

Scenario 17: adding a work to a category it's already in should notify rather
than silently no-op.

- [x] **A. Show a brief snackbar/toast "Already in {category}" wherever a work is
      added to a category it already belongs to (Recommended — matches the
      scenario, low-risk, and applies to both the browse add-flow and the
      library category editor.)**
- [ ] B. Block the duplicate with a dialog requiring acknowledgement.
- [ ] C. Leave as-is for now.

→ ANSWER: yep A,

---

## F. Phase 4 testing appetite (planning ahead)

Not necessarily this round, but it helps me sequence: how much widget/UI testing
do you want once Phase 3 is done?

- [x] **A. A focused set of widget tests for the main tabs + keep growing unit
      tests (Recommended — best value per effort; full golden/integration tests
      are heavy for a webview-driven app.)**
- [ ] B. Go broad: widget + golden tests for most screens.
- [ ] C. Keep unit tests only; skip widget tests.

→ ANSWER: also test the js injection on the many platform, then fix the building using github action if needed

---

## G. Anything else?

Bugs you've hit, priorities, or constraints.

→ ANSWER: add auto run in github action  (i think this was done, but check it if its still good or needing upgrade etc) upon you finishing iteration to create artifacts so i can test the app directly on every platform dont forget to up the version number (always).

this was on before your fixes at all, but ive noticed on desktop (i dint check on other platform) the website opened was very slow (also add the spinning thing when loading website) and some times the screen is blank dark, do check on this