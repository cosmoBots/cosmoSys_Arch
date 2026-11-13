// A native range quantizes from min and can make max unreachable. Use ordinal
// positions for authored steps, with a final position for the exact upper bound.
export function rangeSteps(min, max, step) {
  return Math.max(1, Math.ceil(Number(((max - min) / step).toPrecision(14))));
}

export function rangeValue(index, min, max, step) {
  const count = rangeSteps(min, max, step);
  if (index <= 0) return min;
  if (index >= count) return max;
  return Math.min(max, Number((min + index * step).toPrecision(15)));
}

function numericStep(min, max, step) {
  // Finer spinner increments must also be able to reach both exact bounds.
  const epsilon = Math.max(step, max - min) * 1e-10;
  let a = step, b = (max - min) % step;
  for (let i = 0; i < 32 && b > epsilon; i++) [a, b] = [b, a % b];
  return Number(a.toPrecision(14));
}

function floatingRanges(inputs, getValue, setValue) {
  const popup = document.createElement('div');
  popup.className = 'arch-cad-range-popup';
  const slider = document.createElement('input');
  slider.type = 'range';
  const limits = document.createElement('div');
  limits.className = 'arch-cad-range-limits';
  limits.setAttribute('aria-hidden', 'true');
  const low = document.createElement('span'), high = document.createElement('span');
  limits.append(low, high);
  popup.append(slider, limits);
  let active;
  const definitions = new Map(inputs.map(input => {
    const min = Number(input.min), max = Number(input.max), step = Number(input.step);
    if (![min,max,step].every(Number.isFinite) || step <= 0 || max < min) throw new Error('Invalid CAD control range');
    input.dataset.archStep = String(step);
    input.step = String(numericStep(min, max, step));
    return [input, {min, max, step}];
  }));
  const position = () => {
    if (!active) return;
    if (!active.isConnected) { close(); return; }
    const rect = active.getBoundingClientRect();
    const width = Math.min(240, Math.max(0, window.innerWidth - 16));
    popup.style.width = `${width}px`;
    popup.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - width - 8))}px`;
    popup.style.top = `${rect.bottom + popup.offsetHeight + 6 <= window.innerHeight ? rect.bottom + 6 : Math.max(8, rect.top - popup.offsetHeight - 6)}px`;
  };
  const sync = () => {
    if (!active) return;
    const {min,max,step} = definitions.get(active);
    const value = getValue(active);
    slider.value = String(value >= max ? rangeSteps(min,max,step) : Math.round((value-min)/step));
    slider.setAttribute('aria-valuetext', String(value));
  };
  const contains = target => target && (target === active || popup.contains(target));
  const outside = event => { if (!contains(event.target)) close(); };
  function close() {
    active?.setAttribute('aria-expanded', 'false');
    active = null;
    popup.remove();
    window.removeEventListener('resize', position);
    window.removeEventListener('scroll', position, true);
    document.removeEventListener('pointerdown', outside, true);
  }
  const show = input => {
    close();
    const {min,max,step} = definitions.get(input);
    if (min === max) return;
    active = input;
    input.setAttribute('aria-expanded', 'true');
    slider.min = '0'; slider.max = String(rangeSteps(min,max,step)); slider.step = '1';
    slider.setAttribute('aria-label', input.getAttribute('aria-label'));
    low.textContent = String(min); high.textContent = String(max);
    document.body.append(popup);
    sync(); position();
    window.addEventListener('resize', position);
    window.addEventListener('scroll', position, true);
    document.addEventListener('pointerdown', outside, true);
  };
  slider.addEventListener('input', () => {
    const {min,max,step} = definitions.get(active);
    setValue(active, rangeValue(Number(slider.value), min,max,step));
    sync();
  });
  popup.addEventListener('focusout', event => { if (!contains(event.relatedTarget)) close(); });
  popup.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation();
      const input = active;
      input?.focus(); close();
    }
  });
  inputs.forEach(input => {
    input.setAttribute('aria-expanded', 'false');
    input.addEventListener('focus', () => show(input));
    input.addEventListener('click', () => { if (active !== input) show(input); });
    input.addEventListener('blur', event => {
      const {min,max} = definitions.get(input);
      const numeric = input.value === '' ? NaN : Number(input.value);
      setValue(input, Number.isFinite(numeric) ? Math.min(max,Math.max(min,numeric)) : getValue(input));
      if (!contains(event.relatedTarget)) close();
    });
    input.addEventListener('keydown', event => {
      if (event.key === 'Escape') { event.stopPropagation(); close(); }
    });
  });
  return sync;
}

export function initializeArchitectureControls(ModelControls, root = document) {
const initialize = viewer => {
  const panel = root.querySelector('#arch-cad-controls');
  if (!panel || panel.dataset.ready === 'true') return;
  const status = panel.querySelector('[role="status"]');
  try {
    const configuration = JSON.parse(root.querySelector('#arch-cad-configuration').textContent);
    const controls = new ModelControls(viewer, configuration);
    const inputs = [...panel.querySelectorAll('[data-arch-control]')];
    let values = Object.fromEntries(inputs.map(input => [input.dataset.archControl, Number(input.dataset.default)]));
    let syncRange = () => {};
    const apply = () => {
      inputs.forEach(input => {
        input.value = values[input.dataset.archControl];
        input.removeAttribute('aria-invalid');
      });
      controls.setValues(values);
      syncRange();
    };
    inputs.forEach(input => {
      input.disabled = false;
      input.addEventListener('input', () => {
        const value = input.value === '' ? NaN : Number(input.value);
        if (!Number.isFinite(value) || value < Number(input.min) || value > Number(input.max)) {
          input.setAttribute('aria-invalid', 'true');
          return;
        }
        values[input.dataset.archControl] = value;
        apply();
      });
    });
    syncRange = floatingRanges(inputs, input => values[input.dataset.archControl], (input,value) => {
      values[input.dataset.archControl] = value; apply();
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
          input.removeAttribute('aria-invalid');
        });
        syncRange();
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
