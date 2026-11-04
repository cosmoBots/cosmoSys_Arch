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
