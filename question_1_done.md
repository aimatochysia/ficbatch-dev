# question_1.md — Iteration 1 decisions

**How this works:** Edit this file to answer the questions below (write your
answer after each `→ ANSWER:` marker, or just delete the options you don't
want). On your next commit I'll read your answers, implement the agreed scope,
rename this file to `question_1_done.md`, and create `question_2.md` for the
following round. See `CLAUDE.md` §5–§8 for the full findings and roadmap.

If you don't answer a question, I'll proceed with the option marked
**(default)**.

---

## A. What should iteration 1 focus on?

I recommend starting with **Phase 0 (Correctness & hygiene)** because several
"working" features are quietly broken (imported works have no metadata; the test
suite won't compile; no CI safety net).

**A1. Pick the scope for this iteration** (choose one):
- [ ] **(default)** Phase 0 only — fix correctness/hygiene, add CI gate.
- [x] Phase 0 + the highest-value Phase 1 item you choose in section B.
- [ ] Skip Phase 0; jump straight to a specific feature (name it below).
- [ ] Something else.

→ ANSWER: phase 0 and phase 1 all of them is possible, separate to some commit to protect against session limit

---

## B. If we add one user-facing feature this round, which?

**B1.** Rank or pick the most important (these are the biggest UX gaps):
- [x] Library search + sort + multi-select bulk actions (scenario 4)
- [x] Favorites (star toggle + "Favorites First" sort) (scenario 5)
- [x] Reader settings dialog — font size / line height / sepia theme / chapter-jump (scenario 13)
- [ ] Download folder picker + re-pick (scenario 14)
- [ ] First-run onboarding (scenario 3-step + folder pick) (scenario 1)

→ ANSWER:do library first, then reader setting then favourites, for folder picker maybe only when its desktop, since the app should be cross platform first.

---

## C. Specific decisions I need

**C1. The "delete on empty category" behavior.** Today, removing a work from its
last category deletes it from the library entirely
(`storage_service.dart:209`). Should I:
- [x] **(default)** Keep the work in the library but uncategorized (recommended),
- [ ] Keep current behavior (empty categories = delete), but add a confirmation,
- [ ] Leave it exactly as-is for now.

→ ANSWER: yep default (A) is good

**C2. AO3 metadata extraction.** I'll complete `Ao3Service` to scrape tags,
summary, word/chapter counts, stats, and published/updated dates. Any fields you
specifically care about most (e.g. tags vs. word count vs. updated date)?

→ ANSWER:

**C3. Duplicate export systems.** There are two export/import paths
(`StorageService` vs `LibraryExportService`). I plan to standardize on the
versioned `LibraryExportService` and remove the older `StorageService` JSON/OPDS
methods. Keep OPDS export (for e-reader apps), or drop it?
- [x] **(default)** Standardize on `LibraryExportService`; drop OPDS for now.
- [ ] Standardize, but keep + surface OPDS export in Settings.

→ ANSWER: okay, but keep in mid for cross platformness

**C4. Dead code removal.** OK to delete `lib/services/work_saver.dart` (empty)
and `lib/widgets/work_card.dart` (unused)?
- [x] **(default)** Yes, delete both.
- [ ] Keep `work_card.dart` (I plan to use it).

→ ANSWER: yes delete them when uneeded in the future

**C5. New dependencies.** Some features need new packages — `file_picker`
(folder/file selection) and possibly `permission_handler` (Android 13+
notifications). Any objection to adding these when their feature lands?
- [x] **(default)** Fine to add as needed.
- [ ] Ask me before adding any new dependency.

→ ANSWER:as many as you like no asking is needed, but make sure the dependencies are reliable and not questionable

---

## D. Platform & testing priorities

**D1. Primary target platform** for this round's manual verification
(affects which behaviors I prioritize):
- [ ] **(default)** Android
- [ ] Windows
- [ ] iOS / macOS / Linux / Web (specify)
- [x] all except Web
→ ANSWER: au contraire, the default primary target are windows, android, ios, mac, linux. the project designed to be cross platform first for easy library syncing, and offline saved works reading + history

**D2. CI quality gate.** Add a GitHub Actions workflow running `flutter analyze`
+ `flutter test` on push/PR?
- [x] **(default)** Yes, add it.
- [ ] Not yet.

→ ANSWER: yep and please keep it updated in the future

---

## E. Anything else?

Free-form: bugs you've personally hit, features not captured in
`USER_SCENARIO.md`, or constraints I should know about.

→ ANSWER:
nothing else for now except next time use multiple choice & alpha
bet, on reccomended add reasoning/justification why before i answer additional notes
