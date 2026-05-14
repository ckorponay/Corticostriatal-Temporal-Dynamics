function results = disentangle_burst_person_vs_arousal_all6(cfg_input)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end
if nargin < 1, cfg_input = []; end
cfg = load_project_config(cfg_input);

% Decompose burst metrics across ALL 6 runs (4 REST + 2 TASK) into:
%   (1) between-person sLFO effect
%   (2) within-person sLFO effect
%   (3) task effect above/beyond sLFO
%   (4) task x within-sLFO interaction
%   (5) person-specific stable component beyond sLFO and task
%
% Model per metric:
%   BurstMetric ~ sLFO_subjectMean + sLFO_within + Task + Task:sLFO_within + (1|Subject)

%% ------------------------- CONFIGURATION -------------------------------
if ~isfield(cfg, 'subject_vars_file') || isempty(cfg.subject_vars_file)
    error('Config must define cfg.subject_vars_file');
end
subject_vars_file = cfg.subject_vars_file;

runs = { ...
    struct('name','REST1_LR',    'file',get_results_file(cfg,'REST1_LR'),    'slfo_col','sLFO_REST1_LR',    'isTask',0), ...
    struct('name','REST1_RL',    'file',get_results_file(cfg,'REST1_RL'),    'slfo_col','sLFO_REST1_RL',    'isTask',0), ...
    struct('name','REST2_LR',    'file',get_results_file(cfg,'REST2_LR'),    'slfo_col','sLFO_REST2_LR',    'isTask',0), ...
    struct('name','REST2_RL',    'file',get_results_file(cfg,'REST2_RL'),    'slfo_col','sLFO_REST2_RL',    'isTask',0), ...
    struct('name','GAMBLING_LR', 'file',get_results_file(cfg,'GAMBLING_LR'), 'slfo_col','sLFO_GAMBLING_LR', 'isTask',1), ...
    struct('name','GAMBLING_RL', 'file',get_results_file(cfg,'GAMBLING_RL'), 'slfo_col','sLFO_GAMBLING_RL', 'isTask',1) ...
    };

output_dir = get_output_dir(cfg, 'burst_person_vs_arousal_all6');
extra_covariates = {'Gender','Age_in_Yrs'};
use_random_slope = false;

%% ------------------------- LOAD SPREADSHEET ----------------------------
fprintf('Loading subject spreadsheet...\n');
if ~exist(subject_vars_file, 'file')
    error('Subject vars file not found: %s', subject_vars_file);
end
Tsub = readtable(subject_vars_file);
if width(Tsub) < 2
    error('Spreadsheet must have at least 2 columns.');
end

subject_ids = Tsub{:,1};
subject_ids = normalize_subject_ids(subject_ids);

extra_cov = table();
for i = 1:numel(extra_covariates)
    vn = extra_covariates{i};
    if any(strcmp(Tsub.Properties.VariableNames, vn))
        extra_cov.(vn) = to_double_column(Tsub.(vn));
    else
        warning('Extra covariate "%s" not found in spreadsheet.', vn);
    end
end

%% ------------------------- LOAD RUN METRICS ----------------------------
fprintf('Loading burst metrics from all 6 runs...\n');
run_metrics = cell(numel(runs),1);
n_subjects_by_run = nan(numel(runs),1);
for r = 1:numel(runs)
    rr = runs{r};
    if ~exist(rr.file, 'file')
        error('Missing run results file: %s', rr.file);
    end
    if ~any(strcmp(Tsub.Properties.VariableNames, rr.slfo_col))
        error('Missing spreadsheet column for %s: %s', rr.name, rr.slfo_col);
    end
    D = load(rr.file);
    M = extract_focused_metrics_with_extra(D);
    run_metrics{r} = M;
    fn = fieldnames(M);
    if isempty(fn)
        error('No extractable metrics found in %s', rr.file);
    end
    n_subjects_by_run(r) = numel(M.(fn{1}));
    fprintf('  %-12s : %d subjects\n', rr.name, n_subjects_by_run(r));
