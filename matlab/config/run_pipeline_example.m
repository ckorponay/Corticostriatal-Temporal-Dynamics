function run_pipeline_example()
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end

% Example runner showing the intended order of operations.
% Copy path_config_template.m to user_paths.m, edit it, then run this file.

cfg = load_project_config();

fprintf('1) Run the core script separately for each acquisition.
');
fprintf('2) After all runs are processed, execute the downstream summary scripts.
');

% Example manual order:
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'REST1_LR');
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'REST1_RL');
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'REST2_LR');
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'REST2_RL');
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'GAMBLING_RL');
% Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'GAMBLING_LR');
%
% compare_rest_vs_task_interblock_states(cfg);
% compare_rest_vs_task_period_states(cfg);
% rest_vs_task_statistical_comparison_avgedRest(cfg);

fprintf('Loaded config from user_paths.m or supplied config source.
');
if isfield(cfg,'project_root'), fprintf('Project root: %s\n', cfg.project_root); end
if isfield(cfg,'output_root'), fprintf('Output root: %s\n', cfg.output_root); end
end

% Optional downstream models
results = disentangle_burst_person_vs_arousal_all6(cfg);
regression_results = analyze_residualized_neural_predictors_all6(cfg);
