require_dependency File.expand_path('../../../lib/cosmosys_arch/cad_viewer', __dir__)

module CosmosysArch
  module CadItemsHelper
    module InlineFileUrl
      def cad_preview_file_path(*arguments, **options)
        return arch_cad_file_path(@architecture_inline_issue) if @architecture_inline_issue
        super
      end
    end

    # Reuse exactly the standalone viewer's selection and authorization. Scope
    # its assigns and file URL to this render, leaving other CAD macros alone.
    class Presentation
      include CosmosysArch::CadViewer

      def initialize(issue)
        @issue = issue
        prepare_architecture_view(prepend_paths: false)
      end

      def assigns
        instance_variables.to_h { |name| [name, instance_variable_get(name)] }
      end
    end

    def render_architecture_cad_item(issue)
      assigns = Presentation.new(issue).assigns.merge(:@architecture_inline_issue => issue)
      singleton_class.prepend(InlineFileUrl) unless singleton_class < InlineFileUrl
      previous = assigns.keys.to_h { |name| [name, [instance_variable_defined?(name), instance_variable_get(name)]] }
      begin
        assigns.each { |name, value| instance_variable_set(name, value) }
        render partial: 'cosmosys_arch/cad_imports/viewer'
      ensure
        previous.each do |name, (defined, value)|
          defined ? instance_variable_set(name, value) : remove_instance_variable(name)
        end
      end
    rescue CosmosysArch::CadModel::Invalid => error
      content_tag(:p, error.message, class: 'warning')
    rescue Unauthorized
      # A visible architecture item does not grant access to its source model.
      nil
    end
  end
end
