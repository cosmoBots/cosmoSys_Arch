require_dependency File.expand_path('../../../cosmosys/lib/cosmosys/item_kind_registry', __dir__)
require_dependency File.expand_path('../../../cosmosys/lib/cosmosys/project_profile_registry', __dir__)

module CosmosysArch
  module ProfileRegistration
    TYPES = %w[complex optical mechanical hardware software].freeze

    module_function

    def register!
      register_item_profile!
      register_dof_profile!
      register_project_profile!
    end

    def register_item_profile!
      if Cosmosys::ItemKindRegistry.registered?('arch_node')
        existing = Cosmosys::ItemKindRegistry.fetch('arch_node')
        raise 'item profile arch_node belongs to another provider' unless existing.provider == :cosmosys_arch

        return existing
      end

      Cosmosys::ItemKindRegistry.register(
        'arch_node',
        label: :label_cosmosys_arch_item_profile_node,
        description: :text_cosmosys_arch_item_profile_node,
        provider: :cosmosys_arch,
        diagram_shape: 'box',
        diagram_fill_color: 'white',
        diagram_border_color: 'black',
        reference_mode: lambda do |_issue, kind: nil|
          %w[combined dependency hierarchy].include?(kind.to_s) ? 'csid' : 'chapter'
        end,
        can_have_children: true,
        can_split: false,
        aggregate_children: false,
        allowed_parent_profiles: %w[info arch_node].freeze,
        allowed_child_profiles: %w[arch_node arch_dof].freeze,
        dsm_mode: 'none',
        closed_presentation: 'consolidated'
      )
    end

    def register_dof_profile!
      return if Cosmosys::ItemKindRegistry.registered?('arch_dof')
      Cosmosys::ItemKindRegistry.register(
        'arch_dof', label: :label_cosmosys_arch_dof, description: :text_cosmosys_arch_dof,
        provider: :cosmosys_arch, diagram_shape: 'parallelogram', can_have_children: false,
        can_split: false, aggregate_children: false, allowed_parent_profiles: %w[arch_node],
        allowed_child_profiles: [], dsm_mode: 'none', closed_presentation: 'consolidated'
      )
    end

    def register_project_profile!
      return if Cosmosys::ProjectProfileRegistry.registered?('architecture')

      Cosmosys::ProjectProfileRegistry.register(
        'architecture',
        label: :label_cosmosys_arch_project_profile,
        description: :text_cosmosys_arch_project_profile,
        provider: :cosmosys_arch,
        required_trackers: [
          { key: 'arch_node', name: 'archNode', item_profile: 'arch_node' }.freeze,
          { key: 'arch_dof', name: 'archDoF', item_profile: 'arch_dof' }.freeze
        ].freeze,
        default_root_tracker: 'cs_info',
        default_report_columns: %w[tracker status arch_type],
        default_report_field_presentations: { 'arch_type' => 'metadata' }.freeze,
        default_item_list_columns: %w[chapter_label subject tracker status arch_type priority]
      )
    end
  end
end

CosmosysArch::ProfileRegistration.register!
