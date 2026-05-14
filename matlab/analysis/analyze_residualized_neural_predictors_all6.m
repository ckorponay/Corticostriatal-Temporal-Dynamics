function regression_results = analyze_residualized_neural_predictors_all6(cfg_input)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end
if nargin < 1, cfg_input = []; end
cfg = load_project_config(cfg_input);

% Regress behavioral outcomes on subject-level residualized neural predictors
% derived from disentangle_burst_person_vs_arousal_all6().

%% ------------------------- CONFIGURATION -------------------------------
if ~isfield(cfg, 'subject_vars_file') || isempty(cfg.subject_vars_file)
    error('Config must define cfg.subject_vars_file');
end
subject_vars_file = cfg.subject_vars_file;
burst_output_dir = get_output_dir(cfg, 'burst_person_vs_arousal_all6', false);
residual_file = fullfile(burst_output_dir, 'subject_level_stable_components_all6.csv');
output_dir = get_output_dir(cfg, 'residualized_neural_predictors_all6');
alpha = 0.05;
use_fdr_correction = true;
min_subjects_for_analysis = 30;
outcome_vars = { ...
    'Gender', 'Age_in_Yrs', ...
    'PMAT24_A_CR', ...
    'DDisc_AUC_200', 'DDisc_AUC_40K', ...
    'Cope1_Punish_rStriatumAvg_Gambling_RL', ...
    'Cope2_Reward_rStriatumAvg_Gambling_RL', ...
    'Cope6_rewardMINUSpunish_rStriatumAvg_Gambling_RL', ...
    'Internalizing', 'SubstanceUse', 'Cognition', 'ProcessingSpeed', 'WellBeing'};

%% ------------------------- LOAD FILES ----------------------------------
fprintf('Loading behavioral spreadsheet...\n');
if ~exist(subject_vars_file, 'file'), error('Subject variables file not found: %s', subject_vars_file); end
T = readtable(subject_vars_file);
fprintf('Loading residualized neural predictors...\n');
if ~exist(residual_file, 'file')
    error('Residual predictor file not found: %s. Run disentangle_burst_person_vs_arousal_all6 first.', residual_file);
end
R = readtable(residual_file);

%% ------------------------- SUBJECT IDS ---------------------------------
T.Subject = normalize_subject_ids(T{:,1});
R.Subject = normalize_subject_ids(R.Subject);

%% ------------------------- SELECT BEHAVIOR VARIABLES --------------------
headers = {};
subject_vars = table();
subject_vars.Subject = T.Subject;
for i = 1:numel(outcome_vars)
    vn = outcome_vars{i};
    if any(strcmp(T.Properties.VariableNames, vn))
        subject_vars.(vn) = to_double_column(T.(vn));
        headers{end+1} = vn; %#ok<AGROW>
    else
        fprintf('Warning: Variable "%s" not found in behavioral spreadsheet\n', vn);
    end
end

%% ------------------------- MERGE TABLES --------------------------------
M = innerjoin(subject_vars, R, 'Keys', 'Subject');
fprintf('Merged dataset has %d subjects\n', height(M));
gender_idx = find(strcmp(headers, 'Gender'), 1);
age_idx = find(strcmp(headers, 'Age_in_Yrs'), 1);
assert(~isempty(gender_idx) && ~isempty(age_idx), 'Gender and/or Age_in_Yrs not found.');
covariate_names = {'Gender', 'Age_in_Yrs'};
outcome_idx = setdiff(1:numel(headers), [gender_idx, age_idx]);
outcome_names = headers(outcome_idx);

%% ------------------------- IDENTIFY PREDICTOR SETS ---------------------
all_vars = M.Properties.VariableNames;
stable_metric_names = all_vars(endsWith(all_vars, '_stableResidual'));
taskeffect_metric_names = all_vars(endsWith(all_vars, '_taskEffectResidual'));
fprintf('Found %d stable residual metrics\n', numel(stable_metric_names));
fprintf('Found %d task-effect residual metrics\n', numel(taskeffect_metric_names));

%% ------------------------- RUN REGRESSIONS -----------------------------
all_results = struct();
all_results.stable_models = struct();
all_results.taskeffect_models = struct();
fprintf('\n=== STABLE RESIDUAL MODELS ===\n');
for m = 1:numel(stable_metric_names)
    neural_metric = stable_metric_names{m};
    fprintf('Running stable residual models for: %s\n', neural_metric);
    metric_results = run_individual_metric_models_from_table(M, neural_metric, outcome_names, covariate_names, min_subjects_for_analysis);
    all_results.stable_models.(matlab.lang.makeValidName(neural_metric)) = metric_results;
