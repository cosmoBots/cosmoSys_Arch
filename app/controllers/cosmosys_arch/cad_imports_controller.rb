require 'fileutils'
require 'tempfile'
require_dependency File.expand_path('../../../lib/cosmosys_arch/cad_viewer', __dir__)

module CosmosysArch
  class CadImportsController < ApplicationController
    include CosmosysArch::CadViewer
    before_action :find_issue
    before_action :require_import_permission, only: %i[index review create preview]
    before_action :load_model, only: :file
    helper_method :cad_preview_file_path
    rescue_from CosmosysArch::CadModel::Invalid, with: :invalid_model

    def index
      @attachments = @issue.attachments.to_a
    end

    def review
      build_plan
      @cad_report_tools_disabled = true
      @retained = @plan.selected_nodes
      begin
        @controls = @plan.selected_controls
      rescue CadModel::Invalid => error
        @review_error = error.message
        @controls = []
      end
      @attachment, @yaml = @plan.glb, @plan.yaml
      @cad_format, @cad_snapshot, @cad_image = 'glb', false, nil
      @children = @plan.model.nodes.group_by { |node| node['parent'] }
      @node_controls = @plan.model.controls.group_by { |control| control['node'] }
      @configuration = @plan.model.payload.except('controls').merge('controls' => [])
      prepend_view_path File.expand_path('../../views', __dir__)
      use_architecture_viewer_layout
      render :review
    end

    def preview
      build_plan
      serve_annotated_file(@plan.glb, @plan.yaml)
    end

    def create
      build_plan
      @plan.call(user: User.current, expected_digest: params[:plan_digest])
      redirect_to arch_cad_view_path(@issue)
    end

    def view
      prepare_architecture_view
    end

    def file
      serve_annotated_file(@attachment, @yaml)
    end

    private

    def serve_annotated_file(attachment, yaml)
      cache = Rails.root.join('tmp', 'cosmosys_arch_glb')
      FileUtils.mkdir_p(cache)
      key = Digest::SHA256.hexdigest("#{attachment.id}:#{attachment.digest}:v2")
      path = cache.join("#{key}.glb")
      File.open(cache.join("#{key}.lock"), 'a') do |lock|
        lock.flock(File::LOCK_EX)
        unless File.exist?(path)
          model = CosmosysArch::CadModel.new(glb_path: attachment.diskfile, yaml_path: yaml.diskfile, filename: attachment.filename)
          Tempfile.create(['annotated', '.glb'], cache) do |temporary|
            model.write_annotated(attachment.diskfile, temporary.path)
            File.rename(temporary.path, path)
          end
        end
      end
      send_file path, type: 'model/gltf-binary', disposition: 'inline'
    end
    def find_issue
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
      raise Unauthorized unless @issue.visible?(User.current)
    end

    def require_import_permission
      raise Unauthorized unless @project.csys_project_profile == 'architecture' && @issue.editable?(User.current) && User.current.allowed_to?(:add_issues, @project)
      raise CadModel::Invalid, 'Apply the CAD architecture migration first' unless @issue.has_attribute?(:arch_model_csid)
    end

    def build_plan
      raw = params[:choices_json].to_s
      raise CadModel::Invalid, 'Too many decisions' if raw.bytesize > 2.megabytes
      choices = raw.empty? ? {} : JSON.parse(raw)
      raise CadModel::Invalid, 'Decisions must be a mapping' unless choices.is_a?(Hash)
      @plan = CadImport.new(source: @issue, glb: @issue.attachments.find_by(id: params[:glb_id]),
        yaml: @issue.attachments.find_by(id: params[:yaml_id]), choices: choices)
    rescue JSON::ParserError => error
      raise CadModel::Invalid, error.message
    end
    def invalid_model(error)
      render_error message: error.message, status: 422
    end
  end
end
