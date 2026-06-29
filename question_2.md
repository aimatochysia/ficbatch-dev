# question_2.md — Iteration 2 decisions

**How this works:** Edit this file to answer. For each question, mark your choice
by putting an `x` in the `[ ]` next to a lettered option (e.g. `[x] B.`), or
write free text after `→ ANSWER:`. On your next commit I'll implement the agreed
scope, rename this file to `question_2_done.md` (closed — never reopened), and
create `question_3.md`.

Recommended options are listed **first** with a short justification so you can
judge before answering. If you skip a question I'll take the **(Recommended)**
option.

Iteration 1 shipped **Phase 0 + Phase 1** (correctness/hygiene, library
search/sort/multi-select, favorites, reader settings, System theme). This round
is **Phase 2 — downloads, storage & sync robustness**. See `CLAUDE.md` §6–§7.

---

## A. Scope & ordering for iteration 2

- [ ] **A. All of Phase 2, split into separate commits (Recommended — keeps the
      release coherent: downloads/storage/sync robustness ship together, and
      per-commit boundaries protect against session cuts like last round.)**
- [ ] B. Only the download-folder picker + downloads settings (defer sync +
      notifications to iteration 3).
- [ ] C. Only sync robustness + Android notifications (defer folder picker).
- [ ] D. Something else (describe below).

→ ANSWER:

---

## B. Download-folder picker platforms

You said folder picking should be "desktop first" since the app is
cross-platform. How should the re-pickable download folder behave?

- [ ] **A. Desktop only (Windows/macOS/Linux) pick a folder; mobile/iOS keep the
      app-documents dir (Recommended — `file_picker` directory selection is
      reliable on desktop, while Android/iOS sandbox restrictions make arbitrary
      folders fragile; this matches your "cross-platform first" intent.)**
- [ ] B. All platforms, including Android SAF / iOS document picker (more work,
      more edge cases, but a user-visible folder everywhere).
- [ ] C. Desktop folder picker now; add mobile later in a separate iteration.

→ ANSWER:

---

## C. Native file export/import vs the JSON paste box

Today, import requires pasting raw JSON or typing a path
(`settings_tab.dart`). Export writes a file and shows its path.

- [ ] **A. Replace with native file pickers (save/open dialogs) and keep the
      paste box as a hidden fallback only if the picker is unavailable
      (Recommended — far better UX and fewer user errors; the fallback avoids
      regressions on any platform where the picker misbehaves.)**
- [ ] B. Add native pickers but keep the paste box visible as an explicit option.
- [ ] C. Leave export/import as-is this round.

→ ANSWER:

---

## D. Android notifications dependency

Update notifications likely never appear on Android 13+ (missing
`POST_NOTIFICATIONS` permission + runtime request).

- [ ] **A. Add `permission_handler` and request POST_NOTIFICATIONS at the right
      moment, plus manifest fixes (`POST_NOTIFICATIONS`,
      `RECEIVE_BOOT_COMPLETED`) (Recommended — it's the standard, reliable way to
      get runtime permission + reboot rescheduling working; you already approved
      adding reliable deps.)**
- [ ] B. Manifest fixes only, request via flutter_local_notifications' own
      Android API (no new dependency, slightly less control).
- [ ] C. Skip notifications this round.

→ ANSWER:

---

## E. Sync date-parsing hardening

`SyncService` reads `dd.status`/`dd.published` text and `DateTime.tryParse`s it,
which silently fails on AO3's real markup (labels/ranges).

- [ ] **A. Reuse the new `Ao3Service` date regex + share one metadata parser
      between sync and import (Recommended — single source of truth, and sync
      gets the full updated/word-count baseline it currently lacks.)**
- [ ] B. Just harden the date regex in `SyncService` without refactoring.
- [ ] C. Leave sync parsing for a later round.

→ ANSWER:

---

## F. Deprecation cleanup (`withOpacity`)

`Color.withOpacity(...)` is deprecated on newer Flutter in favor of
`withValues(alpha:)`. It's widespread.

- [ ] **A. Defer to Phase 3 as planned (Recommended — it's purely cosmetic on the
      current CI Flutter 3.32 where it isn't yet an error; bundling it later
      keeps this round focused on functional robustness.)**
- [ ] B. Do the `withOpacity` → `withValues` sweep now as part of this round.

→ ANSWER:

---

## G. Anything else?

Bugs you've hit, priorities, or constraints.

→ ANSWER:
