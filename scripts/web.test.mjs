import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { JSDOM } from 'jsdom';

const source = fs.readFileSync(new URL('../web/commute-experience.html', import.meta.url), 'utf8');
function open(saved = null) {
  let latest = saved;
  const errors = [];
  const dom = new JSDOM(source, {
    runScripts: 'dangerously',
    beforeParse(window) {
      window.openai = {
        widgetState: saved,
        setWidgetState: async snapshot => {
          latest = JSON.parse(JSON.stringify(snapshot));
          window.openai.widgetState = latest;
          // The real exported bridge emits this synchronously before persisting.
          window.dispatchEvent(new window.CustomEvent('openai:set_globals', {
            detail: { globals: { widgetState: latest } },
          }));
        },
      };
      window.addEventListener('error', event => errors.push(event.error));
    },
  });
  const document = dom.window.document;
  return {
    document, window: dom.window, state: () => latest,
    click(selector) {
      const element = document.querySelector(selector);
      assert.ok(element, `Missing control: ${selector}`);
      element.click();
    },
    submit(selector) {
      document.querySelector(selector).dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true }));
    },
    change(selector, value) {
      const element = document.querySelector(selector);
      if (element.type === 'checkbox') element.checked = value;
      else element.value = value;
      element.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
    },
    close() { dom.window.close(); assert.deepEqual(errors, []); },
  };
}

test('plan, pause, resume, confirmation, and history work as one flow', () => {
  const app = open();
  try {
    app.click('[data-act="preview"]');
    assert.equal(app.document.querySelectorAll('.cf-plan-row').length, 3);
    app.click('[data-act="start"]');
    app.click('[data-act="pause"]');
    assert.equal(app.state().privateContent.active.timer.phase, 'paused');
    app.click('[data-act="resume"]');
    app.click('[data-act="fast"]');
    assert.equal(app.state().privateContent.active.timer.phase, 'confirm');
    app.change('[data-step]', true);
    app.submit('#cf-complete');
    assert.equal(app.state().privateContent.logs[0].completed, 1);
    assert.equal(app.state().privateContent.tasks[0].steps[0].done, true);
    app.click('[data-act="next"]');
    app.click('[data-act="ask-end"]');
    app.click('[data-act="end"]');
    assert.equal(app.state().privateContent.page, 'history');
    assert.equal(app.state().privateContent.active, null);
    assert.equal(app.state().privateContent.logs.length, 2);
  } finally { app.close(); }
});

test('editing survives synchronous state echoes and saves multiple steps', () => {
  const app = open();
  try {
    app.click('[data-page="tasks"]');
    app.click('[data-act="new"]');
    assert.ok(app.document.querySelector('#cf-editor'));
    app.document.querySelector('[name="title"]').value = '准备下一周';
    app.document.querySelector('[data-title="0"]').value = '列出三个重点';
    app.click('[data-act="add-step"]');
    app.document.querySelector('[data-title="1"]').value = '查看已有日程';
    app.submit('#cf-editor');
    assert.equal(app.state().privateContent.tasks.length, 4);
    assert.equal(app.state().privateContent.tasks[3].steps.length, 2);
  } finally { app.close(); }
});

test('browser persistence restores tasks and settings in a new page session', () => {
  const first = open();
  first.click('[data-page="settings"]');
  first.change('#cf-buffer', '5');
  const saved = first.state();
  first.close();
  const second = open(saved);
  try {
    second.click('[data-page="home"]');
    assert.match(second.document.querySelector('#cf-main').textContent, /已留出 5 分钟/);
    assert.ok(new TextEncoder().encode(JSON.stringify(second.state())).length < 16 * 1024);
  } finally { second.close(); }
});

test('user text is escaped instead of becoming executable markup', () => {
  const app = open();
  try {
    app.click('[data-page="tasks"]');
    app.click('[data-act="new"]');
    app.document.querySelector('[name="title"]').value = '<img src=x onerror=alert(1)>';
    app.document.querySelector('[data-title="0"]').value = '<script>bad()</script>';
    app.submit('#cf-editor');
    assert.match(app.document.querySelector('#cf-main').textContent, /<img src=x/);
    assert.equal(app.document.querySelectorAll('#cf-main img, #cf-main script').length, 0);
  } finally { app.close(); }
});

test('published HTML includes the current source and standalone persistence', () => {
  const html = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
  const dom = new JSDOM(html);
  try {
    const frame = dom.window.document.querySelector('iframe');
    assert.ok(frame);
    assert.equal(frame.getAttribute('sandbox'), 'allow-scripts');
    assert.ok(frame.dataset.srcdoc.includes(source));
    assert.match(html, /localStorage/);
    assert.doesNotMatch(source, /window\.openai\.(?:sendFollowUpMessage|openExternal)/);
    assert.doesNotMatch(html, /\/Users\/jinmu/);
  } finally { dom.window.close(); }
});
