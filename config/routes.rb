get 'issues/:issue_id/architecture/cad', to: 'cosmosys_arch/cad_imports#index', as: :arch_cad_import
post 'issues/:issue_id/architecture/cad/review', to: 'cosmosys_arch/cad_imports#review', as: :arch_cad_review
get 'issues/:issue_id/architecture/cad/review', to: 'cosmosys_arch/cad_imports#review'
get 'issues/:issue_id/architecture/cad/preview', to: 'cosmosys_arch/cad_imports#preview', as: :arch_cad_preview
post 'issues/:issue_id/architecture/cad/import', to: 'cosmosys_arch/cad_imports#create', as: :arch_cad_create
get 'issues/:issue_id/architecture/cad/view', to: 'cosmosys_arch/cad_imports#view', as: :arch_cad_view
get 'issues/:issue_id/architecture/cad/file', to: 'cosmosys_arch/cad_imports#file', as: :arch_cad_file
