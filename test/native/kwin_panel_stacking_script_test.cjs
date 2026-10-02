const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const header = fs.readFileSync(path.join(__dirname,
  '../../linux/runner/kwin_panel_stacking_script.h'), 'utf8');
const script = header.match(/R"script\(([\s\S]*?)\)script"/)[1];
const applicationId = 'com.divertedriver.HotkeyGrammarCorrector';

function signal() {
  const listeners = [];
  return {
    connect(listener) { listeners.push(listener); },
    emit(...arguments) { listeners.forEach(listener => listener(...arguments)); },
  };
}

function window(properties = {}) {
  const result = {
    normalWindow: true, resourceClass: applicationId, desktopFileName: '',
    keepAbove: false, hidden: false, minimized: false, skipTaskbar: false,
    activeChanged: signal(), hiddenChanged: signal(),
    minimizedChanged: signal(), demandsAttentionChanged: signal(),
    ...properties,
  };
  let attention = false;
  Object.defineProperty(result, 'demandsAttention', {
    get() { return attention; },
    set(value) {
      if (attention === value) return;
      attention = value;
      result.demandsAttentionChanged.emit();
    },
  });
  return result;
}

function workspace(windows = [], plasma = 6) {
  const added = signal();
  const result = plasma === 6 ? {
    activeWindow: null, windowAdded: added, windowList: () => windows,
  } : {
    activeClient: null, clientAdded: added, clientList: () => windows,
  };
  vm.runInNewContext(script, { workspace: result });
  return {
    added,
    active() { return plasma === 6 ? result.activeWindow : result.activeClient; },
    focus(other) {
      if (plasma === 6) result.activeWindow = other;
      else result.activeClient = other;
    },
  };
}

for (const plasma of [5, 6]) {
  test(`CAP-1: Plasma ${plasma} keeps newly mapped panel above and focused`, () => {
    const desktop = workspace([], plasma);
    const panel = window();
    desktop.added.emit(panel);
    assert.equal(panel.keepAbove, true);
    assert.equal(panel.skipTaskbar, false);
    assert.equal(desktop.active(), panel);
  });

  test(`CAP-1: Plasma ${plasma} denied activation focuses without flashing`, () => {
    const panel = window();
    const desktop = workspace([panel], plasma);
    desktop.focus(window({ resourceClass: 'another.app' }));
    panel.demandsAttention = true;
    assert.equal(desktop.active(), panel);
    assert.equal(panel.demandsAttention, false);
  });

  test(`CAP-14: Plasma ${plasma} focus loss stays dismissed`, () => {
    const panel = window();
    const desktop = workspace([panel], plasma);
    const other = window({ resourceClass: 'another.app' });
    desktop.focus(other);
    panel.activeChanged.emit();
    panel.hidden = true;
    panel.hiddenChanged.emit();
    panel.demandsAttention = true;
    assert.equal(desktop.active(), other);
    panel.hidden = false;
    panel.hiddenChanged.emit();
    assert.equal(desktop.active(), panel);
    assert.equal(panel.demandsAttention, false);
  });

  test(`CAP-1: Plasma ${plasma} unminimize raises without undoing minimize`, () => {
    const panel = window({ minimized: true });
    const desktop = workspace([panel], plasma);
    assert.equal(desktop.active(), null);
    panel.demandsAttention = true;
    assert.equal(desktop.active(), null);
    assert.equal(panel.minimized, true);
    panel.minimized = false;
    panel.minimizedChanged.emit();
    assert.equal(desktop.active(), panel);
  });
}

test('CAP-1: foreign applications and helper windows keep their own policy', () => {
  const foreign = window({ resourceClass: 'another.app' });
  const helper = window({ normalWindow: false });
  const similar = window({ resourceClass: `${applicationId}.other` });
  const desktop = workspace([foreign, helper, similar]);
  for (const candidate of [foreign, helper, similar]) {
    candidate.demandsAttention = true;
    assert.equal(candidate.keepAbove, false);
    assert.equal(candidate.demandsAttention, true);
  }
  assert.equal(desktop.active(), null);
});

test('CAP-1: desktop-file identity works when resource class differs', () => {
  const panel = window({ resourceClass: 'different', desktopFileName: applicationId });
  const desktop = workspace([panel]);
  assert.equal(desktop.active(), panel);
  assert.equal(panel.keepAbove, true);
});