end
fprintf('\n=== TASK-EFFECT RESIDUAL MODELS ===\n');
for m = 1:numel(taskeffect_metric_names)
    neural_metric = taskeffect_metric_names{m};
    fprintf('Running task-effect residual models for: %s\n', neural_metric);
    metric_results = run_individual_metric_models_from_table(M, neural_metric, outcome_names, covariate_names, min_subjects_for_analysis);
    all_results.taskeffect_models.(matlab.lang.makeValidName(neural_metric)) = metric_results;
end

%% ------------------------- COLLECT P VALUES ----------------------------
all_p_values = []; p_value_map = struct([]);
for m = 1:numel(stable_metric_names)
    nm_raw = stable_metric_names{m}; nm = matlab.lang.makeValidName(nm_raw);
    if ~isfield(all_results.stable_models, nm), continue; end
    model_results = all_results.stable_models.(nm);
    for o = 1:numel(outcome_names)
        outcome = outcome_names{o};
        if isfield(model_results, outcome) && isfield(model_results.(outcome), 'neural_p_value')
            p_val = model_results.(outcome).neural_p_value;
            all_p_values(end+1,1) = p_val; %#ok<AGROW>
            p_value_map(end+1).model_type = 'stable'; %#ok<AGROW>
            p_value_map(end).neural_metric = nm; p_value_map(end).neural_metric_raw = nm_raw; p_value_map(end).outcome = outcome;
        end
    end
end
for m = 1:numel(taskeffect_metric_names)
    nm_raw = taskeffect_metric_names{m}; nm = matlab.lang.makeValidName(nm_raw);
    if ~isfield(all_results.taskeffect_models, nm), continue; end
    model_results = all_results.taskeffect_models.(nm);
    for o = 1:numel(outcome_names)
        outcome = outcome_names{o};
        if isfield(model_results, outcome) && isfield(model_results.(outcome), 'neural_p_value')
            p_val = model_results.(outcome).neural_p_value;
            all_p_values(end+1,1) = p_val; %#ok<AGROW>
            p_value_map(end+1).model_type = 'taskeffect'; %#ok<AGROW>
            p_value_map(end).neural_metric = nm; p_value_map(end).neural_metric_raw = nm_raw; p_value_map(end).outcome = outcome;
        end
    end
end

%% ------------------------- FDR CORRECTION ------------------------------
fprintf('Applying FDR correction across all %d models...\n', numel(all_p_values));
if use_fdr_correction && ~isempty(all_p_values)
    if exist('mafdr', 'file') == 2, corrected_p = mafdr(all_p_values, 'BHFDR', true); else, corrected_p = fdr_correction(all_p_values, alpha); end
    correction_method = 'FDR (across all residualized models)';
else
    corrected_p = all_p_values; correction_method = 'None';
end
for i = 1:numel(corrected_p)
    model_type = p_value_map(i).model_type; nm = p_value_map(i).neural_metric; outcome = p_value_map(i).outcome;
    switch model_type
        case 'stable', all_results.stable_models.(nm).(outcome).neural_p_corrected = corrected_p(i);
        case 'taskeffect', all_results.taskeffect_models.(nm).(outcome).neural_p_corrected = corrected_p(i);
    end
end

%% ------------------------- SIGNIFICANT RESULTS -------------------------
significant_results = struct('model_type', {}, 'neural_metric', {}, 'outcome_name', {}, 'coefficient', {}, 'se', {}, 't_stat', {}, 'p_raw', {}, 'p_corrected', {}, 'r_squared', {}, 'n_subjects', {});
    function add_sig(bucket, bucket_label, raw_names)
        for mm = 1:numel(raw_names)
            nm_raw = raw_names{mm}; nm = matlab.lang.makeValidName(nm_raw);
            if ~isfield(bucket, nm), continue; end
            model_results = bucket.(nm);
            for oo = 1:numel(outcome_names)
                outcome = outcome_names{oo};
                if isfield(model_results, outcome) && isfield(model_results.(outcome), 'neural_p_corrected')
                    if model_results.(outcome).neural_p_corrected <= alpha
                        sig_result = struct();
                        sig_result.model_type = bucket_label; sig_result.neural_metric = nm_raw; sig_result.outcome_name = outcome;
                        sig_result.coefficient = getfield_or_nan(model_results.(outcome), 'neural_coefficient');
                        sig_result.se = getfield_or_nan(model_results.(outcome), 'neural_se');
                        sig_result.t_stat = getfield_or_nan(model_results.(outcome), 'neural_t_stat');
                        sig_result.p_raw = getfield_or_nan(model_results.(outcome), 'neural_p_value');
                        sig_result.p_corrected = getfield_or_nan(model_results.(outcome), 'neural_p_corrected');
                        sig_result.r_squared = getfield_or_nan(model_results.(outcome), 'r_squared');
                        sig_result.n_subjects = getfield_or_nan(model_results.(outcome), 'n_subjects');
                        significant_results(end+1) = sig_result; %#ok<AGROW>
                    end
                end
            end
        end
    end
