function results = rest_vs_task_statistical_comparison_avgedRest(cfg_input)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end
if nargin < 1, cfg_input = []; end


% Compare pooled REST metrics (4 runs) vs pooled TASK metrics (2 runs)
% using paired t-tests for each neural metric.

cfg = load_project_config(cfg_input);

%% ------------------------- CONFIGURATION -------------------------------
rest_run_names = {'REST1_RL','REST1_LR','REST2_LR','REST2_RL'};
task_run_names = {'GAMBLING_RL','GAMBLING_LR'};
rest_results_files = cellfun(@(rn) get_results_file(cfg, rn), rest_run_names, 'UniformOutput', false);
task_results_files = cellfun(@(rn) get_results_file(cfg, rn), task_run_names, 'UniformOutput', false);

output_dir = get_output_dir(cfg, 'rest_vs_task_comparison_all6');

alpha = 0.05;
use_fdr_correction = true;

%% ------------------------- LOAD + POOL METRICS ------------------------
fprintf('Loading pooled REST and TASK metrics...\n');

rest_avg_metrics = mean_metrics_over_files(rest_results_files);
task_avg_metrics = mean_metrics_over_files(task_results_files);

metric_names = fieldnames(rest_avg_metrics);
n_metrics = numel(metric_names);

%% ------------------------- RUN PAIRED TESTS ---------------------------
fprintf('Running paired REST vs TASK tests on pooled metrics...\n');

results = struct();
results.output_dir = output_dir;
all_p = nan(n_metrics,1);

for i = 1:n_metrics
    metric = metric_names{i};

    if ~isfield(task_avg_metrics, metric)
        warning('Metric missing in task data: %s', metric);
        continue;
    end

    r = rest_avg_metrics.(metric);
    t = task_avg_metrics.(metric);

    valid = ~isnan(r) & ~isnan(t);
    rv = r(valid);
    tv = t(valid);

    if numel(rv) < 3
        warning('Skipping %s: insufficient paired data', metric);
        continue;
    end

    diffs = tv - rv;
    mean_rest = mean(rv, 'omitnan');
    mean_task = mean(tv, 'omitnan');
    mean_diff = mean(diffs, 'omitnan');
    sd_diff   = std(diffs, 0, 'omitnan');

    [~, p, ci, stats] = ttest(tv, rv);

    if sd_diff == 0
        dz = NaN;
    else
        dz = mean_diff / sd_diff;
    end

    results.(metric).n = numel(rv);
    results.(metric).mean_rest = mean_rest;
    results.(metric).mean_task = mean_task;
    results.(metric).mean_diff = mean_diff;
    results.(metric).t_stat = stats.tstat;
    results.(metric).df = stats.df;
    results.(metric).p_value = p;
    results.(metric).ci_low = ci(1);
    results.(metric).ci_high = ci(2);
    results.(metric).cohens_dz = dz;

    all_p(i) = p;

    fprintf('%-24s | N=%3d | REST=%.4f | TASK=%.4f | Δ=%.4f | t(%d)=%.3f | p=%.5g\n', ...
        metric, numel(rv), mean_rest, mean_task, mean_diff, stats.df, stats.tstat, p);
end

%% ------------------------- MULTIPLE COMPARISON CORRECTION -------------
valid_p_idx = ~isnan(all_p);
if use_fdr_correction && any(valid_p_idx)
    if exist('mafdr','file') == 2
        p_fdr = nan(size(all_p));
        p_fdr(valid_p_idx) = mafdr(all_p(valid_p_idx), 'BHFDR', true);
    else
        p_fdr = nan(size(all_p));
        p_fdr(valid_p_idx) = fdr_correction(all_p(valid_p_idx), alpha);
    end
else
    p_fdr = all_p;
end

for i = 1:n_metrics
    metric = metric_names{i};
    if isfield(results, metric)
        results.(metric).p_fdr = p_fdr(i);
    end
end

%% ------------------------- EXPORT TABLE -------------------------------
rows = {};
for i = 1:n_metrics
    metric = metric_names{i};
    if ~isfield(results, metric), continue; end
    R = results.(metric);
    rows(end+1,:) = {metric, R.n, R.mean_rest, R.mean_task, R.mean_diff, ...
        R.t_stat, R.df, R.p_value, R.p_fdr, R.cohens_dz}; %#ok<AGROW>
end

if ~isempty(rows)
    T = cell2table(rows, 'VariableNames', ...
        {'Metric','N','Mean_REST','Mean_TASK','Mean_Diff', ...
         't_stat','df','p_value','p_fdr','cohens_dz'});
    writetable(T, fullfile(output_dir, 'rest_vs_task_pooled_comparison.csv'));
end

save(fullfile(output_dir, 'rest_vs_task_pooled_comparison.mat'), 'results');
fprintf('Saved outputs to %s\n', output_dir);

