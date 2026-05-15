function results = compare_rest_vs_task_period_states_pooledAcrossRuns_plusSequentialByRun_plusTaskOnComparisons(cfg_input)
% Compare task-period state occupancies with:
%
% A) POOLED-CATEGORY STATS ACROSS BOTH GAMBLING RUNS COMBINED
%    - InterblockTrim (RL+LR) vs Rest
%    - RewardAll (RL+LR) vs Rest
%    - LossAll (RL+LR) vs Rest
%    - RewardAll (RL+LR) vs InterblockTrim (RL+LR)
%    - LossAll (RL+LR) vs InterblockTrim (RL+LR)
%    - RewardAll (RL+LR) vs LossAll (RL+LR)
%
% B) ADJACENT-PERIOD SEQUENTIAL STATS KEPT SEPARATE FOR RL AND LR
%    - Block1 -> Interblock1
%    - Interblock1 -> Block2
%    - ...
%
% C) TASK-ON vs TASK-ON SEQUENTIAL COMPARISONS KEPT SEPARATE FOR RL AND LR
%    - compare consecutive task blocks directly, ignoring the interblock:
%         Reward1 vs Loss1
%         Loss1 vs Loss2
%         Loss2 vs Reward2
%      (or the corresponding LR ordering)
%
% First and last inter-block periods are excluded from the interblock category.
%
% Required cfg fields:
%   cfg.output_root
%   cfg.run_files.REST1_LR
%   cfg.run_files.REST1_RL
%   cfg.run_files.REST2_LR
%   cfg.run_files.REST2_RL
%   cfg.run_files.GAMBLING_RL
%   cfg.run_files.GAMBLING_LR
%   cfg.timing_files.win_RL
%   cfg.timing_files.loss_RL
%   cfg.timing_files.win_LR
%   cfg.timing_files.loss_LR
%
% Optional cfg.analysis fields:
%   cfg.analysis.TR
%   cfg.analysis.striatal_voxels
%   cfg.analysis.n_subjects
%   cfg.analysis.block_duration_sec
%   cfg.analysis.post_block_buffer_tr

%% ------------------------- CONFIGURATION -------------------------------
cfg = load_project_config(cfg_input);

TR = get_cfg_or(cfg, {'analysis','TR'}, 0.72);
Striatal_Voxels = get_cfg_or(cfg, {'analysis','striatal_voxels'}, 1710);
N_SUBJECTS = get_cfg_or(cfg, {'analysis','n_subjects'}, 407);
state_names = {'Rest1','Rest2','Rest3','Burst'};

block_duration_sec = get_cfg_or(cfg, {'analysis','block_duration_sec'}, 28.0);
block_duration_tr = round(block_duration_sec / TR);
post_block_buffer_tr = get_cfg_or(cfg, {'analysis','post_block_buffer_tr'}, 10);

output_dir = fullfile(cfg.output_root, 'updated_period_stats_pooledAcrossRuns_plusSequentialByRun_plusTaskOnComparisons');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

rest_runs = {'REST1_LR','REST1_RL','REST2_LR','REST2_RL'};
task_runs = { ...
    struct('short','RL', ...
           'name','GAMBLING_RL', ...
           'matfile', get_results_file(cfg, 'GAMBLING_RL'), ...
           'winfile', cfg.timing_files.win_RL, ...
           'lossfile', cfg.timing_files.loss_RL), ...
    struct('short','LR', ...
           'name','GAMBLING_LR', ...
           'matfile', get_results_file(cfg, 'GAMBLING_LR'), ...
           'winfile', cfg.timing_files.win_LR, ...
           'lossfile', cfg.timing_files.loss_LR) ...
    };

%% ------------------------- REST OCCUPANCY ------------------------------
fprintf('Processing REST runs...\n');

rest_state_means = []; % subj x state x run
rest_tr_counts = nan(numel(rest_runs),1);