add_sig(all_results.stable_models, 'stable', stable_metric_names);
add_sig(all_results.taskeffect_models, 'taskeffect', taskeffect_metric_names);

%% ------------------------- COMPILE RESULTS -----------------------------
regression_results = struct();
regression_results.output_dir = output_dir;
regression_results.stable_models = all_results.stable_models;
regression_results.taskeffect_models = all_results.taskeffect_models;
regression_results.significant_results = significant_results;
regression_results.correction_method = correction_method;
regression_results.alpha = alpha;
regression_results.n_subjects = height(M);
regression_results.stable_metric_names = stable_metric_names;
regression_results.taskeffect_metric_names = taskeffect_metric_names;
regression_results.outcome_names = outcome_names;
regression_results.covariate_names = covariate_names;

%% ------------------------- EXPORT --------------------------------------
save(fullfile(output_dir, 'residualized_neural_predictor_results.mat'), 'regression_results');
export_residualized_model_tables(regression_results, output_dir);
display_residualized_model_summary(regression_results);
fprintf('\nDone. Results saved to %s\n', output_dir);
end

%% ========================= HELPERS =====================================
function results = run_individual_metric_models_from_table(M, neural_metric_name, outcome_names, covariate_names, min_subjects)
results = struct();
for o = 1:numel(outcome_names)
    outcome_name = outcome_names{o};
    y = to_double_column(M.(outcome_name)); neural_data = to_double_column(M.(neural_metric_name));
    covariate_matrix = [];
    for c = 1:numel(covariate_names), covariate_matrix(:,c) = to_double_column(M.(covariate_names{c})); end %#ok<AGROW>
    valid = ~isnan(y) & ~isnan(neural_data) & all(~isnan(covariate_matrix),2);
    if sum(valid) < min_subjects, continue; end
    yv = y(valid); nv = neural_data(valid); Cv = covariate_matrix(valid,:); X = [ones(sum(valid),1), Cv, nv];
    try
        XtX = X' * X; if rcond(XtX) < 1e-12, continue; end
        [b, ~, ~, ~, stats] = regress(yv, X);
        se_b = sqrt(stats(4) * diag(inv(XtX))); neural_ix = size(X,2); neural_coef = b(neural_ix); neural_se = se_b(neural_ix);
        neural_t = neural_coef / neural_se; df = size(X,1) - size(X,2); neural_p = 2 * (1 - tcdf(abs(neural_t), df));
        results.(outcome_name).n_subjects = sum(valid); results.(outcome_name).r_squared = stats(1); results.(outcome_name).f_stat = stats(2);
        results.(outcome_name).model_p_value = stats(3); results.(outcome_name).error_variance = stats(4); results.(outcome_name).neural_coefficient = neural_coef;
        results.(outcome_name).neural_se = neural_se; results.(outcome_name).neural_t_stat = neural_t; results.(outcome_name).neural_p_value = neural_p;
    catch
    end
end
end
function export_residualized_model_tables(results, output_dir)
rows = {};
metrics = results.stable_metric_names;
for m = 1:numel(metrics)
    nm_raw = metrics{m}; nm = matlab.lang.makeValidName(nm_raw);
    if ~isfield(results.stable_models, nm), continue; end
    model_results = results.stable_models.(nm); outcomes = fieldnames(model_results);
    for o = 1:numel(outcomes)
        outcome = outcomes{o}; res = model_results.(outcome);
        rows(end+1,:) = {'stable', nm_raw, outcome, getfield_or_nan(res,'n_subjects'), getfield_or_nan(res,'r_squared'), getfield_or_nan(res,'f_stat'), getfield_or_nan(res,'model_p_value'), getfield_or_nan(res,'neural_coefficient'), getfield_or_nan(res,'neural_se'), getfield_or_nan(res,'neural_t_stat'), getfield_or_nan(res,'neural_p_value'), getfield_or_nan(res,'neural_p_corrected')}; %#ok<AGROW>
    end
