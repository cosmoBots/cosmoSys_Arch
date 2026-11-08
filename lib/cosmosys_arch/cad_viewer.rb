module CosmosysArch
  # Shared preparation for standalone and integrated CAD viewers. Both paths
  # enforce source/attachment visibility before rendering the same partial.
  module CadViewer
    private

    def prepare_architecture_view(prepend_paths: true)
      load_model
      # Slider poses are session-local, not editorial report views.
      @cad_format, @cad_snapshot, @cad_image = 'glb', false, nil
      @node_items = Issue.where(project_id: @source.project.root.self_and_descendants.select(:id), arch_model_csid: @source.csid).includes(:tracker).to_a
      @node_items.select! { |item| item.visible?(User.current) }
      selected = @issue.arch_node_key.presence || @issue.cosmosys_arch_parent_node&.arch_node_key
      @cad_report_view_name = selected ? "arch-node-#{selected}" : 'arch-model'
      nodes = @spec.fetch('model').fetch('nodes')
      if @issue.cosmosys_arch_node? && (selected.nil? || nodes.none? { |node| node['index'].to_s == selected })
        raise CadModel::Invalid, 'The architecture item has no valid CAD node reference'
      end
      subtree = {}
      nodes.each { |node| subtree[node['index']] = true if selected.nil? || node['index'].to_s == selected || subtree[node['parent']] }
      target_items = @node_items.select { |item| item.cosmosys_arch_node? && subtree[item.arch_node_key.to_i] }
      targets = target_items.index_by(&:id)
      @dofs = Issue.where(parent_id: targets.keys).includes(:tracker).select do |item|
        item.cosmosys_item_kind_key == 'arch_dof' && item.visible?(User.current)
      end
      geometry = {}
      node_map = @node_items.select(&:cosmosys_arch_node?).to_h { |item| [item.arch_node_key.to_i, item] }
      nodes.each do |node|
        item = node_map[node['index']]
        parent = geometry[node['parent']]
        policy = @spec.dig('model', 'choices', node['index'].to_s) || {}
        geometry[node['index']] = if policy['mode'] == 'exclude'
          { 'included' => false, 'visible' => false }
        elsif item
          { 'included' => true, 'visible' => item.cosmosys_arch_cad.fetch('visible', true) && (parent.nil? || parent['visible']),
            'atomic' => item.cosmosys_arch_cad['mode'] == 'atomic' }
        elsif parent && parent['atomic']
          parent.merge('visible' => parent['visible'] && policy.fetch('visible', true))
        else
          { 'included' => false, 'visible' => false }
        end
      end
      @configuration = @spec.fetch('model').slice('transform', 'node_transforms', 'rotation_order').merge(
        'visible_nodes' => nodes.filter_map { |node| node['index'] if subtree[node['index']] && geometry.dig(node['index'], 'included') && geometry.dig(node['index'], 'visible') },
        'controls' => @dofs.map do |item|
          { 'key' => item.csid, 'node' => targets.fetch(item.parent_id).arch_node_key.to_i,
            'motion' => item.arch_motion, 'space' => item.arch_space, 'axis' => item.arch_axis,
            'default' => item.arch_default, 'min' => item.arch_min, 'max' => item.arch_max, 'step' => item.arch_step }
        end)
      @piece_views = CosmosysArch::PieceViews.new(@attachment, @cad_report_view_name, @configuration)
      prepend_view_path File.expand_path('../../app/views', __dir__) if prepend_paths
    end
    # Reuse the upstream viewer template, but serve our annotated derivative.
    def cad_preview_file_path(_attachment)
      @plan ? arch_cad_preview_path(@issue, glb_id: @plan.glb.id, yaml_id: @plan.yaml.id) : arch_cad_file_path(@issue)
    end

    def load_model
      if @issue.cosmosys_item_kind_key == 'arch_dof'
        raise Unauthorized unless @issue.cosmosys_arch_parent_node&.visible?(User.current)
      end
      @source = @issue.cosmosys_arch_model
      raise Unauthorized unless @source&.visible?(User.current)
      @spec = @source.cosmosys_arch_cad
      @attachment = @source.attachments.find_by(filename: @spec['glb'])
      @yaml = @source.attachments.find_by(filename: @spec['yaml'])
      raise CadModel::Invalid, 'Source files missing or replaced; create a new import' unless
        @attachment&.visible?(User.current) && @yaml&.visible?(User.current) &&
        @attachment.digest == @spec['glb_digest'] && @yaml.digest == @spec['yaml_digest']
    end
  end
end