for f = 1:numel(rest_runs)
    rest_file = get_results_file(cfg, rest_runs{f});
    D = load(rest_file, 'class_All');
    labels = D.class_All(:);

    TRs_rest = numel(labels) / (Striatal_Voxels * N_SUBJECTS);
    if abs(TRs_rest - round(TRs_rest)) > 1e-8
        error('Could not infer integer REST TR count in %s. Check N_SUBJECTS.', rest_file);
    end
    TRs_rest = round(TRs_rest);
    rest_tr_counts(f) = TRs_rest;

    S3 = reshape(labels, TRs_rest, Striatal_Voxels, N_SUBJECTS);

    run_means = nan(N_SUBJECTS, 4);
    for k = 1:4
        occ = squeeze(mean(S3 == k, 2) * 100); % TR x subj
        run_means(:,k) = mean(occ, 1, 'omitnan')';
    end

    rest_state_means(:,:,f) = run_means; %#ok<AGROW>
end

rest_avg = mean(rest_state_means, 3, 'omitnan'); % subj x state

%% ------------------------- PROCESS TASK RUNS ---------------------------
results = struct();
results.rest_avg = rest_avg;
results.rest_tr_counts = rest_tr_counts;
results.state_names = state_names;
results.output_dir = output_dir;

pooled_by_run = struct();

