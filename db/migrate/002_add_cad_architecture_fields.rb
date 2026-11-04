class AddCadArchitectureFields < ActiveRecord::Migration[6.1]
  STRINGS = %i[arch_model_csid arch_node_key arch_motion arch_axis arch_space].freeze
  NUMBERS = %i[arch_min arch_max arch_default arch_step].freeze

  def up
    STRINGS.each { |name| add_column :issues, name, :string unless column_exists?(:issues, name) }
    NUMBERS.each { |name| add_column :issues, name, :float unless column_exists?(:issues, name) }
    add_column :issues, :arch_cad_data, :text, limit: 16_777_215 unless column_exists?(:issues, :arch_cad_data)
    add_index :issues, :arch_model_csid unless index_exists?(:issues, :arch_model_csid)
    tracker = record('trackers')
    source = tracker.find_by!(csys_key: 'arch_node')
    target = tracker.find_or_initialize_by(csys_key: 'arch_dof')
    target.assign_attributes(name: 'archDoF', csys_item_kind: 'arch_dof', default_status_id: source.default_status_id)
    target.save!
    workflow = record('workflows')
    workflow.where(tracker_id: target.id).delete_all
    workflow.where(tracker_id: source.id).find_each do |row|
      workflow.create!(row.attributes.except('id').merge('tracker_id' => target.id))
    end
    assignment = record('projects_trackers')
    record('projects').where(csys_project_profile: 'architecture').find_each do |row|
      assignment.find_or_create_by!(project_id: row.id, tracker_id: target.id)
    end
  end

  def down
    issue = record('issues')
    raise 'Export CAD architecture before rollback' if issue.where.not(arch_model_csid: nil).exists? || issue.where.not(arch_motion: nil).exists? || issue.where.not(arch_cad_data: nil).exists?
    target = record('trackers').find_by(csys_key: 'arch_dof')
    if target
      raise 'Cannot remove populated archDoF tracker' if issue.where(tracker_id: target.id).exists?
      record('workflows').where(tracker_id: target.id).delete_all
      record('projects_trackers').where(tracker_id: target.id).delete_all
      target.destroy!
    end
    remove_index :issues, :arch_model_csid if index_exists?(:issues, :arch_model_csid)
    (STRINGS + NUMBERS + [:arch_cad_data]).reverse_each { |name| remove_column :issues, name if column_exists?(:issues, name) }
  end

  private

  def record(table)
    Class.new(ActiveRecord::Base) do
      self.table_name = table
      self.inheritance_column = :_disabled_type
      self.primary_key = nil if table == 'projects_trackers'
    end.tap(&:reset_column_information)
  end
end
