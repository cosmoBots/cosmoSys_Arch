// Reports can contain many uncaptured pieces. Instantiate one temporary
// viewer at a time, release it, then prepare the next piece. Templates are
// inert until their turn, so the native loader cannot start all contexts.
let queue = Promise.resolve();
export function initializeReportPieceCameras(ModelControls, captureImage, initializePieceCamera) {
  document.querySelectorAll('[data-report-piece]').forEach(wrapper => {
    if (wrapper.dataset.queued) return;
    wrapper.dataset.queued = 'true';
    queue = queue.then(() => new Promise(resolve => {
      const panel = wrapper.querySelector('[data-piece-camera]');
      const template = wrapper.querySelector('[data-piece-renderer-template]');
      const controller = new AbortController();
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        wrapper.dataset.cosmosysReportResource = panel.dataset.error ? 'failed' : 'ready';
        resolve();
      };
      const timer = setTimeout(() => {
        panel.dataset.error = 'true';
        wrapper.querySelector('[role="status"]').textContent = wrapper.dataset.timeoutLabel;
        controller.abort();
        const viewer = wrapper.querySelector('[data-cad-preview]')?.cadViewer;
        if (viewer) {
          viewer.controls.dispose();
          const renderer = viewer.getRenderContext().renderer;
          renderer.dispose(); renderer.forceContextLoss();
        }
        wrapper.querySelector('[data-piece-renderer]')?.remove();
        finish();
      }, 120000);
      try {
        template.replaceWith(template.content.cloneNode(true));
        initializePieceCamera(ModelControls, captureImage, panel, finish, controller.signal);
      } catch (error) {
        panel.dataset.error = 'true';
        wrapper.querySelector('[role="status"]').textContent = error.message;
        wrapper.querySelector('[data-piece-renderer]')?.remove();
        finish();
      }
    }));
  });
}