end
if numel(unique(n_subjects_by_run)) ~= 1
    error('Run metric files do not all have the same number of subjects: %s', mat2str(n_subjects_by_run'));
end
n_metric_subjects = n_subjects_by_run(1);
if numel(subject_ids) < n_metric_subjects
    error('Spreadsheet has fewer rows (%d) than neural metrics (%d).', numel(subject_ids), n_metric_subjects);
end
subject_ids = subject_ids(1:n_metric_subjects);
Tsub = Tsub(1:n_metric_subjects, :);
if ~isempty(extra_cov), extra_cov = extra_cov(1:n_metric_subjects, :); end
metric_names = fieldnames(run_metrics{1});
for r = 2:numel(run_metrics)
    f = fieldnames(run_metrics{r});
    if ~isequal(sort(metric_names), sort(f))
        error('Metric set mismatch across runs.');
    end
end

%% ------------------------- BUILD LONG TABLE ----------------------------
fprintf('Building long-format run-level table...\n');
long_rows = table();
for r = 1:numel(runs)
    rr = runs{r};
    T = table();
    T.Subject = subject_ids(:);
    T.Run = repmat({rr.name}, n_metric_subjects, 1);
    T.sLFO = to_double_column(Tsub.(rr.slfo_col));
    T.Task = repmat(rr.isTask, n_metric_subjects, 1);
    if ~isempty(extra_cov)
        for j = 1:width(extra_cov)
            T.(extra_cov.Properties.VariableNames{j}) = extra_cov{:,j};
        end
    end
    for m = 1:numel(metric_names)
        nm = metric_names{m};
        T.(nm) = run_metrics{r}.(nm)(:);
    end
    long_rows = [long_rows; T]; %#ok<AGROW>
end
[G, ~] = findgroups(long_rows.Subject);
slfo_subject_mean = splitapply(@(x) mean(x,'omitnan'), long_rows.sLFO, G);
long_rows.sLFO_subjectMean = slfo_subject_mean(G);
long_rows.sLFO_within = long_rows.sLFO - long_rows.sLFO_subjectMean;
long_rows.Subject = categorical(long_rows.Subject);
long_rows.Run = categorical(long_rows.Run);
long_rows.Task = categorical(long_rows.Task, [0 1], {'Rest','Task'});
writetable(long_rows, fullfile(output_dir, 'long_run_level_table_all6.csv'));

%% ------------------------- FIT MIXED MODELS ----------------------------
fprintf('Fitting mixed models for each burst metric...\n');
metric_summaries = table();
subject_level_components = table();
subject_level_components.Subject = string(categories(long_rows.Subject));
for m = 1:numel(metric_names)
    metric = metric_names{m};
    fprintf('  %s\n', metric);
    Tm = long_rows(:, {'Subject','Run','Task','sLFO','sLFO_subjectMean','sLFO_within'});
    Tm.BurstMetric = long_rows.(metric);
    valid = ~isnan(Tm.BurstMetric) & ~isnan(Tm.sLFO_subjectMean) & ~isnan(Tm.sLFO_within);
    Tm = Tm(valid,:);
    if height(Tm) < 30
        warning('Skipping %s: too few valid rows (%d).', metric, height(Tm));
        continue;
    end
    if use_random_slope
        formula = 'BurstMetric ~ sLFO_subjectMean + sLFO_within + Task + Task:sLFO_within + (sLFO_within|Subject)';
    else
        formula = 'BurstMetric ~ sLFO_subjectMean + sLFO_within + Task + Task:sLFO_within + (1|Subject)';
    end
    lme = fitlme(Tm, formula);
    Coef = lme.Coefficients;
    names = Coef.Name;
    between_idx = find(strcmp(names, 'sLFO_subjectMean'), 1);
    within_idx = find(strcmp(names, 'sLFO_within'), 1);
    task_idx = find(strcmp(names, 'Task_Task'), 1);
    interact_idx = find(strcmp(names, 'Task_Task:sLFO_within'), 1);
    [b_between, se_between, t_between, p_between] = coef_row(Coef, between_idx);
    [b_within, se_within, t_within, p_within] = coef_row(Coef, within_idx);
    [b_task, se_task, t_task, p_task] = coef_row(Coef, task_idx);
    [b_int, se_int, t_int, p_int] = coef_row(Coef, interact_idx);
    fitted = predict(lme);
    resid = Tm.BurstMetric - fitted;
    [Gm, subj_names] = findgroups(Tm.Subject);
    subj_resid_mean = splitapply(@(x) mean(x,'omitnan'), resid, Gm);
    subj_metric_mean = splitapply(@(x) mean(x,'omitnan'), Tm.BurstMetric, Gm);
    subj_slfo_mean = splitapply(@(x) mean(x,'omitnan'), Tm.sLFO, Gm);
    subj_fit_mean = splitapply(@(x) mean(x,'omitnan'), fitted, Gm);
    subj_task_resid = splitapply(@task_minus_rest_mean, resid, Tm.Task, Gm);
    metric_summaries = [metric_summaries; table( ...
        {metric}, height(Tm), numel(unique(Tm.Subject)), ...
        b_between, se_between, t_between, p_between, ...
        b_within, se_within, t_within, p_within, ...
        b_task, se_task, t_task, p_task, ...
        b_int, se_int, t_int, p_int, ...
        lme.ModelCriterion.AIC, lme.ModelCriterion.BIC, ...
        'VariableNames', {'Metric','N_rows','N_subjects', ...
                          'Beta_between','SE_between','t_between','p_between', ...
                          'Beta_within','SE_within','t_within','p_within', ...
                          'Beta_task','SE_task','t_task','p_task', ...
                          'Beta_taskXwithin','SE_taskXwithin','t_taskXwithin','p_taskXwithin', ...
                          'AIC','BIC'})]; %#ok<AGROW>
    stable_col = nan(height(subject_level_components),1);
    raw_col = nan(height(subject_level_components),1);
    slfo_col = nan(height(subject_level_components),1);
    fit_col = nan(height(subject_level_components),1);
    taskres_col = nan(height(subject_level_components),1);
    subj_names = string(cellstr(subj_names));
    [tf, loc] = ismember(subject_level_components.Subject, subj_names);
    stable_col(tf) = subj_resid_mean(loc(tf));
    raw_col(tf) = subj_metric_mean(loc(tf));
    slfo_col(tf) = subj_slfo_mean(loc(tf));
    fit_col(tf) = subj_fit_mean(loc(tf));
    taskres_col(tf) = subj_task_resid(loc(tf));
    subject_level_components.([metric '_stableResidual']) = stable_col;
    subject_level_components.([metric '_rawMean']) = raw_col;
    subject_level_components.([metric '_sLFOmean']) = slfo_col;
    subject_level_components.([metric '_fittedMean']) = fit_col;
    subject_level_components.([metric '_taskEffectResidual']) = taskres_col;
    save(fullfile(output_dir, sprintf('lme_%s.mat', metric)), 'lme');
end

%% ------------------------- COVARIATE CORRELATIONS ----------------------
fprintf('Computing correlations of stable residual components with age / sex / mean sLFO...\n');
subject_cov = table();
subject_cov.Subject = string(subject_ids(:));
if any(strcmp(extra_cov.Properties.VariableNames, 'Age_in_Yrs')), subject_cov.Age_in_Yrs = extra_cov.Age_in_Yrs(:); end
if any(strcmp(extra_cov.Properties.VariableNames, 'Gender')), subject_cov.Gender = extra_cov.Gender(:); end
[G2, ~] = findgroups(long_rows.Subject);
subject_mean_sLFO = splitapply(@(x) mean(x,'omitnan'), long_rows.sLFO, G2);
subj_names2 = string(categories(long_rows.Subject));
subject_sLFO_tbl = table(subj_names2, subject_mean_sLFO, 'VariableNames', {'Subject','Mean_sLFO'});
subject_cov = outerjoin(subject_cov, subject_sLFO_tbl, 'Keys','Subject', 'MergeKeys', true);
covariate_corr_rows = {};
for m = 1:numel(metric_names)
    metric = metric_names{m};
    stable_name = [metric '_stableResidual'];
    if ~ismember(stable_name, subject_level_components.Properties.VariableNames), continue; end
    A = subject_level_components(:, {'Subject', stable_name});
    B = subject_cov;
    A.Subject = string(A.Subject); B.Subject = string(B.Subject);
    tmp = outerjoin(A, B, 'Keys', 'Subject', 'MergeKeys', true);
    burst_stable = tmp.(stable_name);
    cov_names = intersect({'Age_in_Yrs','Gender','Mean_sLFO'}, tmp.Properties.VariableNames, 'stable');
    for c = 1:numel(cov_names)
        cov_name = cov_names{c}; cov_data = tmp.(cov_name);
        valid = ~isnan(burst_stable) & ~isnan(cov_data);
        if sum(valid) < 20, continue; end
        [r,p] = corr(burst_stable(valid), cov_data(valid), 'type', 'Pearson');
        covariate_corr_rows(end+1,:) = {metric, cov_name, r, p, sum(valid)}; %#ok<AGROW>
    end
end
if ~isempty(covariate_corr_rows)
    cov_corr_table = cell2table(covariate_corr_rows, 'VariableNames', {'Metric','Covariate','r','p','N'});
    writetable(cov_corr_table, fullfile(output_dir, 'stable_component_covariate_correlations_all6.csv'));
else
    cov_corr_table = table();
end

%% ------------------------- EXPORT --------------------------------------
writetable(metric_summaries, fullfile(output_dir, 'mixed_model_metric_summaries_all6.csv'));
writetable(subject_level_components, fullfile(output_dir, 'subject_level_stable_components_all6.csv'));
results = struct();
results.output_dir = output_dir;
results.long_table = long_rows;
results.metric_summaries = metric_summaries;
results.subject_level_components = subject_level_components;
results.stable_component_covariate_correlations = cov_corr_table;
save(fullfile(output_dir, 'burst_person_vs_arousal_all6_results.mat'), 'results', '-v7.3');
fprintf('\nDone.\nSaved outputs to: %s\n', output_dir);
end

%% ========================= HELPERS =====================================
function metrics = extract_focused_metrics_with_extra(data)
metrics = struct();
if isfield(data, 'SubjectPercent_BurstTotal'), metrics.Burst_total_pct = data.SubjectPercent_BurstTotal(:); end
if isfield(data, 'SubjectPercent_RestStates')
    S = data.SubjectPercent_RestStates;
    if size(S,2) >= 1, metrics.Rest1_pct = S(:,1); end
    if size(S,2) >= 2, metrics.Rest2_pct = S(:,2); end
    if size(S,2) >= 3, metrics.Rest3_pct = S(:,3); end
end
if isfield(data, 'Rest3_to_Rest1_Ratio_Subject')
    metrics.Rest3_to_Rest1_Ratio = data.Rest3_to_Rest1_Ratio_Subject(:);
elseif isfield(data, 'SubjectPercent_RestStates') && size(data.SubjectPercent_RestStates, 2) >= 3
    rest1_pct = data.SubjectPercent_RestStates(:,1); rest3_pct = data.SubjectPercent_RestStates(:,3);
    r = rest3_pct ./ rest1_pct; r(rest1_pct == 0) = NaN; metrics.Rest3_to_Rest1_Ratio = r(:);
end
if isfield(data, 'SubjectAvgK_onBursts'), metrics.Burst_avg_k = data.SubjectAvgK_onBursts(:); end
if isfield(data,'AverageDuration_inTRs_subject')
    A = data.AverageDuration_inTRs_subject;
    if size(A,1) >= 1, metrics.Rest1_dwell_TRs = A(1,:)'; end
    if size(A,1) >= 3, metrics.Rest3_dwell_TRs = A(3,:)'; end
    metrics.Burst_dwell_TRs = A(end,:)';
end
if isfield(data, 'SubjectAvgPos5_onBursts_raw'), metrics.Burst_avgPos5_raw = data.SubjectAvgPos5_onBursts_raw(:); end
if isfield(data, 'SubjectAvgPos5_onBursts_z'), metrics.Burst_avgPos5_z = data.SubjectAvgPos5_onBursts_z(:); end
if isfield(data, 'StriatalBOLD_Mean_TS')
    metrics.StriatalBOLD_mean = mean(data.StriatalBOLD_Mean_TS, 1, 'omitnan')';
    metrics.StriatalBOLD_sd = std(data.StriatalBOLD_Mean_TS, 0, 1, 'omitnan')';
end
if isfield(data, 'TransProb_subject')
    P = data.TransProb_subject;
    if ndims(P) == 3 && size(P,2) >= 4 && size(P,3) >= 4
        metrics.P_R1_to_R1 = squeeze(P(:,1,1));
        metrics.P_R1_to_R3 = squeeze(P(:,1,3));
        metrics.P_R3_to_R1 = squeeze(P(:,3,1));
        metrics.P_R3_to_R3 = squeeze(P(:,3,3));
        metrics.P_R3_to_Burst = squeeze(P(:,3,4));
        metrics.P_R2_to_Burst = squeeze(P(:,2,4));
        metrics.P_Burst_to_Burst = squeeze(P(:,4,4));
        metrics.P_Burst_to_R3 = squeeze(P(:,4,3));
    end
end
end
function [b,se,t,p] = coef_row(Coef, idx)
if isempty(idx), b = NaN; se = NaN; t = NaN; p = NaN; else, b = Coef.Estimate(idx); se = Coef.SE(idx); t = Coef.tStat(idx); p = Coef.pValue(idx); end
end
function out = task_minus_rest_mean(resid, taskcat)
task_mask = strcmp(string(taskcat), 'Task'); rest_mask = strcmp(string(taskcat), 'Rest');
if any(task_mask), mt = mean(resid(task_mask), 'omitnan'); else, mt = NaN; end
if any(rest_mask), mr = mean(resid(rest_mask), 'omitnan'); else, mr = NaN; end
out = mt - mr;
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
if isnumeric(sid_raw), sid = arrayfun(@(x) sprintf('%d', x), sid_raw, 'UniformOutput', false);
elseif iscell(sid_raw), sid = cellfun(@convert_one_id, sid_raw, 'UniformOutput', false);
elseif isstring(sid_raw), sid = cellstr(sid_raw);
elseif iscategorical(sid_raw), sid = cellstr(string(sid_raw));
else, error('Unsupported Subject ID type.'); end
sid = sid(:);
    function out = convert_one_id(x)
        if isnumeric(x), out = sprintf('%d', x); elseif isstring(x) || ischar(x), out = char(string(x)); else, out = char(string(x)); end
    end
end
