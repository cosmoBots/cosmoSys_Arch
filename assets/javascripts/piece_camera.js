// Camera/appearance only. PNGs are captured at default DoF values; no runtime
// state is stored or commanded, including when the visible sliders were moved.
export function initializePieceCamera(ModelControls, captureImage, panel = document.querySelector('[data-piece-camera]'), completed = () => {}, signal) {
  if (!panel || panel.dataset.initialized) return;
  panel.dataset.initialized = 'true';
  const automatic = panel.dataset.automatic === 'true';
  const wrapper = panel.closest('[data-architecture-piece-bootstrap]') || document;
  const element = wrapper.querySelector('[data-cad-preview]');
  const status = automatic ? wrapper.querySelector('[role="status"]') : panel.querySelector('[role="status"]');
  let initialized = false;
  const start = async viewer => {
    if (initialized) return;
    initialized = true;
    const buttons = [...panel.querySelectorAll('button')];
    const release = () => {
      if (!automatic || !wrapper.querySelector('[data-piece-renderer]')) return;
      viewer.controls.dispose();
      const renderer = viewer.getRenderContext().renderer;
      renderer.dispose();
      renderer.forceContextLoss();
      wrapper.querySelector('[data-piece-renderer]').remove();
    };
    buttons.forEach(button => button.disabled = true);
    try {
      // Let the existing synchronous slider initializer handle the same ready
      // event first, irrespective of the order of the two module scripts.
      await Promise.resolve();
      const config = JSON.parse(panel.querySelector('[data-piece-configuration]').textContent);
      let controls = automatic ? new ModelControls(viewer, config) : null;
      // The viewer and slider modules can finish loading in either order.
      for (let attempt = 0; !controls && attempt < 200; attempt++) {
        const target = document.querySelector('#arch-cad-controls');
        controls = target?.archControls;
        if (controls || target?.dataset.error === 'true') break;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      if (!controls) throw new Error('CAD controls are not ready');
      if (automatic) controls.fitVisible();
      const request = async (method = 'GET', body) => {
        const response = await fetch(panel.dataset.url, {method, signal, headers: {'Content-Type':'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''},
          ...(body ? {body:JSON.stringify(body)} : {})});
        const result = await response.json();
        if (!response.ok) {
          const error = new Error(result.error || `HTTP ${response.status}`);
          error.status = response.status;
          throw error;
        }
        return result;
      };
      let {views, signature} = await request();
      const choice = panel.querySelector('[data-piece-choice]');
      const refresh = (selected = 'default') => {
        if (!choice) return;
        choice.replaceChildren(...views.map(view => new Option(view.name === 'default' ? panel.dataset.defaultLabel : view.name, view.name)));
        choice.value = selected;
      };
      const restore = view => { if (view) viewer.restoreView(view.state); };
      const defaultView = views.find(view => view.name === 'default');
      restore(defaultView);
      refresh();
      // Runtime/simulation contexts share the piece camera, but never capture,
      // reset DoFs or expose editorial save controls.
      if (panel.dataset.readOnly === 'true') {
        panel.dataset.ready = 'true';
        return;
      }
      const take = () => {
        const inputs = [...document.querySelectorAll('[data-arch-control]')];
        const values = Object.fromEntries(inputs.map(input => [input.dataset.archControl,
          Number(input.parentElement.querySelector('output').textContent)]));
        try {
          controls.setValues({});
          return {state: viewer.exportView(), image: captureImage(viewer).toDataURL('image/png')};
        } finally { controls.setValues(values); }
      };
      const save = async (name, capture = take()) => {
        const previous = views.find(view => view.name === name);
        const result = await request('PUT', {name, view: {state:capture.state, image:capture.image.split(',')[1],
          signature, revision:previous?.revision}});
        views = views.filter(view => view.name !== name).concat(result.view);
        refresh(name);
        return result.view;
      };
      if (automatic) {
        const capture = take();
        const image = wrapper.querySelector('[data-piece-generated-image]');
        image.querySelector('img').src = capture.image;
        image.hidden = false;
        wrapper.querySelector('[data-piece-fallback]')?.setAttribute('hidden', '');
        status.textContent = '';
        if (!defaultView?.current && panel.dataset.canSave === 'true') {
          try { await save('default', capture); }
          catch (error) { if (error.status !== 409) status.textContent = error.message; }
        } else if (!defaultView?.current && wrapper.dataset?.reportPiece !== undefined) {
          status.textContent = wrapper.dataset.unsavedLabel;
        }
        // Remove the temporary renderer from the page once the PNG is ready.
        release();
        panel.dataset.ready = 'true';
        return;
      }
      const run = async action => {
        buttons.forEach(button => button.disabled = true);
        try { await action(); status.textContent = panel.dataset.savedLabel; }
        catch (error) { status.textContent = error.message; }
        finally { buttons.forEach(button => button.disabled = false); }
      };
      panel.querySelector('[data-piece-restore]').addEventListener('click', () => {
        restore(views.find(view => view.name === choice.value));
        status.textContent = panel.dataset.restoredLabel;
      });
      choice.addEventListener('change', () => {
        const name = panel.querySelector('[data-piece-name]');
        if (name) name.value = choice.value;
      });
      panel.querySelector('[data-piece-save]')?.addEventListener('click', () => run(() => save(panel.querySelector('[data-piece-name]').value.trim().toLowerCase())));
      panel.querySelector('[data-piece-default]')?.addEventListener('click', () => run(() => save('default')));
      buttons.forEach(button => button.disabled = false);
      panel.dataset.ready = 'true';
    } catch (error) {
      status.textContent = error.message;
      panel.dataset.error = 'true';
      release();
    } finally {
      if (automatic) completed();
    }
  };
  element.addEventListener('cad-preview:ready', event => start(event.detail.viewer));
  element.addEventListener('cad-preview:error', () => {
    status.textContent = element.querySelector('.cad-preview-status')?.textContent || 'CAD loading failed';
    panel.dataset.error = 'true';
    if (automatic) completed();
  });
  if (element.cadViewer) start(element.cadViewer);
}
