require 'digest'

module CosmosysArch
  # Release only the source's import state. Never delete items, attachments,
  # cameras or bindings; a populated model must be resolved by the user first.
  class CadImportReset
    def initialize(source, user:)
      @source, @user = source, user
    end

    def digest
      Digest::SHA256.hexdigest(@source.arch_cad_data.to_s)
    end

    def blocked_reason
      return :text_cosmosys_arch_reset_not_source if @source.arch_model_csid.present? || !@source.cosmosys_arch_cad['model']
      return :text_cosmosys_arch_reset_has_items if @source.children.exists? ||
        Issue.where(project_id: @source.project.root.self_and_descendants.select(:id), arch_model_csid: @source.csid).exists?

      nil
    end

    def call(expected_digest:)
      raise Unauthorized unless @source.project.csys_project_profile == 'architecture' &&
        @source.visible?(@user) && @source.editable?(@user) && @user.allowed_to?(:add_issues, @source.project)

      @source.with_lock do
        raise CadModel::Invalid, I18n.t(:text_cosmosys_arch_reset_changed) unless expected_digest == digest
        reason = blocked_reason
        raise CadModel::Invalid, I18n.t(reason) if reason

        @source.update!(arch_cad_data: nil)
        @source.journals.create!(user: @user, notes: I18n.t(:text_cosmosys_arch_reset_done))
      end
    end
  end
end
