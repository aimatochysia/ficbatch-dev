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

- [x] **A. Bug-fix round: whatever your manual testing of v1.2.0 surfaces, plus
      small leftovers (remaining tab widget tests, RadioGroup migration in
      advanced search) (Recommended — after four heavy iterations the highest
      value is stabilizing what shipped against real-device feedback.)**
- [x] B. Mobile sync folder: Android SAF folder access so phones can join the
      sync folder directly (desktop-only today).
- [ ] C. Start the Rust/iroh P2P sync spike from the research addendum.
- [ ] D. Something else (describe below).

→ ANSWER: B first the A, for the C part lets wait after both A and B

---

## B. Report your manual-testing findings

List anything broken/odd per platform (Android / Windows / Linux / macOS /
iOS), ideally with steps. I'll triage and fix in priority order.

→ ANSWER:
- on mobile android, i found that if im too fast, only some information of a work is saved to library. e.g. only the summary are correct, the author listed as unkown, and the title is work #58495609 perhaps also try to get info again on library if those are empty (except if really empty then mark them as special case e.g. the summary being empty or title is empty / space / special characters)
- on mobile android + physical mouse clicking a popup menu e.g. load saved searches, clicked through to the website (doesnt happen with touch)
- for the issue of windows can you rate limit the app on downloads etc to make it slightly slower with some small randomized break between download / processes to not overwhelm the server
- on android as well as windows, can you delete only the text (not class not link) from this element?
<ul class="required-tags">
<li><a class="help symbol question modal modal-attached" title="Symbols key" href="/help/symbols_key" aria-controls="modal"><span class="rating-teen rating" title="Teen And Up Audiences"><span class="text">Teen And Up Audiences</span></span></a></li>
<li><a class="help symbol question modal modal-attached" title="Symbols key" href="/help/symbols_key" aria-controls="modal"><span class="warning-no warnings" title="No Archive Warnings Apply"><span class="text">No Archive Warnings Apply</span></span></a></li>
<li><a class="help symbol question modal modal-attached" title="Symbols key" href="/help/symbols_key" aria-controls="modal"><span class="category-multi category" title="F/F, F/M"><span class="text">F/F, F/M</span></span></a></li>
<li><a class="help symbol question modal modal-attached" title="Symbols key" href="/help/symbols_key" aria-controls="modal"><span class="complete-no iswip" title="Work in Progress"><span class="text">Work in Progress</span></span></a></li>
</ul>
- on android as well as windows can you skip editing this <ul class="navigation actions"> the darkmode causes the link text background color to be dark grey? or in fact for darkmode i dont think a link text should have background color

---

## C. Sync-folder polish (if you tested it)

- [ ] **A. Works as-is; no changes needed yet (Recommended default until your
      testing says otherwise.)**
- [ ] B. Add sync-on-app-focus (re-import when the window regains focus, not
      just at launch).
- [ ] C. Add a conflict indicator / last-device-synced info in Settings.
- [ ] D. Problems found (describe below).

→ ANSWER: i havent tested this, but could you make per 1 hour for temporary debug?

---

## D. Anything else?

→ ANSWER:
if possible after implementing all above, add more themes , reading themes and app themes for personality (ap themes also affect colors like buttons etc) while reading themes is for ready + flutter buttons only when reading that. its such a cool thing youve added sepia