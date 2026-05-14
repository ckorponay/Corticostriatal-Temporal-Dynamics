function p = get_results_file(cfg, run_name)
%GET_RESULTS_FILE Return standardized run-level results MAT path.
if isfield(cfg,'runs') && isfield(cfg.runs, run_name) && isfield(cfg.runs.(run_name),'results_file') && ~isempty(cfg.runs.(run_name).results_file)
    p = cfg.runs.(run_name).results_file;
elseif isfield(cfg,'results_root') && ~isempty(cfg.results_root)
    p = fullfile(cfg.results_root, run_name, 'efc_states_louvain_all_detectors.mat');
elseif isfield(cfg,'output_root') && ~isempty(cfg.output_root)
    p = fullfile(cfg.output_root, 'results', run_name, 'efc_states_louvain_all_detectors.mat');
elseif isfield(cfg,'project_root') && ~isempty(cfg.project_root)
    p = fullfile(cfg.project_root, 'outputs', 'results', run_name, 'efc_states_louvain_all_detectors.mat');
else
    error('Could not resolve results file for run %s. Add cfg.runs.%s.results_file or cfg.output_root.', run_name, run_name);
end
end
