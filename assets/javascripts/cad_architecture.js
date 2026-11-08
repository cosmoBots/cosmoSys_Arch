export function initializeArchitectureControls(ModelControls, root = document) {
const initialize = viewer => {
  const panel = root.querySelector('#arch-cad-controls');
  if (!panel || panel.dataset.ready === 'true') return;
  const status = panel.querySelector('[role="status"]');
  try {
    const configuration = JSON.parse(root.querySelector('#arch-cad-configuration').textContent);
    const controls = new ModelControls(viewer, configuration);
    const inputs = [...panel.querySelectorAll('[data-arch-control]')];
    let values = Object.fromEntries(inputs.map(input => [input.dataset.archControl, Number(input.value)]));
    const apply = () => {
      inputs.forEach(input => {
        input.parentElement.querySelector('output').textContent = String(values[input.dataset.archControl]);
      });
      controls.setValues(values);
    };
    inputs.forEach(input => {
      input.disabled = false;
      input.addEventListener('input', () => { values[input.dataset.archControl] = Number(input.value); apply(); });
    });
    const reset = panel.querySelector('[data-arch-reset]');
    reset.disabled = false;
    reset.addEventListener('click', () => {
      inputs.forEach(input => input.value = input.dataset.default);
      values = Object.fromEntries(inputs.map(input => [input.dataset.archControl, Number(input.dataset.default)]));
      apply();
    });
    apply(); controls.fitVisible();
    // Upstream fits the complete attachment, including our masked geometry.
    // In this context the toolbar must frame the selected piece instead.
    viewer.element?.querySelector('[data-cad-action="fit"]')?.addEventListener('click', event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      controls.fitVisible();
    }, {capture:true});
    status.textContent = panel.dataset.readyLabel;
    panel.dataset.ready = 'true';
    // Shared client-local scene controller for piece-camera capture and tests.
    // Runtime clients should continue using the validated batch event below.
    panel.archControls = controls;
    // Generic batch API for optional execution clients. Validate every value
    // before changing any slider; the model and its saved defaults stay intact.
    panel.addEventListener('architecture:set-values', event => {
      try {
        const batch = event.detail?.values;
        if (!batch || typeof batch !== 'object' || Array.isArray(batch)) throw new Error('Invalid control batch');
        const entries = Object.entries(batch).map(([key, value]) => {
          const input = inputs.find(candidate => candidate.dataset.archControl === key);
          if (!input || typeof value !== 'number' || !Number.isFinite(value) || value < Number(input.min) || value > Number(input.max)) {
            throw new Error(`Invalid value for ${key}`);
          }
          return [input, value];
        });
        // Do not route numerical actuation through range inputs: the browser
        // can quantize them to their step. Apply the exact validated values.
        const all = {...values, ...batch};
        controls.setValues(all);
        values = all;
        entries.forEach(([input, value]) => {
          input.value = value;
          input.parentElement.querySelector('output').textContent = String(value);
        });
        event.detail.result = {status: 'applied'};
      } catch (error) {
        event.detail.result = {status: 'rejected', reason: error.message};
      }
    });
  } catch (error) {
    status.textContent = error.message;
    panel.dataset.error = 'true';
  }
};
root.addEventListener('cad-preview:ready', event => {
  if (event.target === root.querySelector('[data-cad-preview]')) initialize(event.detail.viewer);
});
const viewer = root.querySelector('[data-cad-preview]')?.cadViewer;
if (viewer) initialize(viewer);
}
