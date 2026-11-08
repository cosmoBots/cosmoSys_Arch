require_dependency File.expand_path('../../../lib/cosmosys_arch/cad_viewer', __dir__)

module CosmosysArch
  module CadItemsHelper
    REPORT_PIECE_MAX_HEIGHT_PX = 450

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

    def render_architecture_cad_item(issue, report: false)
      assigns = Presentation.new(issue).assigns.merge(:@architecture_inline_issue => issue)
      singleton_class.prepend(InlineFileUrl) unless singleton_class < InlineFileUrl
      previous = assigns.keys.to_h { |name| [name, [instance_variable_defined?(name), instance_variable_get(name)]] }
      begin
        assigns.each { |name, value| instance_variable_set(name, value) }
        render partial: 'cosmosys_arch/cad_imports/piece_image', locals: {report: report}
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

    # Reuse the detail view's selection, signature and visibility. HTML may
    # prepare missing captures; server-side office/PDF export uses only PNGs,
    # never an internal HTTP fetch or a WebGL bootstrap in the printed report.
    def render_architecture_cad_report_figure(issue, server_export: false)
      return unless issue.cosmosys_arch_node? && issue.visible?(User.current) &&
        issue.project.csys_project_profile == 'architecture'

      views = Presentation.new(issue).assigns.fetch(:@piece_views)
      saved = views.find
      unless views.current?(saved) && saved.image.visible?(User.current)
        return render_architecture_cad_item(issue, report: true) unless server_export

        return content_tag(:p, safe_join([
          l(:text_cad_preview_no_views), ' ', link_to(issue.subject, arch_cad_view_path(issue))
        ]), class: 'cosmosys-arch-report-figure-missing')
      end

      png = File.binread(saved.image.diskfile)
      width, height = CadPreviewView.png_dimensions(png)
      scale = [REPORT_PIECE_MAX_HEIGHT_PX.to_f / height, 1.0].min
      width, height = [width, height].map { |size| [(size * scale).floor, 1].max }
      content_tag(:p, image_tag("data:image/png;base64,#{Base64.strict_encode64(png)}",
        alt: issue.subject, width: width, height: height,
        style: "width:#{width}px;height:auto;max-width:100%;max-height:#{REPORT_PIECE_MAX_HEIGHT_PX}px"),
        class: 'cosmosys-arch-report-figure', style: 'text-align:center')
    rescue CosmosysArch::CadModel::Invalid => error
      content_tag(:p, error.message, class: 'warning')
    rescue Unauthorized
      nil
    end
  end
end
