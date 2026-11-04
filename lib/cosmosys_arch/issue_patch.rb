module CosmosysArch
  module IssuePatch
    TYPES = CosmosysArch::ProfileRegistration::TYPES
    CAD_FIELDS = %w[arch_motion arch_axis arch_space arch_min arch_max arch_default arch_step].freeze
    attr_accessor :cosmosys_arch_restoring_hierarchy

    def self.included(base)
      base.safe_attributes('arch_type')
      base.safe_attributes(*CAD_FIELDS)
      base.before_validation :cosmosys_arch_apply_defaults, on: :create
      base.before_validation :cosmosys_arch_sync_dof_model
      base.validate :cosmosys_arch_validate_type
      base.validate :cosmosys_arch_validate_dof
    end

    def cosmosys_arch_node?
      cosmosys_item_kind_key == 'arch_node'
    end

    def cosmosys_arch_cad
      return {} unless has_attribute?(:arch_cad_data)
      JSON.parse(arch_cad_data.presence || '{}')
    rescue JSON::ParserError
      {}
    end

    def cosmosys_arch_resolve(csid)
      return nil if csid.blank?
      Issue.where(project_id: project.root.self_and_descendants.select(:id), csid: csid).first
    end

    def cosmosys_arch_model
      return nil unless has_attribute?(:arch_model_csid)
      return cosmosys_arch_parent_node&.cosmosys_arch_model if cosmosys_item_kind_key == 'arch_dof'
      arch_model_csid.present? ? cosmosys_arch_resolve(arch_model_csid) : (cosmosys_arch_cad['model'].present? ? self : nil)
    end

    def cosmosys_arch_parent_node
      return nil unless cosmosys_item_kind_key == 'arch_dof'
      # Redmine's parent_issue_id is a pending hierarchy edit until before_save.
      candidate = parent_issue_id.to_s == parent_id.to_s ? parent : Issue.find_by(id: parent_issue_id)
      candidate if candidate&.cosmosys_arch_node?
    end

    private

    def cosmosys_arch_validate_dof
      return unless cosmosys_item_kind_key == 'arch_dof' && has_attribute?(:arch_motion)
      errors.add(:arch_motion, :inclusion) unless %w[position rotation].include?(arch_motion)
      errors.add(:arch_axis, :inclusion) unless %w[x y z].include?(arch_axis)
      errors.add(:arch_space, :inclusion) unless %w[local global].include?(arch_space)
      values = [arch_min, arch_max, arch_default, arch_step]
      unless values.all? { |value| value.is_a?(Numeric) && value.finite? } && arch_min < arch_max &&
             arch_default.between?(arch_min, arch_max) && arch_step.positive?
        errors.add(:base, 'Invalid degree-of-freedom limits, default or step')
      end
      errors.add(:parent_issue_id, :invalid) unless cosmosys_arch_restoring_hierarchy || cosmosys_arch_parent_node
    end

    def cosmosys_arch_sync_dof_model
      return unless cosmosys_item_kind_key == 'arch_dof' && has_attribute?(:arch_model_csid)
      return if cosmosys_arch_restoring_hierarchy
      self.arch_model_csid = cosmosys_arch_parent_node&.arch_model_csid
    end

    def cosmosys_arch_apply_defaults
      self.arch_type ||= 'complex' if cosmosys_arch_node?
      return unless cosmosys_item_kind_key == 'arch_dof' && has_attribute?(:arch_motion)
      self.arch_motion ||= 'position'
      self.arch_axis ||= 'x'
      self.arch_space ||= 'local'
      self.arch_min = -1 if arch_min.nil?
      self.arch_max = 1 if arch_max.nil?
      self.arch_default = 0 if arch_default.nil?
      self.arch_step = 0.01 if arch_step.nil?
    end

    def cosmosys_arch_validate_type
      return unless cosmosys_arch_node?

      errors.add(:arch_type, :blank) if arch_type.blank?
      errors.add(:arch_type, :inclusion) if arch_type.present? && !TYPES.include?(arch_type)
    end
  end
end

Issue.include(CosmosysArch::IssuePatch) unless Issue < CosmosysArch::IssuePatch