end
metrics = results.taskeffect_metric_names;
for m = 1:numel(metrics)
    nm_raw = metrics{m}; nm = matlab.lang.makeValidName(nm_raw);
    if ~isfield(results.taskeffect_models, nm), continue; end
    model_results = results.taskeffect_models.(nm); outcomes = fieldnames(model_results);
    for o = 1:numel(outcomes)
        outcome = outcomes{o}; res = model_results.(outcome);
        rows(end+1,:) = {'taskeffect', nm_raw, outcome, getfield_or_nan(res,'n_subjects'), getfield_or_nan(res,'r_squared'), getfield_or_nan(res,'f_stat'), getfield_or_nan(res,'model_p_value'), getfield_or_nan(res,'neural_coefficient'), getfield_or_nan(res,'neural_se'), getfield_or_nan(res,'neural_t_stat'), getfield_or_nan(res,'neural_p_value'), getfield_or_nan(res,'neural_p_corrected')}; %#ok<AGROW>
    end
end
if ~isempty(rows)
    T = cell2table(rows, 'VariableNames', {'Model_Type','Neural_Metric','Outcome','N','R_squared', 'F_stat','Model_p','Neural_Coefficient','Neural_SE', 'Neural_t_stat','Neural_P_raw','Neural_P_corrected'});
    writetable(T, fullfile(output_dir, 'all_residualized_models.csv'));
end
if ~isempty(results.significant_results)
    sig_data = cell(numel(results.significant_results), 10);
    for i = 1:numel(results.significant_results)
        sig = results.significant_results(i);
        sig_data(i,:) = {sig.model_type, sig.neural_metric, sig.outcome_name, sig.n_subjects, sig.r_squared, sig.coefficient, sig.se, sig.t_stat, sig.p_raw, sig.p_corrected};
    end
    Tsig = cell2table(sig_data, 'VariableNames', {'Model_Type','Neural_Metric','Outcome','N','R_squared', 'Coefficient','SE','t_stat','p_raw','p_corrected'});
    writetable(Tsig, fullfile(output_dir, 'significant_residualized_models.csv'));
end
end
function display_residualized_model_summary(results)
fprintf('\n============================================================\n');
fprintf('RESIDUALIZED NEURAL PREDICTOR ANALYSIS SUMMARY\n');
fprintf('============================================================\n');
fprintf('Subjects: %d\n', results.n_subjects);
fprintf('Stable residual metrics: %d\n', numel(results.stable_metric_names));
fprintf('Task-effect residual metrics: %d\n', numel(results.taskeffect_metric_names));
fprintf('Outcomes: %d\n', numel(results.outcome_names));
fprintf('Covariates: %s\n', strjoin(results.covariate_names, ', '));
n_total = numel(results.stable_metric_names) * numel(results.outcome_names) + numel(results.taskeffect_metric_names) * numel(results.outcome_names);
fprintf('Total models: %d\n', n_total);
if ~isempty(results.significant_results), fprintf('FDR-significant effects: %d\n', numel(results.significant_results)); else, fprintf('No FDR-significant effects.\n'); end
fprintf('============================================================\n');
end
function corrected_p = fdr_correction(p_values, alpha)
if nargin < 2, alpha = 0.05; end
p_values = p_values(:); n = length(p_values); [sorted_p, sort_idx] = sort(p_values); q_values = nan(n,1); q_values(n) = sorted_p(n);
for i = (n-1):-1:1, q_raw = sorted_p(i) * n / i; q_values(i) = min(q_raw, q_values(i+1)); end
corrected_p = nan(n,1); corrected_p(sort_idx) = q_values; corrected_p = min(corrected_p, 1.0);
end
function v = getfield_or_nan(s, fn)
if isfield(s, fn), v = s.(fn); else, v = NaN; end
end
function x = to_double_column(col)
if isnumeric(col), x = double(col);
elseif islogical(col), x = double(col);
elseif iscategorical(col), x = double(grp2idx(col)) - 1;
elseif isstring(col), x = str2double(col);
elseif iscell(col)
    try
        if all(cellfun(@isnumeric, col)), x = cell2mat(col); else, x = str2double(string(col)); end
    catch
        x = NaN(size(col));
    end
else, x = NaN(size(col));
end
x = x(:);
end
function sid = normalize_subject_ids(sid_raw)
if isnumeric(sid_raw), sid = string(arrayfun(@(x) sprintf('%d', x), sid_raw, 'UniformOutput', false));
elseif iscell(sid_raw), sid = string(cellfun(@convert_one_id, sid_raw, 'UniformOutput', false));
elseif isstring(sid_raw), sid = sid_raw;
elseif iscategorical(sid_raw), sid = string(sid_raw);
else, error('Unsupported Subject ID type.'); end
sid = sid(:);
    function out = convert_one_id(x)
        if isnumeric(x), out = sprintf('%d', x); else, out = char(string(x)); end
    end
end
