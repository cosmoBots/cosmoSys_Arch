// Inspection never changes import decisions, and folding never changes selection.
export class PreflightPreview {
  constructor(controls, nodes) {
    this.controls = controls;
    this.nodes = nodes;
    this.materials = new Map();
    this.meshes = [];
    controls.root.traverse(object => {
      if (!object.isMesh && !object.isLine && !object.isPoints) return;
      let owner = object;
      while (owner && !Number.isInteger(owner.userData?.cosmosys_cad_node_index)) owner = owner.parent;
      if (owner) this.meshes.push({object, owner: owner.userData.cosmosys_cad_node_index,
        mask: object.layers.mask, material: object.material});
    });
  }

  highlight(material) {
    if (!this.materials.has(material)) {
      const highlighted = material.clone();
      highlighted.color?.set('#ffb000');
      highlighted.emissive?.set('#604000');
      this.materials.set(material, highlighted);
    }
    return this.materials.get(material);
  }

  focus(index, context = false) {
    this.selected = index;
    const subtree = new Set();
    for (const node of this.nodes) {
      if (index === null || node.index === index || subtree.has(node.parent)) subtree.add(node.index);
    }
    for (const entry of this.meshes) {
      const selected = subtree.has(entry.owner);
      entry.object.layers.mask = selected || context ? entry.mask : 0;
      const highlighted = index !== null && context && selected;
      entry.object.material = highlighted ? (Array.isArray(entry.material) ?
        entry.material.map(material => this.highlight(material)) : this.highlight(entry.material)) : entry.material;
    }
    this.controls.fitVisible();
    this.controls.viewer.render();
    return subtree;
  }
}

export function initializeCadPreflight(ModelControls) {
  const form = document.getElementById('arch-cad-plan');
  const panel = document.getElementById('arch-cad-preflight');
  if (!form || !panel) return;
  const config = JSON.parse(document.getElementById('arch-preflight-configuration').textContent);
  const rows = [...panel.querySelectorAll('[data-arch-node]')];
  const status = panel.querySelector('[data-arch-preview-status]');
  const context = panel.querySelector('[data-arch-context]');
  const showAll = panel.querySelector('[data-arch-show-all]');
  const collect = () => Object.fromEntries(rows.map(row => [row.dataset.archNode, {
    mode: row.querySelector('[data-arch-mode]').value,
    visible: row.querySelector('[data-arch-visible]').checked ? '1' : '0'
  }]));
  const reviewed = JSON.stringify(collect());
  let preview, selected = null;
  const policies = () => {
    const inherited = new Map();
    for (const row of rows) {
      const skipped = inherited.get(row.dataset.parent) || false;
      row.dataset.policySkipped = String(skipped || row.querySelector('[data-arch-mode]').value === 'exclude');
      inherited.set(row.dataset.archNode, skipped || row.querySelector('[data-arch-mode]').value !== 'include');
    }
    const changed = JSON.stringify(collect()) !== reviewed;
    form.querySelector('[data-arch-decisions-changed]').hidden = !changed;
    form.querySelector('[data-arch-confirm]').disabled = changed || panel.dataset.blocked === 'true';
  };
  policies();
  initializeBulkFilter(panel, config.nodes, rows, policies);
  form.addEventListener('change', event => {
    if (event.target.matches('[data-arch-mode], [data-arch-visible]')) policies();
  });
  form.addEventListener('submit', () => form.querySelector('[name="choices_json"]').value = JSON.stringify(collect()));
  panel.querySelector('[data-arch-expand]').addEventListener('click', () => panel.querySelectorAll('details').forEach(detail => detail.open = true));
  panel.querySelector('[data-arch-collapse]').addEventListener('click', () => panel.querySelectorAll('details').forEach(detail => detail.open = false));
  const focus = () => {
    rows.forEach(row => row.querySelector('[data-arch-select]').setAttribute('aria-pressed', String(Number(row.dataset.archNode) === selected)));
    if (!preview) return;
    preview.focus(selected, context.checked);
    status.textContent = selected === null ? showAll.textContent : config.nodes.find(node => node.index === selected).path;
  };
  panel.querySelectorAll('[data-arch-select]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault(); event.stopPropagation();
    selected = Number(button.dataset.archSelect);
    focus();
  }));
  showAll.addEventListener('click', () => {selected = null; focus();});
  context.addEventListener('change', focus);
  const initialize = viewer => {
    if (preview) return;
    try {
      preview = new PreflightPreview(new ModelControls(viewer, config), config.nodes);
      context.disabled = false; showAll.disabled = false;
      panel.dataset.ready = 'true';
      panel.archPreview = preview;
      focus();
    } catch (error) {
      status.textContent = error.message;
      panel.dataset.error = 'true';
    }
  };
  document.addEventListener('cad-preview:ready', event => initialize(event.detail.viewer));
  document.addEventListener('cad-preview:error', () => {
    status.textContent = document.querySelector('.cad-preview-status')?.textContent || 'CAD loading failed';
    panel.dataset.error = 'true';
  });
  const element = document.querySelector('[data-cad-preview]');
  if (element?.cadViewer) initialize(element.cadViewer);
}

