# frozen_string_literal: true
require 'json'
require 'yaml'
require 'digest'

module CosmosysArch
  # Read only the GLB JSON chunk, never tessellate geometry on the server.
  class CadModel
    class Invalid < StandardError; end
    MAX_JSON = 32 * 1024 * 1024
    attr_reader :nodes, :controls, :settings, :document, :json_size

    def initialize(glb_path:, yaml_path: nil, filename:)
      File.open(glb_path, 'rb') do |file|
        header = file.read(12)
        raise Invalid, 'Invalid GLB header' unless header&.bytesize == 12
        magic, version, total = header.unpack('a4V2')
        raise Invalid, 'Expected GLB 2.0' unless magic == 'glTF' && version == 2 && total == file.size
        raise Invalid, 'GLB exceeds 512 MiB' if total > 512 * 1024 * 1024
        chunk = file.read(8)
        raise Invalid, 'Missing GLB JSON' unless chunk&.bytesize == 8
        @json_size, type = chunk.unpack('V2')
        raise Invalid, 'Invalid GLB JSON chunk' unless type == 0x4e4f534a && @json_size <= MAX_JSON && @json_size <= total - 20
        @document = JSON.parse(file.read(@json_size))
      end
      raise Invalid, 'Expected GLB document and nodes' unless document.is_a?(Hash) && document['nodes'].is_a?(Array)
      raise Invalid, 'Too many GLB nodes' if document.fetch('nodes').size > 20_000
      build_nodes
      embedded = embedded_settings
      if yaml_path
        raise Invalid, 'YAML exceeds 2 MiB' if File.size(yaml_path) > 2 * 1024 * 1024
        yaml = YAML.safe_load_file(yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise Invalid, 'Expected YAML models mapping' unless yaml.is_a?(Hash) && yaml['models'].is_a?(Hash)
        @settings = yaml.fetch('models').fetch(filename)
      else
        @settings = embedded
        raise Invalid, 'GLB has no embedded controls contract; choose a YAML attachment' unless settings
      end
      raise Invalid, 'Model settings must be a mapping' unless settings.is_a?(Hash)
      @rotation_order = settings.fetch('rotation_order', 'XYZ')
      validate_rotation_order(@rotation_order)
      @controls = normalized_controls(settings.fetch('controls', {}))
      transform = settings.fetch('transform', settings)
      @model_transform = normalized_transform(transform)
      raise Invalid, 'Node transforms must be a mapping' unless settings.fetch('node_transforms', {}).is_a?(Hash)
      @overrides = settings.fetch('node_transforms', {}).to_h do |path, transform|
        [resolve_node(path).fetch('index').to_s, normalized_transform(transform)]
      end
      if embedded && yaml_path
        same_controls = controls.sort_by { |control| control['key'] } == normalized_controls(embedded.fetch('controls')).sort_by { |control| control['key'] }
        raise Invalid, 'GLB annotations and YAML disagree; use matching files' unless same_controls && @rotation_order == embedded['rotation_order']
        raise Invalid, 'GLB annotations cannot be combined with YAML pose overrides' unless (@model_transform.keys - ['rotation_order']).empty? && @overrides.empty?
      end
    rescue KeyError, TypeError, ArgumentError, JSON::ParserError, Psych::Exception => error
      raise Invalid, error.message
    end

    def normalized_controls(mapping)
      raise Invalid, 'Controls must be a mapping' unless mapping.is_a?(Hash)
      mapping.map do |key, value|
        raise Invalid, 'Control must be a mapping' unless value.is_a?(Hash)
        target = resolve_node(value.fetch('target_node'))
        motion = value.fetch('transform', 'position')
        space = value.fetch('space', 'local')
        axis = value.fetch('axis', 'x')
        raise Invalid, "Unsupported control #{key}" unless %w[position rotation].include?(motion) && %w[local global].include?(space) && %w[x y z].include?(axis)
        min, max, step = [value.fetch('min'), value.fetch('max'), value.fetch('step', 0.0001)].map { |number| Float(number) }
        raise Invalid, "Invalid limits for #{key}; zero must be in range" unless [min, max, step].all?(&:finite?) && min <= 0 && max >= 0 && min < max && step.positive?
        { 'key' => key.to_s, 'node' => target.fetch('index'), 'motion' => motion, 'space' => space,
          'axis' => axis, 'min' => min, 'max' => max, 'default' => 0.0, 'step' => step }
      end
    end
    private :normalized_controls

    def payload
      { 'nodes' => nodes, 'controls' => controls, 'rotation_order' => @rotation_order, 'transform' => @model_transform,
        'node_transforms' => @overrides }
    end

    def resolve_node(name)
      matches = nodes.select { |node| node['name'] == name || node['path'] == name || node['path'].end_with?("/#{name}") }
      raise Invalid, "Node #{name.inspect}: #{matches.size} matches" unless matches.one?
      matches.first
    end

    # Annotated derivative only: keep the original GLB and its binary chunks intact.
    def write_annotated(glb_path, destination)
      document.fetch('nodes', []).each_with_index do |node, index|
        node['extras'] = {} unless node['extras'].is_a?(Hash)
        node['extras']['cosmosys_cad_node_index'] = index
      end
      json = JSON.generate(document)
      json += ' ' * ((4 - json.bytesize % 4) % 4)
      remaining = File.size(glb_path) - 20 - json_size
      File.open(destination, 'wb') do |out|
        out.write(['glTF', 2, 20 + json.bytesize + remaining].pack('a4V2'))
        out.write([json.bytesize, 0x4e4f534a].pack('V2'))
        out.write(json)
        File.open(glb_path, 'rb') { |input| input.seek(20 + json_size); IO.copy_stream(input, out) }
      end
    end

    private

    def embedded_settings
      schemas, mapping = [], {}
      reachable = nodes.to_h { |node| [node['index'], node] }
      document.fetch('nodes').each_with_index do |raw, index|
        extras = raw.is_a?(Hash) && raw['extras'].is_a?(Hash) ? raw['extras'] : {}
        next unless extras.key?('cosmosys_model') || extras.key?('cosmosys_controls')
        owner = reachable[index]
        raise Invalid, 'Embedded annotation outside the active scene' unless owner
        if extras.key?('cosmosys_model')
          schema = extras['cosmosys_model']
          raise Invalid, 'Embedded model contract must be on a scene root' unless owner['parent'].nil?
          raise Invalid, 'Unsupported embedded controls contract' unless schema.is_a?(Hash) && schema['schema'] == 'cosmosys.cad.controls' && schema['version'] == 1 && schema['rotation_order'] == 'XYZ'
          schemas << schema
        end
        annotations = extras.fetch('cosmosys_controls', {})
        raise Invalid, 'Embedded controls must be a mapping' unless annotations.is_a?(Hash)
        annotations.each do |key, value|
          raise Invalid, 'Empty or duplicate embedded control key' unless key.is_a?(String) && !key.strip.empty? && !mapping.key?(key)
          required = %w[target_node transform space axis min max step]
          raise Invalid, "Incomplete embedded control #{key}" unless value.is_a?(Hash) && required.all? { |field| value.key?(field) }
          raise Invalid, "Invalid embedded control #{key}" unless value['target_node'].is_a?(String) && !value['target_node'].empty? && %w[min max step].all? { |field| value[field].is_a?(Numeric) && value[field].finite? }
          raise Invalid, "Embedded control #{key} targets another node" unless resolve_node(value['target_node'])['index'] == index
          mapping[key] = value
        end
      end
      return nil if schemas.empty? && mapping.empty?
      raise Invalid, 'Expected exactly one embedded model contract' unless schemas.one?
      { 'rotation_order' => schemas.first['rotation_order'], 'controls' => mapping }
    end

    def normalized_transform(value)
      raise Invalid, 'Transform must be a mapping' unless value.is_a?(Hash)
      result = {}
      if value.key?('rotation_order')
        validate_rotation_order(value['rotation_order'])
        result['rotation_order'] = value['rotation_order']
      end
      %w[translation rotation_degrees].each_with_object(result) do |key, result|
        next unless value.key?(key)
        vector = value[key]
        raise Invalid, "Invalid #{key}" unless vector.is_a?(Array) && vector.size == 3 && vector.all? { |n| n.is_a?(Numeric) && n.finite? }
        result[key] = vector
      end
    end

    def validate_rotation_order(order)
      raise Invalid, 'Invalid Euler rotation order' unless %w[XYZ YXZ ZXY ZYX YZX XZY].include?(order)
    end

    def build_nodes
      raw = document.fetch('nodes')
      raise Invalid, 'Expected GLB nodes and scenes' unless raw.is_a?(Array) && document['scenes'].is_a?(Array)
      roots = document.fetch('scenes').fetch(document.fetch('scene', 0)).fetch('nodes')
      raise Invalid, 'Expected scene root array' unless roots.is_a?(Array)
      @nodes = []
      seen = {}
      visit = lambda do |index, parent, path, depth|
        raise Invalid, 'Invalid, repeated or excessively deep node' unless index.is_a?(Integer) && index >= 0 && index < raw.size && !seen[index] && depth <= 128
        seen[index] = true
        node = raw.fetch(index)
        raise Invalid, 'Expected node mapping' unless node.is_a?(Hash)
        name = node['name'].to_s.empty? ? "node_#{index}" : node['name'].to_s
        node_path = (path + [name]).join('/')
        children = node.fetch('children', [])
        raise Invalid, 'Expected child index array' unless children.is_a?(Array)
        nodes << { 'index' => index, 'parent' => parent, 'name' => name, 'path' => node_path,
                   'children' => children, 'depth' => depth }
        children.each { |child| visit.call(child, index, path + [name], depth + 1) }
      end
      roots.each { |root| visit.call(root, nil, [], 0) }
    end
  end
end
