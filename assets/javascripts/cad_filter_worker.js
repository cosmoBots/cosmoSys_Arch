// Matching is isolated so even a pathological regular expression can be stopped.
export function matchCadNodes(nodes, query, {regex = false, field = 'name'} = {}) {
  if (!query || query.length > 256) throw new Error('Use a non-empty filter of at most 256 characters');
  if (!['name', 'path'].includes(field)) throw new Error('Invalid filter field');
  const expression = regex ? new RegExp(query, 'iu') : null;
  const text = query.toLocaleLowerCase();
  return nodes.filter(node => expression ? expression.test(node[field]) :
    String(node[field]).toLocaleLowerCase().includes(text)).map(node => node.index);
}

if (typeof self !== 'undefined' && typeof document === 'undefined') {
  self.onmessage = ({data}) => {
    try { self.postMessage({indices: matchCadNodes(data.nodes, data.query, data.options)}); }
    catch (error) { self.postMessage({error: error.message}); }
  };
}
