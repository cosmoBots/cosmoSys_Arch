require_dependency 'issue_query'

module CosmosysArch
  module IssueQueryPatch
    def self.prepended(base)
      unless base.available_columns.any? { |column| column.name == :arch_type }
        base.available_columns << QueryColumn.new(:arch_type, sortable: "#{Issue.table_name}.arch_type", caption: :field_arch_type)
      end
    end

    def initialize_available_filters
      super
      add_available_filter('arch_type', type: :list, name: :field_arch_type,
                           values: CosmosysArch::ProfileRegistration::TYPES.map do |value|
                             [I18n.t("label_cosmosys_arch_type_#{value}"), value]
                           end) unless available_filters.key?('arch_type')
    end
  end
end

IssueQuery.prepend(CosmosysArch::IssueQueryPatch) unless IssueQuery < CosmosysArch::IssueQueryPatch
