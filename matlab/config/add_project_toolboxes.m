function add_project_toolboxes(cfg)
%ADD_PROJECT_TOOLBOXES Add project dependencies from config.
if isfield(cfg,'toolbox')
    if isfield(cfg.toolbox,'efc') && ~isempty(cfg.toolbox.efc)
        addpath(genpath(cfg.toolbox.efc));
    end
    if isfield(cfg.toolbox,'nifti') && ~isempty(cfg.toolbox.nifti)
        addpath(cfg.toolbox.nifti);
    end
    if isfield(cfg.toolbox,'bct') && ~isempty(cfg.toolbox.bct)
        addpath(cfg.toolbox.bct);
    end
end
end
