# frozen_string_literal: true
module CosmosysArch
  class CadImport
    attr_reader :source, :glb, :yaml, :model, :choices

    def initialize(source:, glb:, yaml: nil, choices: {})
      @source, @glb, @yaml = source, glb, yaml
      raise CadModel::Invalid, 'Use an architecture project' unless source.project.csys_project_profile == 'architecture'
      raise CadModel::Invalid, 'Choose attachments of the source item' unless glb && [glb, yaml].compact.all? { |file| file.container == source }
      raise CadModel::Invalid, 'Expected GLB and optional YAML attachments' unless glb.filename.downcase.end_with?('.glb') && (!yaml || yaml.filename.downcase.end_with?('.yaml', '.yml'))
      @model = CadModel.new(glb_path: glb.diskfile, yaml_path: yaml&.diskfile, filename: glb.filename)
      defaults = Array(model.settings['disabled']).map { |path| model.resolve_node(path)['index'].to_s }
      @choices = model.nodes.to_h do |node|
        key = node['index'].to_s
        choice = choices.fetch(key, {})
        raise CadModel::Invalid, 'Each node decision must be a mapping' unless choice.is_a?(Hash)
        choice = choice.stringify_keys
        mode = choice.fetch('mode', defaults.include?(key) ? 'exclude' : 'include')
        visible = choice.fetch('visible', '1').to_s == '1'
        raise CadModel::Invalid, 'Invalid import policy' unless %w[include exclude atomic].include?(mode)
        [key, { 'mode' => mode, 'visible' => visible }]
      end
    end

    def selected_nodes
      retained = {}
      model.nodes.each do |node|
        parent = node['parent']
        next if parent && (!retained.key?(parent) || choices.fetch(parent.to_s)['mode'] == 'atomic')
        next if choices.fetch(node['index'].to_s)['mode'] == 'exclude'
        retained[node['index']] = node
      end
      retained
    end

    def selected_controls
      retained = selected_nodes
      model.controls.select do |control|
        next true if retained.key?(control['node'])
        node = model.nodes.find { |entry| entry['index'] == control['node'] }
        while node
          mode = choices.fetch(node['index'].to_s)['mode']
          break if mode == 'exclude'
          raise CadModel::Invalid, "Expand atomic subtree #{node['path']} to expose control #{control['key']}" if mode == 'atomic'
          node = model.nodes.find { |entry| entry['index'] == node['parent'] }
        end
        false
      end
    end

    def digest
      Digest::SHA256.hexdigest(JSON.generate([source.id, glb.id, glb.digest, yaml&.id, yaml&.digest, choices]))
    end

    def call(user:, expected_digest:)
      raise Unauthorized unless source.editable?(user) && user.allowed_to?(:add_issues, source.project)
      raise CadModel::Invalid, 'Files or decisions changed; repeat review' unless expected_digest == digest
      controls = selected_controls
      raise CadModel::Invalid, 'Nothing selected' if selected_nodes.empty?
      source.with_lock do
        raise CadModel::Invalid, 'This source item has already been imported' if source.cosmosys_arch_cad['model']
        structural = Tracker.find_by!(csys_key: 'arch_node')
        dof = Tracker.find_by!(csys_key: 'arch_dof')
        items = {}
        selected_nodes.each_value do |node|
          items[node['index']] = Issue.create!(project: source.project, author: user, tracker: structural,
            status: structural.default_status, subject: node['name'],
            parent_issue_id: items[node['parent']]&.id || source.id, arch_type: 'mechanical',
            arch_model_csid: source.csid, arch_node_key: node['index'].to_s,
            arch_cad_data: JSON.generate(choices.fetch(node['index'].to_s)))
        end
        controls.each do |control|
          target = items.fetch(control['node'])
          Issue.create!(project: source.project, author: user, tracker: dof, status: dof.default_status,
            parent_issue_id: target.id, subject: control['key'], arch_model_csid: source.csid,
            arch_motion: control['motion'], arch_axis: control['axis'],
            arch_space: control['space'], arch_min: control['min'], arch_max: control['max'],
            arch_default: control['default'], arch_step: control['step'])
        end
        source.reload.update!(arch_cad_data: JSON.generate('model' => model.payload.merge('choices' => choices),
          'glb' => glb.filename, 'yaml' => yaml&.filename, 'glb_digest' => glb.digest, 'yaml_digest' => yaml&.digest,
          'controls_source' => yaml ? 'yaml' : 'embedded'))
        items
      end
    end
  end
end