export function affectedCadNodes(nodes, matches) {
  const affected = new Set(matches);
  for (const node of nodes) if (affected.has(node.parent)) affected.add(node.index);
  return affected;
}

export function applyCadFilter(rows, matches, action) {
  if (!['include', 'exclude', 'atomic', 'show', 'hide'].includes(action)) throw new Error('Invalid bulk action');
  const selected = new Set(matches.map(String));
  for (const row of rows) {
    if (!selected.has(row.dataset.archNode)) continue;
    if (action === 'show' || action === 'hide') row.querySelector('[data-arch-visible]').checked = action === 'show';
    else row.querySelector('[data-arch-mode]').value = action;
  }
}

function initializeBulkFilter(panel, nodes, rows, policies) {
  const filter = panel.querySelector('[data-arch-filter]');
  if (!filter) return;
  const query = filter.querySelector('[data-filter-query]');
  const regex = filter.querySelector('[data-filter-regex]');
  const field = filter.querySelector('[data-filter-field]');
  const action = filter.querySelector('[data-filter-action]');
  const status = filter.querySelector('[role="status"]');
  const apply = filter.querySelector('[data-filter-apply]');
  let worker, timer, matches = null;
  const clear = () => {
    worker?.terminate(); clearTimeout(timer); worker = null; matches = null;
    apply.disabled = true;
    rows.forEach(row => delete row.dataset.filterMatch);
    status.textContent = '';
  };
  filter.addEventListener('input', clear);
  filter.addEventListener('change', clear);
  filter.querySelector('[data-filter-preview]').addEventListener('click', () => {
    clear();
    try {
      worker = new Worker(filter.dataset.workerUrl, {type:'module'});
      const currentWorker = worker;
      timer = setTimeout(() => {clear(); status.textContent = filter.dataset.timeoutLabel;}, 1500);
      worker.onmessage = ({data}) => {
        if (worker !== currentWorker) return;
        worker.terminate(); worker = null; clearTimeout(timer);
        if (data.error) { status.textContent = data.error; return; }
        matches = data.indices;
        const affected = affectedCadNodes(nodes, matches);
        rows.forEach(row => row.dataset.filterMatch = String(matches.includes(Number(row.dataset.archNode))));
        status.textContent = filter.dataset.matchesLabel.replace('%{matches}', matches.length).replace('%{affected}', affected.size);
        apply.disabled = !matches.length;
      };
      worker.onerror = () => {clear(); status.textContent = filter.dataset.errorLabel;};
      worker.postMessage({nodes, query:query.value, options:{regex:regex.checked, field:field.value}});
    } catch (_) { clear(); status.textContent = filter.dataset.errorLabel; }
  });
  apply.addEventListener('click', () => {
    if (!matches) return;
    applyCadFilter(rows, matches, action.value);
    policies();
    status.textContent = filter.dataset.appliedLabel;
    apply.disabled = true;
  });
  window.addEventListener('pagehide', clear, {once:true});
}
