module CosmosysArch
  # CAD parentage/order, not the independently editable Redmine item hierarchy.
  # Receives only authorized items; missing ancestors are never named or linked.
  class CadNavigation
    def self.build(nodes:, items:, selected:, source: nil)
      by_index = nodes.to_h { |node| [node.fetch('index').to_s, node] }
      by_key = items.to_h { |item| [item.arch_node_key.to_s, item] }
      branches = nodes.filter_map do |node|
        key = node.fetch('index').to_s
        item = by_key[key]
        [key, { item: item, children: [], current: key == selected.to_s, open: false }] if item
      end.to_h
      ancestors = lambda do |key|
        path, seen = [], { key => true }
        parent = by_index[key]&.fetch('parent', nil)
        until parent.nil? || seen[parent.to_s]
          parent = parent.to_s
          seen[parent] = true
          path << parent
          parent = by_index[parent]&.fetch('parent', nil)
        end
        path
      end
      ancestors.call(selected.to_s).each { |key| branches[key][:open] = true if branches[key] }
      roots = branches.each_with_object([]) do |(key, branch), roots|
        parent = ancestors.call(key).find { |ancestor| branches.key?(ancestor) }
        (parent ? branches.fetch(parent)[:children] : roots) << branch
      end
      # The source item is the whole GLB, even with several scene roots or
      # no imported item for its structural container. No synthetic PBS item.
      return roots unless source && items.none? { |item| item == source }

      [{ item: source, children: roots, current: selected.nil?, open: !selected.nil? }]
    end
  end
end
