module CosmosysArch
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'hooks/cosmosys_arch/item_fields'
    render_on :view_issues_show_description_bottom, partial: 'hooks/cosmosys_arch/item_details'
  end
end
