class CreateCosmosysArchitecture < ActiveRecord::Migration[6.1]
  def up
    add_column :issues, :arch_type, :string unless column_exists?(:issues, :arch_type)
    add_index :issues, :arch_type unless index_exists?(:issues, :arch_type)
    install_tracker
  end

  def down
    issue_class = Class.new(ActiveRecord::Base) { self.table_name = 'issues' }
    populated = column_exists?(:issues, :arch_type) && issue_class.where.not(arch_type: nil).exists?
    raise 'Cannot remove populated architecture node types; export them before rollback' if populated

    remove_index :issues, :arch_type if index_exists?(:issues, :arch_type)
    remove_column :issues, :arch_type if column_exists?(:issues, :arch_type)
  end

  private

  def tracker_class
    @tracker_class ||= Class.new(ActiveRecord::Base) { self.table_name = 'trackers' }.tap(&:reset_column_information)
  end

  def install_tracker
    source = tracker_class.find_by(csys_key: 'requirement')
    raise 'cosmoSys Architecture requires the csRq tracker from cosmoSys-Req to be migrated first' unless source
    raise 'cosmoSys Architecture requires csRq to have a default status' if source.default_status_id.blank?

    tracker = tracker_class.find_by(csys_key: 'arch_node') || tracker_class.new
    tracker.assign_attributes(
      name: 'archNode', csys_key: 'arch_node', csys_item_kind: 'arch_node',
      default_status_id: source.default_status_id
    )
    tracker.save!
    copy_workflows(source.id, tracker.id)
    add_to_architecture_projects(tracker.id)
  end

  def copy_workflows(source_id, tracker_id)
    return unless table_exists?(:workflows) && source_id.to_i != tracker_id.to_i

    workflow_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'workflows'
      self.inheritance_column = :_disabled_type
    end
    workflow_class.where(tracker_id: tracker_id).delete_all
    workflow_class.where(tracker_id: source_id).find_each do |workflow|
      workflow_class.create!(workflow.attributes.except('id').merge('tracker_id' => tracker_id))
    end
  end

  def add_to_architecture_projects(tracker_id)
    return unless table_exists?(:projects_trackers) && column_exists?(:projects, :csys_project_profile)

    project_class = Class.new(ActiveRecord::Base) { self.table_name = 'projects' }
    assignment_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'projects_trackers'
      self.primary_key = nil
    end
    project_class.where(csys_project_profile: 'architecture').find_each do |project|
      assignment_class.find_or_create_by!(project_id: project.id, tracker_id: tracker_id)
    end
  end
end