end

%% ========================= HELPERS ====================================

function metrics_mean = mean_metrics_over_files(files)
metrics_list = cell(numel(files),1);
for i = 1:numel(files)
    f = files{i};
    if ~exist(f,'file')
        error('Missing results file: %s', f);
    end
    D = load(f);
    metrics_list{i} = extract_focused_metrics(D);
end

metrics_mean = metrics_list{1};
fns = fieldnames(metrics_mean);
for j = 1:numel(fns)
    nm = fns{j};
    X = [];
    for i = 1:numel(metrics_list)
        if isfield(metrics_list{i}, nm)
            X(:,i) = metrics_list{i}.(nm)(:); %#ok<AGROW>
        else
            X(:,i) = nan(numel(metrics_list{1}.(nm)),1); %#ok<AGROW>
        end
    end
    metrics_mean.(nm) = mean(X, 2, 'omitnan');
end
end

function metrics = extract_focused_metrics(data)
metrics = struct();

if isfield(data, 'SubjectPercent_BurstTotal')
    metrics.Burst_total_pct = data.SubjectPercent_BurstTotal(:);
end

if isfield(data, 'SubjectPercent_RestStates')
    S = data.SubjectPercent_RestStates;
    if size(S,2) >= 1, metrics.Rest1_pct = S(:,1); end
    if size(S,2) >= 2, metrics.Rest2_pct = S(:,2); end
    if size(S,2) >= 3, metrics.Rest3_pct = S(:,3); end
end

if isfield(data, 'Rest3_to_Rest1_Ratio_Subject')
    metrics.Rest3_to_Rest1_Ratio = data.Rest3_to_Rest1_Ratio_Subject(:);
elseif isfield(data, 'SubjectPercent_RestStates') && size(data.SubjectPercent_RestStates, 2) >= 3
    rest1_pct = data.SubjectPercent_RestStates(:,1);
    rest3_pct = data.SubjectPercent_RestStates(:,3);
    r = rest3_pct ./ rest1_pct;
    r(rest1_pct == 0) = NaN;
    metrics.Rest3_to_Rest1_Ratio = r(:);
end

if isfield(data, 'SubjectAvgK_onBursts')
    metrics.Burst_avg_k = data.SubjectAvgK_onBursts(:);
end

if isfield(data,'AverageDuration_inTRs_subject')
    A = data.AverageDuration_inTRs_subject;
    if size(A,1) >= 1, metrics.Rest1_dwell_TRs = A(1,:)'; end
    if size(A,1) >= 3, metrics.Rest3_dwell_TRs = A(3,:)'; end
    metrics.Burst_dwell_TRs = A(end,:)';
end

if isfield(data, 'SubjectAvgPos5_onBursts_raw')
    metrics.Burst_avgPos5_raw = data.SubjectAvgPos5_onBursts_raw(:);
end
if isfield(data, 'SubjectAvgPos5_onBursts_z')
    metrics.Burst_avgPos5_z = data.SubjectAvgPos5_onBursts_z(:);
end

if isfield(data, 'StriatalBOLD_Mean_TS')
    metrics.StriatalBOLD_mean = mean(data.StriatalBOLD_Mean_TS, 1, 'omitnan')';
    metrics.StriatalBOLD_sd   = std(data.StriatalBOLD_Mean_TS, 0, 1, 'omitnan')';
end

if isfield(data, 'TransProb_subject')
    P = data.TransProb_subject;
    if ndims(P) == 3 && size(P,2) >= 4 && size(P,3) >= 4
        metrics.P_R1_to_R1       = squeeze(P(:,1,1));
        metrics.P_R1_to_R3       = squeeze(P(:,1,3));
        metrics.P_R3_to_R1       = squeeze(P(:,3,1));
        metrics.P_R3_to_R3       = squeeze(P(:,3,3));
        metrics.P_R3_to_Burst    = squeeze(P(:,3,4));
        metrics.P_R2_to_Burst    = squeeze(P(:,2,4));
        metrics.P_Burst_to_Burst = squeeze(P(:,4,4));
        metrics.P_Burst_to_R3    = squeeze(P(:,4,3));
    end
end
end

function corrected_p = fdr_correction(p_values, alpha)
if nargin < 2, alpha = 0.05; end
p_values = p_values(:);
n = length(p_values);
[sorted_p, sort_idx] = sort(p_values);
q_values = nan(n, 1);
q_values(n) = sorted_p(n);
for i = (n-1):-1:1
    q_raw = sorted_p(i) * n / i;
    q_values(i) = min(q_raw, q_values(i+1));
end
corrected_p = nan(n, 1);
corrected_p(sort_idx) = q_values;
corrected_p = min(corrected_p, 1.0);
end
