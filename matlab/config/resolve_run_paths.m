function [run_cfg, results_file, export_dir] = resolve_run_paths(cfg, run_name)
%RESOLVE_RUN_PATHS Standardized output locations for a run.

assert(isfield(cfg,'runs') && isfield(cfg.runs, run_name), 'Missing cfg.runs.%s in config.', run_name);
run_cfg = cfg.runs.(run_name);

if isfield(run_cfg,'results_file') && ~isempty(run_cfg.results_file)
    results_file = run_cfg.results_file;
else
    results_dir = get_output_dir(cfg, fullfile('results', run_name));
    results_file = fullfile(results_dir, 'efc_states_louvain_all_detectors.mat');
end

if isfield(run_cfg,'export_dir') && ~isempty(run_cfg.export_dir)
    export_dir = run_cfg.export_dir;
else
    export_dir = get_output_dir(cfg, fullfile('exports', run_name, 'efc_exports'));
end
end
