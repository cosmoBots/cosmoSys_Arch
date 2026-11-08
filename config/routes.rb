get 'issues/:issue_id/architecture/cad', to: 'cosmosys_arch/cad_imports#index', as: :arch_cad_import
get 'issues/:issue_id/architecture/cad/reset', to: 'cosmosys_arch/cad_imports#reset_review', as: :arch_cad_reset_review
post 'issues/:issue_id/architecture/cad/reset', to: 'cosmosys_arch/cad_imports#reset_import', as: :arch_cad_reset
post 'issues/:issue_id/architecture/cad/review', to: 'cosmosys_arch/cad_imports#review', as: :arch_cad_review
get 'issues/:issue_id/architecture/cad/review', to: 'cosmosys_arch/cad_imports#review'
get 'issues/:issue_id/architecture/cad/preview', to: 'cosmosys_arch/cad_imports#preview', as: :arch_cad_preview
post 'issues/:issue_id/architecture/cad/import', to: 'cosmosys_arch/cad_imports#create', as: :arch_cad_create
get 'issues/:issue_id/architecture/cad/view', to: 'cosmosys_arch/cad_imports#view', as: :arch_cad_view
get 'issues/:issue_id/architecture/cad/file', to: 'cosmosys_arch/cad_imports#file', as: :arch_cad_file
get 'issues/:issue_id/architecture/cad/capture-module', to: 'cosmosys_arch/cad_imports#capture_module', as: :arch_cad_capture_module
get 'issues/:issue_id/architecture/cad/views', to: 'cosmosys_arch/cad_imports#piece_views', as: :arch_cad_piece_views
put 'issues/:issue_id/architecture/cad/views', to: 'cosmosys_arch/cad_imports#save_piece_view'
get 'issues/:issue_id/architecture/cad/figure', to: 'cosmosys_arch/cad_imports#piece_image', as: :arch_cad_piece_image
