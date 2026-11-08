module CosmosysArch
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'hooks/cosmosys_arch/item_fields'
    render_on :view_issues_show_description_bottom, partial: 'hooks/cosmosys_arch/item_details'
    render_on :view_cosmosys_report_item_after_description, partial: 'hooks/cosmosys_arch/report_piece_image'
  end
end
