require 'redmine'

Redmine::Plugin.register :cosmosys_arch do
  directory File.expand_path(__dir__)
  name 'cosmoSys Architecture'
  author 'cosmoBots.eu'
  description 'Product architecture profiles for cosmoSys.'
  version '0.1.3'
  url 'https://cosmobots.eu'
  author_url 'https://cosmobots.eu'

  requires_redmine_plugin :cosmosys, version_or_higher: '0.2.8'
  requires_redmine_plugin :cosmosys_cad_preview, version_or_higher: '0.1.3'
  requires_redmine_plugin :cosmosys_req, version_or_higher: '0.3.5'
end

require_dependency 'issue'
require_dependency 'issue_query'
require_dependency 'tracker'
require_dependency File.expand_path('lib/cosmosys_arch/profile_registration', __dir__)
require_dependency File.expand_path('lib/cosmosys_arch/issue_patch', __dir__)
require_dependency File.expand_path('lib/cosmosys_arch/issue_query_patch', __dir__)
require_dependency File.expand_path('lib/cosmosys_arch/ods_fields', __dir__)
require_dependency File.expand_path('lib/cosmosys_arch/hooks', __dir__)

class CosmosysArchMaterializationListener < Redmine::Hook::Listener
  def after_plugins_loaded(_context = {})
    Cosmosys::ProjectSnapshotMaterializationCallbacks.register(:architecture_cad) do |context|
      context.fetch(:items).each do |item|
        next unless item.cosmosys_item_kind_key == 'arch_dof'
        item.cosmosys_arch_restoring_hierarchy = false
        item.reload.validate!
      end
    end
  end
end
