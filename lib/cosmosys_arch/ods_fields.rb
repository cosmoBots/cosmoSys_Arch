require_dependency File.expand_path('../../../cosmosys/lib/cosmosys/ods_item_field_registry', __dir__)

module CosmosysArch
  module OdsFields
    module_function

    def register!
      return if Cosmosys::OdsItemFieldRegistry.names.include?('arch_type')

      Cosmosys::OdsItemFieldRegistry.register(
        'arch_type',
        reader: ->(issue) { issue.cosmosys_item_kind_key == 'arch_node' ? issue.arch_type : nil },
        writer: ->(issue, value) { issue.arch_type = value if issue.cosmosys_item_kind_key == 'arch_node' }
      )
      %w[arch_node_key arch_cad_data arch_motion arch_axis arch_space arch_min arch_max arch_default arch_step].each do |name|
        next if Cosmosys::OdsItemFieldRegistry.names.include?(name)
        Cosmosys::OdsItemFieldRegistry.register(name,
          reader: ->(issue) { issue.has_attribute?(name) ? issue.public_send(name) : nil },
          writer: lambda do |issue, value|
            if issue.has_attribute?(name)
              issue.cosmosys_arch_restoring_hierarchy = true
              issue.public_send("#{name}=", value)
            end
          end)
      end
      %w[arch_model_csid].each do |name|
        next if Cosmosys::OdsItemFieldRegistry.names.include?(name)
        Cosmosys::OdsItemFieldRegistry.register(name, deferred: true,
          reader: ->(issue) { issue.has_attribute?(name) ? issue.public_send(name) : nil },
          remapper: ->(value, context) { context.fetch(:csid_map, {}).fetch(value, value) },
          writer: ->(issue, value) { issue.public_send("#{name}=", value) if issue.has_attribute?(name) })
      end
    end
  end
end

CosmosysArch::OdsFields.register!