for f = 1:numel(task_runs)
    rr = task_runs{f};
    fprintf('\n--- %s ---\n', rr.name);

    D = load(rr.matfile, 'class_All');
    labels = D.class_All(:);

    TRs_task = numel(labels) / (Striatal_Voxels * N_SUBJECTS);
    if abs(TRs_task - round(TRs_task)) > 1e-8
        error('Could not infer integer TASK TR count in %s. Check N_SUBJECTS.', rr.matfile);
    end
    TRs_task = round(TRs_task);

    S3 = reshape(labels, TRs_task, Striatal_Voxels, N_SUBJECTS);

    win_onsets_sec  = read_onset_file(rr.winfile);
    loss_onsets_sec = read_onset_file(rr.lossfile);

    win_onsets_tr  = round(win_onsets_sec ./ TR) + 1;
    loss_onsets_tr = round(loss_onsets_sec ./ TR) + 1;

    % Ordered block list
    blocks = [];
    idx = 0;
    for i = 1:numel(win_onsets_tr)
        idx = idx + 1;
        blocks(idx).label = 'Reward'; %#ok<AGROW>
        blocks(idx).onsetTR = win_onsets_tr(i);
        blocks(idx).onsetSec = win_onsets_sec(i);
    end
    for i = 1:numel(loss_onsets_tr)
        idx = idx + 1;
        blocks(idx).label = 'Loss'; %#ok<AGROW>
        blocks(idx).onsetTR = loss_onsets_tr(i);
        blocks(idx).onsetSec = loss_onsets_sec(i);
    end
    [~, ord] = sort([blocks.onsetTR]);
    blocks = blocks(ord);

    nReward = 0;
    nLoss = 0;
    for i = 1:numel(blocks)
        if strcmpi(blocks(i).label, 'Reward')
            nReward = nReward + 1;
            blocks(i).name = sprintf('Reward%d', nReward);
        else
            nLoss = nLoss + 1;
            blocks(i).name = sprintf('Loss%d', nLoss);
        end
        blocks(i).startTR = blocks(i).onsetTR;
        blocks(i).endTR   = min(TRs_task, blocks(i).onsetTR + block_duration_tr - 1);
    end

    % Pooled masks within this run
    reward_mask = false(TRs_task,1);
    loss_mask   = false(TRs_task,1);

    for i = 1:numel(blocks)
        s = blocks(i).startTR;
        e = blocks(i).endTR;
        if strcmpi(blocks(i).label, 'Reward')
            reward_mask(s:e) = true;
        else
            loss_mask(s:e) = true;
        end
    end

    % Internal interblocks only
    interblocks = [];
    ib_idx = 0;
    for i = 1:(numel(blocks)-1)
        s = blocks(i).endTR + post_block_buffer_tr + 1;
        e = blocks(i+1).startTR - 1;
        if s <= e
            ib_idx = ib_idx + 1;
            interblocks(ib_idx).name = sprintf('Interblock%d', ib_idx); %#ok<AGROW>
            interblocks(ib_idx).startTR = s;
            interblocks(ib_idx).endTR = e;
        end
    end

    interblock_trim_mask = false(TRs_task,1);
    for i = 1:numel(interblocks)
        interblock_trim_mask(interblocks(i).startTR:interblocks(i).endTR) = true;
    end

    % -------- Subject means for pooled categories within this run --------
    pooled_means_this_run = struct();
    pooled_means_this_run.RewardAll = nan(N_SUBJECTS,4);
    pooled_means_this_run.LossAll = nan(N_SUBJECTS,4);
    pooled_means_this_run.InterblockTrim = nan(N_SUBJECTS,4);

    occ_all = cell(1,4);
    for k = 1:4
        occ_all{k} = squeeze(mean(S3 == k, 2) * 100); % TR x subj
        pooled_means_this_run.RewardAll(:,k)      = mean(occ_all{k}(reward_mask,:), 1, 'omitnan')';
        pooled_means_this_run.LossAll(:,k)        = mean(occ_all{k}(loss_mask,:), 1, 'omitnan')';
        pooled_means_this_run.InterblockTrim(:,k) = mean(occ_all{k}(interblock_trim_mask,:), 1, 'omitnan')';
    end

    pooled_by_run.(rr.short) = pooled_means_this_run;

    % -------- Sequential period means for THIS RUN ONLY --------
    seq_periods = {};
    seq_masks = struct();

    for i = 1:numel(blocks)
        seq_periods{end+1} = blocks(i).name; %#ok<AGROW>
        seq_masks.(blocks(i).name) = false(TRs_task,1);
        seq_masks.(blocks(i).name)(blocks(i).startTR:blocks(i).endTR) = true;

        if i <= numel(interblocks)
            seq_periods{end+1} = interblocks(i).name; %#ok<AGROW>
            seq_masks.(interblocks(i).name) = false(TRs_task,1);
            seq_masks.(interblocks(i).name)(interblocks(i).startTR:interblocks(i).endTR) = true;
        end
    end

    seq_means = struct();
    T_subject = table((1:N_SUBJECTS)', 'VariableNames', {'Subject'});
    block_means = struct();

    for p = 1:numel(seq_periods)
        pname = seq_periods{p};
        mask = seq_masks.(pname);

        M = nan(N_SUBJECTS,4);
        for k = 1:4
            M(:,k) = mean(occ_all{k}(mask,:), 1, 'omitnan')';
            T_subject.(sprintf('%s_%s', pname, state_names{k})) = M(:,k);
        end
        seq_means.(pname) = M;
    end

    for i = 1:numel(blocks)
        pname = blocks(i).name;
        mask = false(TRs_task,1);
        mask(blocks(i).startTR:blocks(i).endTR) = true;

        M = nan(N_SUBJECTS,4);
        for k = 1:4
            M(:,k) = mean(occ_all{k}(mask,:), 1, 'omitnan')';
        end
        block_means.(pname) = M;
    end

    for k = 1:4
        T_subject.(sprintf('RewardAll_%s', state_names{k})) = pooled_means_this_run.RewardAll(:,k);
        T_subject.(sprintf('LossAll_%s', state_names{k})) = pooled_means_this_run.LossAll(:,k);
        T_subject.(sprintf('InterblockTrim_%s', state_names{k})) = pooled_means_this_run.InterblockTrim(:,k);
    end
    writetable(T_subject, fullfile(output_dir, sprintf('%s_subject_period_means.csv', rr.short)));

    % -------- Sequential adjacent-period tests --------
    seq_rows = {};
    for p = 1:(numel(seq_periods)-1)
        from_name = seq_periods{p};
        to_name   = seq_periods{p+1};

        A = seq_means.(from_name);
        B = seq_means.(to_name);

        for k = 1:4
            [N, mean_from, mean_to, mean_diff, tstat, df, pval, ci, dz] = run_paired_test(B(:,k), A(:,k));
            seq_rows(end+1,:) = {rr.name, sprintf('%s_to_%s', from_name, to_name), state_names{k}, N, ...
                mean_from, mean_to, mean_diff, tstat, df, pval, ci(1), ci(2), dz}; %#ok<AGROW>
        end
    end

    T_seq = cell2table(seq_rows, 'VariableNames', ...
        {'Run','Transition','State','N','Mean_From','Mean_To','Mean_Diff_ToMinusFrom', ...
         't_stat','df','p_value','CI_low','CI_high','Cohens_dz'});
    writetable(T_seq, fullfile(output_dir, sprintf('%s_sequential_change_tests.csv', rr.short)));

    % -------- TASK-ON vs TASK-ON consecutive block comparisons --------
    block_rows = {};
    for i = 1:(numel(blocks)-1)
        from_name = blocks(i).name;
        to_name   = blocks(i+1).name;

        A = block_means.(from_name);
        B = block_means.(to_name);

        for k = 1:4
            [N, mean_from, mean_to, mean_diff, tstat, df, pval, ci, dz] = run_paired_test(B(:,k), A(:,k));
            block_rows(end+1,:) = {rr.name, sprintf('%s_vs_%s', from_name, to_name), state_names{k}, N, ...
                mean_from, mean_to, mean_diff, tstat, df, pval, ci(1), ci(2), dz}; %#ok<AGROW>
        end
    end

    T_block = cell2table(block_rows, 'VariableNames', ...
        {'Run','BlockComparison','State','N','Mean_FirstBlock','Mean_SecondBlock','Mean_Diff_SecondMinusFirst', ...
         't_stat','df','p_value','CI_low','CI_high','Cohens_dz'});
    writetable(T_block, fullfile(output_dir, sprintf('%s_task_on_block_comparisons.csv', rr.short)));

    % -------- Period definitions --------
    period_rows = {};
    for i = 1:numel(blocks)
        period_rows(end+1,:) = {rr.name, blocks(i).name, 'Block', ...
            blocks(i).startTR, blocks(i).endTR, ...
            (blocks(i).startTR-1)*TR, blocks(i).endTR*TR, ...
            blocks(i).endTR - blocks(i).startTR + 1}; %#ok<AGROW>
    end
    for i = 1:numel(interblocks)
        period_rows(end+1,:) = {rr.name, interblocks(i).name, 'TrimmedInterblock', ...
            interblocks(i).startTR, interblocks(i).endTR, ...
            (interblocks(i).startTR-1)*TR, interblocks(i).endTR*TR, ...
            interblocks(i).endTR - interblocks(i).startTR + 1}; %#ok<AGROW>
    end
    T_periods = cell2table(period_rows, 'VariableNames', ...
        {'Run','PeriodName','PeriodType','StartTR','EndTR','StartSec','EndSec','N_TR'});
    writetable(T_periods, fullfile(output_dir, sprintf('%s_period_definitions.csv', rr.short)));

    results.(rr.short).name = rr.name;
    results.(rr.short).task_tr_count = TRs_task;
    results.(rr.short).blocks = blocks;
    results.(rr.short).interblocks = interblocks;
    results.(rr.short).seq_periods = seq_periods;
    results.(rr.short).seq_means = seq_means;
    results.(rr.short).block_means = block_means;
    results.(rr.short).pooled_means_this_run = pooled_means_this_run;
    results.(rr.short).sequential_table = T_seq;
    results.(rr.short).task_on_block_table = T_block;
    results.(rr.short).period_table = T_periods;
end

%% ------------------------- POOLED CATEGORY STATS ACROSS RL + LR --------
fprintf('\nRunning pooled-category stats across RL + LR combined...\n');

pooled_across_runs = struct();
pooled_across_runs.Rest = rest_avg;
pooled_across_runs.RewardAll = mean(cat(3, pooled_by_run.RL.RewardAll, pooled_by_run.LR.RewardAll), 3, 'omitnan');
pooled_across_runs.LossAll = mean(cat(3, pooled_by_run.RL.LossAll, pooled_by_run.LR.LossAll), 3, 'omitnan');
pooled_across_runs.InterblockTrim = mean(cat(3, pooled_by_run.RL.InterblockTrim, pooled_by_run.LR.InterblockTrim), 3, 'omitnan');

pooled_tests = { ...
    'InterblockTrim_vs_Rest', pooled_across_runs.InterblockTrim, pooled_across_runs.Rest; ...
    'RewardAll_vs_Rest', pooled_across_runs.RewardAll, pooled_across_runs.Rest; ...
    'LossAll_vs_Rest', pooled_across_runs.LossAll, pooled_across_runs.Rest; ...
    'RewardAll_vs_InterblockTrim', pooled_across_runs.RewardAll, pooled_across_runs.InterblockTrim; ...
    'LossAll_vs_InterblockTrim', pooled_across_runs.LossAll, pooled_across_runs.InterblockTrim; ...
    'RewardAll_vs_LossAll', pooled_across_runs.RewardAll, pooled_across_runs.LossAll ...
    };

pooled_rows = {};
for c = 1:size(pooled_tests,1)
    comp_name = pooled_tests{c,1};
    X1 = pooled_tests{c,2};
    X0 = pooled_tests{c,3};

    for k = 1:4
        [N, mean_ref, mean_tgt, mean_diff, tstat, df, p, ci, dz] = run_paired_test(X1(:,k), X0(:,k));
        pooled_rows(end+1,:) = {'GAMBLING_POOLED_RL_LR', comp_name, state_names{k}, N, ...
            mean_ref, mean_tgt, mean_diff, tstat, df, p, ci(1), ci(2), dz}; %#ok<AGROW>
    end
end

T_pooled = cell2table(pooled_rows, 'VariableNames', ...
    {'Run','Comparison','State','N','Mean_Reference','Mean_Target','Mean_Diff_TargetMinusReference', ...
     't_stat','df','p_value','CI_low','CI_high','Cohens_dz'});
writetable(T_pooled, fullfile(output_dir, 'pooled_category_tests_across_RL_LR.csv'));

results.pooled_across_runs = pooled_across_runs;
results.pooled_across_runs_table = T_pooled;

save(fullfile(output_dir, 'updated_period_stats_pooledAcrossRuns_plusSequentialByRun_plusTaskOnComparisons.mat'), 'results');

fprintf('\nSaved outputs to: %s\n', output_dir);
fprintf('Key files:\n');
fprintf('  pooled_category_tests_across_RL_LR.csv\n');
fprintf('  RL_sequential_change_tests.csv\n');
fprintf('  LR_sequential_change_tests.csv\n');
fprintf('  RL_task_on_block_comparisons.csv\n');
fprintf('  LR_task_on_block_comparisons.csv\n');

end

%% ========================= HELPERS =====================================

function onsets_sec = read_onset_file(txtfile)
X = readmatrix(txtfile, 'FileType', 'text');
if isempty(X) || size(X,2) < 1
    error('Could not parse onset file: %s', txtfile);
end
onsets_sec = X(:,1);
end

function [N, mean_ref, mean_tgt, mean_diff, tstat, df, p, ci, dz] = run_paired_test(target, reference)
valid = ~isnan(target) & ~isnan(reference);
a = target(valid);
b = reference(valid);

N = numel(a);
mean_ref = mean(b, 'omitnan');
mean_tgt = mean(a, 'omitnan');
diffv = a - b;
mean_diff = mean(diffv, 'omitnan');

[~, p, ci, stats] = ttest(a, b);
tstat = stats.tstat;
df = stats.df;
dz = mean(diffv, 'omitnan') / std(diffv, 0, 'omitnan');
end

function val = get_cfg_or(cfg, fields, default_val)
val = default_val;
tmp = cfg;
for i = 1:numel(fields)
    if isstruct(tmp) && isfield(tmp, fields{i})
        tmp = tmp.(fields{i});
    else
        return;
    end
end
val = tmp;
end