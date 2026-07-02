// Headless DOM tests for assets/js/listing_buttons.js.
// Runs the real injector (the same file the app injects) inside jsdom against
// saved AO3 fixtures, in both a narrow (portrait/mobile) and a wide
// (landscape/desktop) viewport, since layout-affecting differences between
// orientations were a review concern.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { JSDOM } from 'jsdom';

const here = dirname(fileURLToPath(import.meta.url));
const injectorSrc = readFileSync(
  join(here, '..', '..', 'assets', 'js', 'listing_buttons.js'),
  'utf8',
);
const listingHtml = readFileSync(join(here, 'fixtures', 'ao3_listing.html'), 'utf8');
const workPageHtml = readFileSync(join(here, 'fixtures', 'ao3_work_page.html'), 'utf8');

const VIEWPORTS = {
  portrait: { width: 400, height: 800 },
  landscape: { width: 1280, height: 720 },
};

/** Load the fixture into jsdom and run the injector with the given saved ids. */
async function inject({ savedIds = [], viewport = 'landscape' } = {}) {
  const { width, height } = VIEWPORTS[viewport];
  const dom = new JSDOM(listingHtml, {
    url: 'https://archiveofourown.org/works/search?work_search%5Bquery%5D=test',
    runScripts: 'outside-only',
    pretendToBeVisual: true,
  });
  const { window } = dom;
  Object.defineProperty(window, 'innerWidth', { value: width, configurable: true });
  Object.defineProperty(window, 'innerHeight', { value: height, configurable: true });

  const js = injectorSrc.replace('__FB_SAVED_IDS__', JSON.stringify(savedIds));
  window.eval(js);
  // The injector schedules run() bursts via setTimeout(0, 200, ...); the first
  // burst fires at t=0 — give the event loop a moment.
  await new Promise((r) => setTimeout(r, 30));
  return dom;
}

for (const viewport of Object.keys(VIEWPORTS)) {
  test(`[${viewport}] inserts one Save button per work blurb`, async () => {
    const dom = await inject({ viewport });
    const doc = dom.window.document;
    const buttons = doc.querySelectorAll('a.__fb_save_btn');
    assert.equal(buttons.length, 3, 'one button per blurb');
    for (const btn of buttons) assert.equal(btn.textContent, 'Save');
  });

  test(`[${viewport}] discovers work ids from li id, class, and href`, async () => {
    const dom = await inject({ viewport });
    const ids = dom.window.__fb_save_state
      ? [...dom.window.__fb_save_state.processed]
      : [];
    assert.deepEqual(ids.sort(), ['1001', '1002', '1003']);
  });

  test(`[${viewport}] marks already-saved works and dims their blurb`, async () => {
    const dom = await inject({ savedIds: ['1001'], viewport });
    const doc = dom.window.document;
    const first = doc.getElementById('work_1001');
    const btn = first.querySelector('a.__fb_save_btn');
    assert.equal(btn.textContent, 'Saved');
    assert.equal(first.style.opacity, '0.85');
    // The other two remain normal Save buttons.
    const saveButtons = [...doc.querySelectorAll('a.__fb_save_btn')].filter(
      (b) => b.textContent === 'Save',
    );
    assert.equal(saveButtons.length, 2);
  });

  test(`[${viewport}] is idempotent across repeated injection`, async () => {
    const dom = await inject({ viewport });
    // Re-run the injector (same window), as the app does after navigation.
    const js = injectorSrc.replace('__FB_SAVED_IDS__', JSON.stringify([]));
    dom.window.eval(js);
    await new Promise((r) => setTimeout(r, 30));
    const buttons = dom.window.document.querySelectorAll('a.__fb_save_btn');
    assert.equal(buttons.length, 3, 'no duplicate buttons after re-injection');
  });
}

test('clicking Save fetches the work page, extracts metadata, and awaits confirm', async () => {
  const dom = await inject({});
  const { window } = dom;

  const messages = [];
  window.FB = { postMessage: (s) => messages.push(JSON.parse(s)) };
  window.fetch = async () => ({ ok: true, text: async () => workPageHtml });

  const btn = window.document
    .getElementById('work_1001')
    .querySelector('a.__fb_save_btn');
  btn.dispatchEvent(new window.Event('click', { bubbles: true, cancelable: true }));
  await new Promise((r) => setTimeout(r, 30));

  const saveMsg = messages.find((m) => m.type === 'saveWorkFromListing');
  assert.ok(saveMsg, 'app is notified with the scraped metadata');
  assert.equal(saveMsg.workId, '1001');
  assert.equal(saveMsg.meta.title, 'The First Work');
  assert.equal(saveMsg.meta.author, 'alice');
  assert.deepEqual(saveMsg.meta.tags.freeform, ['Fluff', 'Angst']);
  assert.equal(saveMsg.meta.stats.words, '12,345');
  assert.equal(saveMsg.meta.stats.updated, '2024-06-15');
  assert.equal(btn.textContent, 'Select...');

  // App confirms after the category dialog → button flips to saved state.
  window.__fb_confirmSave('1001');
  assert.equal(btn.textContent, '✓ Saved');

  // And a cancel path resets a pending save.
  const btn2 = window.document
    .querySelector('li.work-1002')
    .querySelector('a.__fb_save_btn');
  btn2.dispatchEvent(new window.Event('click', { bubbles: true, cancelable: true }));
  await new Promise((r) => setTimeout(r, 30));
  window.__fb_cancelSave('1002');
  assert.equal(btn2.textContent, 'Save');
});
