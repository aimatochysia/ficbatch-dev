# question_4.md — Iteration 4 decisions

**How this works:** mark your choice with `[x]` or write after `→ ANSWER:`. On
your next commit I implement, rename this to `question_4_done.md` (closed), and
create `question_5.md`. Recommended options are first, with justification; if
you skip a question I take the **(Recommended)** option.

Iteration 3 shipped **Phase 3**: onboarding, duplicate-in-category notices,
Clear Reading History + Reset App Data, the browse webview slow/blank fix with
spinner + watchdog, the auto-artifacts workflow, and version 1.1.0+2. The Pears
P2P research you asked for is in `docs/research/pears_p2p_sync.md`. This round
is **Phase 4 — testing & infra** plus the sync decision.

---

## A. Scope for iteration 4

- [ ] **A. Phase 4 hardening (widget tests, JS-injection testability, dependency
      modernization) + start the sync-folder feature from the Pears research
      (Recommended — finishes the roadmap's quality work while delivering the
      first user-visible step toward cross-device sync.)**
- [ ] B. Phase 4 hardening only; decide on sync later.
- [ ] C. Sync feature only; defer tests/infra.
- [ ] D. Something else.

→ ANSWER:

---

## B. Cross-device sync approach (from `docs/research/pears_p2p_sync.md`)

- [ ] **A. Sync-folder mode: auto-export (debounced, merge-import on launch) into
      a user-chosen folder; users pair it with Syncthing/Dropbox/iCloud
      (Recommended — works on every platform today, zero new native code, zero
      infrastructure, reuses the shipped export/import + portable downloads;
      Syncthing keeps it fully P2P.)**
- [ ] B. Dart-native CRDT (`crdt`/`sql_crdt`) + LAN transport (true multi-writer
      conflict resolution, medium effort, transport/discovery still to solve).
- [ ] C. Embed Pears/Bare via bare-kit (true serverless P2P, but weeks of
      platform-channel work: Java + Obj-C + desktop FFI/sidecar, and no web).
- [ ] D. No sync work yet.

→ ANSWER:

---

## C. JS injection testing (your iteration-3 request)

The injected JS (reader styling, listing buttons, theme) currently lives in
Dart string literals and is untested. Options:

- [ ] **A. Extract the JS into assets + add a Node-based DOM test job in CI that
      runs the injectors against saved AO3 HTML fixtures (Recommended — fast,
      runs on every push, catches selector/markup breakage without needing
      emulators; real-device coverage stays manual via the artifacts builds.)**
- [ ] B. Full integration tests on Android emulator + Windows runner in CI
      (highest fidelity, slow and flaky; macOS/iOS runners cost 10x minutes).
- [ ] C. Both: A now, B later for Android only.
- [ ] D. Skip JS testing.

→ ANSWER:

---

## D. Dependency modernization scope

- [ ] **A. Conservative: drop unused `xml`, bump `http` to ^1.x with code fixes,
      remove the CI analyzer-downgrade workaround; leave webview/workmanager
      majors alone (Recommended — real wins, low regression risk; webview major
      bumps deserve their own round with device testing.)**
- [ ] B. Aggressive: also bump webview_flutter to 4.14+, flutter_local_notifications
      to 19.x, workmanager latest, and Flutter SDK pin to a newer stable.
- [ ] C. Leave dependencies alone this round.

→ ANSWER:

---

## E. Cut a release?

Once iteration 4 lands, should I trigger-ready a real release (tag + installers
via `flutter_build.yml`) as v1.1.0?

- [ ] **A. Yes — prepare release notes and bump to 1.2.0+3 when iteration 4
      finishes, so the first "post-overhaul" release includes the sync folder
      and test hardening (Recommended — a meaty, coherent release.)**
- [ ] B. Release v1.1.0 now from the current branch state.
- [ ] C. No release yet.

→ ANSWER:

---

## F. Anything else?

→ ANSWER:
