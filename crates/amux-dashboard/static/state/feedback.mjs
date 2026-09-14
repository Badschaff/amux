import { createElement, Activity, ChevronDown } from 'lucide';
import { settled, phaseLabels } from './interactions.mjs';
import registry from './control-registry.json';
import { actionFromHandler } from './controls.mjs';

export function installFeedback(interactions, ui, diagnostic = () => {}) {
  const controls = new Map();
  let source = null;
  const hub = document.createElement('details');
  hub.id = 'interaction-feedback';
  const summary = document.createElement('summary');
  summary.title = 'Action status';
  summary.append(createElement(Activity, {width:16, height:16}));
  const heading = document.createElement('span');
  heading.textContent = 'Recent actions';
  summary.append(heading);
  const status = document.createElement('span');
  status.className = 'interaction-summary-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  summary.append(status, createElement(ChevronDown, {width:14, height:14}));
  const list = document.createElement('div');
  list.className = 'interaction-list';
  list.setAttribute('aria-label', 'Recent actions');
  hub.append(summary, list);
  const panel = document.getElementById('notif-panel');
  if (panel) panel.insertBefore(hub, document.getElementById('notif-panel-list'));
  else diagnostic({verdict:'interaction_inspector_host_missing', measured:false, n_considered:0,
    why_unmeasured:'Notifications panel is missing'});
  function reportVisibility() {
    if (!panel?.classList.contains('active')) return;
    requestAnimationFrame(() => {
      // Opening and dismissing can both occur before this frame executes.
      if (!panel.classList.contains('active')) return;
      const rect = summary.getBoundingClientRect();
      const visible = rect.width > 0 && rect.height > 0 && rect.left >= 0 && rect.right <= innerWidth
        && rect.top >= 0 && rect.bottom <= innerHeight;
      diagnostic({verdict:visible ? 'interaction_inspector_visible' : 'interaction_inspector_clipped',
        measured:true, n_considered:1, open:hub.open, visible,
        rect:{left:rect.left, top:rect.top, width:rect.width, height:rect.height},
        viewport:{width:innerWidth, height:innerHeight}});
    });
  }
  if (panel) new MutationObserver(reportVisibility).observe(panel, {attributes:true, attributeFilter:['class']});
  hub.addEventListener('toggle', () => { ui.setState({activityOpen:hub.open}); reportVisibility(); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') hub.open = false; });
  const selectors = 'button, [role="button"], input, select, textarea, a[href], [onclick], [onchange]';
  function declare(element) {
    if (element.closest('#interaction-feedback')) return;
    const handler = actionFromHandler(element.getAttribute('onclick') || element.getAttribute('onchange'), registry.command_handlers);
    element.dataset.action ||= handler || element.id || element.getAttribute('name') || element.tagName.toLowerCase();
    const declaration = registry.command_handlers[element.dataset.action];
    if (declaration) element.dataset.interactionKind ||= declaration.kind;
    element.dataset.feedbackRequired ||= 'true';
    element.dataset.targetId ||= element.closest('[data-session], [data-id]')?.dataset.session || element.closest('[data-id]')?.dataset.id || element.id || element.dataset.action;
  }
  document.querySelectorAll(selectors).forEach(declare);
  new MutationObserver(records => {
    for (const record of records) for (const node of record.addedNodes) {
      if (node.nodeType !== 1 || node.closest('#interaction-feedback')) continue;
      if (node.matches(selectors)) declare(node);
      node.querySelectorAll(selectors).forEach(declare);
    }
  }).observe(document.body, {childList:true, subtree:true});
  for (const eventName of ['click','change','submit']) document.addEventListener(eventName, event => {
    const element = event.target.closest(selectors);
    if (!element || element.closest('#interaction-feedback')) return;
    declare(element);
    source = element;
    element.classList.add('action-responded');
    setTimeout(() => element.classList.remove('action-responded'), 450);
    // Only synchronous dispatch is causal. A later unrelated poll must never
    // borrow the most recently clicked button as its alleged origin.
    setTimeout(() => { if (source === element) source = null; }, 0);
  }, true);
  function render(receipt) {
    if (receipt && controls.has(receipt.id)) {
      const element = controls.get(receipt.id);
      const active = ['accepted','sending','running'].includes(receipt.phase);
      if (!active) controls.delete(receipt.id);
      const busy = active || [...controls.values()].includes(element);
      element.dataset.interactionPhase = receipt.phase;
      element.setAttribute('aria-busy', String(busy));
    }
    const receipts = interactions.recent(200);
    const pending = receipts.filter(r => !settled.has(r.phase));
    const last = receipts.at(-1);
    status.textContent = pending.length ? pending.length + ' active' : last ? phaseLabels[last.phase] : 'Actions';
    hub.dataset.phase = pending.some(r => ['unknown','blocked'].includes(r.phase)) ? 'blocked' : pending.length ? 'running' : last?.phase || 'idle';
    const visible = [...pending, ...receipts.filter(r => settled.has(r.phase)).slice(-20)].reverse();
    const focused = document.activeElement;
    const focusedReceipt = panel?.classList.contains('active') && list.contains(focused)
      && focused.matches('article > details > summary') ? focused.closest('article').dataset.interactionId : null;
    const expanded = new Set([...list.querySelectorAll('article > details[open]')]
      .map(details => details.parentElement.dataset.interactionId));
    list.replaceChildren();
    if (!visible.length) { const empty = document.createElement('p'); empty.textContent = 'No recent actions'; list.append(empty); }
    for (const item of visible) {
      const row = document.createElement('article');
      row.dataset.interactionId = item.id;
      row.dataset.phase = item.phase;
      const title = document.createElement('strong');
      title.textContent = item.command.label || item.command.kind.replaceAll('.', ' ');
      const target = document.createElement('span');
      target.className = 'interaction-target';
      target.textContent = item.command.target.label || item.command.target.id || '';
      const label = document.createElement('div');
      label.className = 'interaction-status';
      label.textContent = item.feedback.message || phaseLabels[item.phase];
      row.append(title, target, label);
      if (!['GET','HEAD'].includes(item.request?.method) && item.command.kind !== 'filesystem.upload') {
        const effects = document.createElement('div');
        effects.className = 'interaction-effects-status';
        const sync = item.effect_sync;
        effects.textContent = sync?.phase === 'failed' ? 'Changes unavailable; retrying'
          : sync?.phase === 'syncing' ? 'Checking changes'
          : sync?.measured ? item.effects.length + ' recorded changes' + (sync.more ? ' (partial)' : ' at last check')
          : 'Changes not yet checked';
        row.append(effects);
      }
      if (['accepted','sending','running'].includes(item.phase)) {
        const progress = document.createElement('progress');
        progress.setAttribute('aria-label', title.textContent + ' progress');
        if (item.progress?.total > 0) {
          progress.max = item.progress.total;
          progress.value = item.progress.completed;
          const fraction = document.createElement('span');
          fraction.textContent = Math.floor(item.progress.completed / item.progress.total * 100) + '%';
          row.append(fraction);
        }
        row.append(progress);
      }
      if (item.why_unmeasured) { const why = document.createElement('p'); why.textContent = item.why_unmeasured; row.append(why); }
      const explanation = document.createElement('details');
      explanation.open = expanded.has(item.id);
      const explainLabel = document.createElement('summary');
      explainLabel.append(createElement(ChevronDown, {width:14, height:14}), document.createTextNode('Details'));
      const metadata = document.createElement('p');
      metadata.textContent = item.id + (item.acknowledgement?.status ? ' | HTTP ' + item.acknowledgement.status : '') + ' | ' + item.effects.length + ' recorded changes';
      explanation.append(explainLabel, metadata);
      if (item.effect_sync?.error) {
        const error = document.createElement('p'); error.textContent = item.effect_sync.error; explanation.append(error);
      }
      const remedy = item.acknowledgement?.remedy;
      if (remedy) { const text = document.createElement('p'); text.textContent = typeof remedy === 'string' ? remedy : JSON.stringify(remedy); explanation.append(text); }
      row.append(explanation);
      list.append(row);
    }
    if (focusedReceipt && visible.some(item => item.id === focusedReceipt)) {
      const replacement = [...list.querySelectorAll('article')]
        .find(row => row.dataset.interactionId === focusedReceipt)?.querySelector('details > summary');
      if (panel.classList.contains('active') && document.activeElement === document.body)
        replacement?.focus({preventScroll:true});
      const restored = document.activeElement === replacement;
      diagnostic({verdict:restored ? 'interaction_focus_restored' : 'interaction_focus_lost',
        measured:true, n_considered:1, interaction_id:focusedReceipt, restored});
    }
    const retainedExpanded = visible.filter(item => expanded.has(item.id));
    if (retainedExpanded.length) {
      const restored = list.querySelectorAll('article > details[open]').length;
      diagnostic({verdict:restored === retainedExpanded.length ? 'interaction_disclosures_preserved' : 'interaction_disclosures_lost',
        measured:true, n_considered:retainedExpanded.length, restored});
    }
  }
  interactions.subscribe(receipt => {
    if (receipt.phase === 'accepted' && source) {
      source.dataset.commandObserved = 'true';
      source.dataset.interactionKind = receipt.command.kind;
      source.dataset.targetId = receipt.command.target.id || receipt.request?.path || source.dataset.targetId;
      source.dataset.interactionId = receipt.id;
      controls.set(receipt.id, source);
    }
    render(receipt);
  });
  render();
  return {render, source:() => source, coverage:() => {
    const all = [...document.querySelectorAll(selectors)].filter(e => !e.closest('#interaction-feedback'));
    const commands = all.filter(e => e.dataset.interactionKind || e.dataset.commandObserved || registry.command_handlers[e.dataset.action]);
    return {measured:true, n_considered:all.length, declared:all.filter(e => e.dataset.action && e.dataset.feedbackRequired && e.dataset.targetId).length,
      declared_command_controls:commands.filter(e => e.dataset.interactionKind).length,
      observed_command_controls:commands.filter(e => e.dataset.commandObserved).length,
      receipts:interactions.recent(200).length,
      missing:commands.filter(e => !e.dataset.action || !e.dataset.interactionKind || !e.dataset.targetId || !e.dataset.feedbackRequired).map(e => e.outerHTML.slice(0,200))};
  }};
}
