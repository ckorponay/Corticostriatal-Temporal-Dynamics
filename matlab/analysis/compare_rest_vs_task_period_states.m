function results = compare_rest_vs_task_period_states(cfg_input)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end
if nargin < 1, cfg_input = []; end


% Compare state occupancy during:
%   (1) REST runs
%   (2) task inter-block periods in GAMBLING runs
%   (3) reward blocks
%   (4) loss blocks
%
% Paths are loaded from the project config.

cfg = load_project_config(cfg_input);

%% ------------------------- CONFIGURATION -------------------------------
rest_run_names = {'REST1_LR','REST1_RL','REST2_LR','REST2_RL'};

task_runs = { ...
    struct('name','GAMBLING_RL', ...
           'matfile', get_results_file(cfg, 'GAMBLING_RL'), ...
           'winfile', cfg.timing.win_rl, ...
           'lossfile', cfg.timing.loss_rl), ...
    struct('name','GAMBLING_LR', ...
           'matfile', get_results_file(cfg, 'GAMBLING_LR'), ...
           'winfile', cfg.timing.win_lr, ...
           'lossfile', cfg.timing.loss_lr) ...
    };

output_dir = get_output_dir(cfg, 'rest_vs_task_period_states');

TR = 0.72;
Striatal_Voxels = 1710;
N_SUBJECTS = cfg.runs.(rest_run_names{1}).subjects;

state_names = {'Rest1','Rest2','Rest3','Burst'};

% Block duration from onset files
block_duration_sec = 28.0;
block_duration_tr = round(block_duration_sec / TR);

% Hemodynamic buffer after each block offset
post_block_buffer_tr = 10;

rest_files = cellfun(@(rn) get_results_file(cfg, rn), rest_run_names, 'UniformOutput', false);

%% ------------------------- REST OCCUPANCY ------------------------------
fprintf('Processing REST runs...\n');

rest_state_means = []; % subj x state x run
rest_tr_counts = nan(numel(rest_files),1);

for f = 1:numel(rest_files)
    D = load(rest_files{f}, 'class_All');
    if ~isfield(D, 'class_All')
        error('class_All not found in %s', rest_files{f});
    end

    labels = D.class_All(:);
    TRs_rest = numel(labels) / (Striatal_Voxels * N_SUBJECTS);

    if abs(TRs_rest - round(TRs_rest)) > 1e-8
        error('Could not infer integer REST TR count in %s. Check N_SUBJECTS.', rest_files{f});
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

%% ------------------------- TASK PERIOD OCCUPANCY -----------------------
fprintf('Processing task periods...\n');

task_interblock_state_means = []; % subj x state x run
task_reward_state_means     = []; % subj x state x run
task_loss_state_means       = []; % subj x state x run

task_masks = struct();
task_tr_counts = nan(numel(task_runs),1);

for f = 1:numel(task_runs)
    rr = task_runs{f};

    D = load(rr.matfile, 'class_All');
    if ~isfield(D, 'class_All')
        error('class_All not found in %s', rr.matfile);
    end

    labels = D.class_All(:);

    TRs_task = numel(labels) / (Striatal_Voxels * N_SUBJECTS);
    if abs(TRs_task - round(TRs_task)) > 1e-8
        error('Could not infer integer TASK TR count in %s. Check N_SUBJECTS.', rr.matfile);
    end
    TRs_task = round(TRs_task);
    task_tr_counts(f) = TRs_task;

    S3 = reshape(labels, TRs_task, Striatal_Voxels, N_SUBJECTS);

    win_onsets_sec  = read_onset_file(rr.winfile);
    loss_onsets_sec = read_onset_file(rr.lossfile);

    win_onsets_tr  = round(win_onsets_sec ./ TR) + 1;
    loss_onsets_tr = round(loss_onsets_sec ./ TR) + 1;

    reward_mask = false(TRs_task,1);
    loss_mask   = false(TRs_task,1);

    % Reward blocks: actual block only
    for i = 1:numel(win_onsets_tr)
        s = win_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1);
        reward_mask(s:e) = true;
    end

    % Loss blocks: actual block only
    for i = 1:numel(loss_onsets_tr)
        s = loss_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1);
        loss_mask(s:e) = true;
    end

    % Buffered exclusion mask for defining inter-block periods
    block_buffered_mask = false(TRs_task,1);

    for i = 1:numel(win_onsets_tr)
        s = win_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1 + post_block_buffer_tr);
        block_buffered_mask(s:e) = true;
    end

    for i = 1:numel(loss_onsets_tr)
        s = loss_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1 + post_block_buffer_tr);
        block_buffered_mask(s:e) = true;
    end

    interblock_mask = ~block_buffered_mask;

    % Save masks and approximate time ranges
    task_masks.(rr.name).win_onsets_sec = win_onsets_sec;
    task_masks.(rr.name).loss_onsets_sec = loss_onsets_sec;
    task_masks.(rr.name).win_onsets_tr = win_onsets_tr;
    task_masks.(rr.name).loss_onsets_tr = loss_onsets_tr;
    task_masks.(rr.name).reward_mask = reward_mask;
    task_masks.(rr.name).loss_mask = loss_mask;
    task_masks.(rr.name).interblock_mask = interblock_mask;
    task_masks.(rr.name).reward_intervals_sec = mask_to_intervals(reward_mask, TR);
    task_masks.(rr.name).loss_intervals_sec = mask_to_intervals(loss_mask, TR);
    task_masks.(rr.name).interblock_intervals_sec = mask_to_intervals(interblock_mask, TR);
    task_masks.(rr.name).buffered_excluded_intervals_sec = mask_to_intervals(block_buffered_mask, TR);

    run_interblock_means = nan(N_SUBJECTS, 4);
    run_reward_means     = nan(N_SUBJECTS, 4);
    run_loss_means       = nan(N_SUBJECTS, 4);

    for k = 1:4
        occ = squeeze(mean(S3 == k, 2) * 100); % TR x subj

        run_interblock_means(:,k) = mean(occ(interblock_mask,:), 1, 'omitnan')';
        run_reward_means(:,k)     = mean(occ(reward_mask,:),     1, 'omitnan')';
        run_loss_means(:,k)       = mean(occ(loss_mask,:),       1, 'omitnan')';
    end

    task_interblock_state_means(:,:,f) = run_interblock_means; %#ok<AGROW>
    task_reward_state_means(:,:,f)     = run_reward_means; %#ok<AGROW>
    task_loss_state_means(:,:,f)       = run_loss_means; %#ok<AGROW>
end

task_interblock_avg = mean(task_interblock_state_means, 3, 'omitnan'); % subj x state
task_reward_avg     = mean(task_reward_state_means, 3, 'omitnan');     % subj x state
task_loss_avg       = mean(task_loss_state_means, 3, 'omitnan');       % subj x state

%% ------------------------- PAIRED TESTS -------------------------------
fprintf('Running paired tests...\n');

stats_rows = {};

comparisons = { ...
    'TaskInterblock_vs_Rest',      task_interblock_avg, rest_avg; ...
    'Reward_vs_TaskInterblock',    task_reward_avg,     task_interblock_avg; ...
    'Loss_vs_TaskInterblock',      task_loss_avg,       task_interblock_avg; ...
    'Reward_vs_Loss',              task_reward_avg,     task_loss_avg};

for comp = 1:size(comparisons,1)
    comp_name = comparisons{comp,1};
    X1 = comparisons{comp,2};
    X0 = comparisons{comp,3};

    for k = 1:4
        x1 = X1(:,k);
        x0 = X0(:,k);

        valid = ~isnan(x1) & ~isnan(x0);
        a = x1(valid);
        b = x0(valid);

        [~, p, ci, stats] = ttest(a, b);
        diffv = a - b;
        dz = mean(diffv, 'omitnan') / std(diffv, 0, 'omitnan');

        stats_rows(end+1,:) = {comp_name, state_names{k}, numel(a), ...
            mean(b,'omitnan'), mean(a,'omitnan'), mean(diffv,'omitnan'), ...
            stats.tstat, stats.df, p, ci(1), ci(2), dz}; %#ok<AGROW>
    end
end

T_stats = cell2table(stats_rows, 'VariableNames', ...
    {'Comparison','State','N','Mean_Reference','Mean_Target','Mean_Diff_TargetMinusReference', ...
     't_stat','df','p_value','CI_low','CI_high','Cohens_dz'});

writetable(T_stats, fullfile(output_dir, 'state_period_paired_tests.csv'));

%% ------------------------- SUBJECT-LEVEL EXPORT ------------------------
T_subj = table((1:size(rest_avg,1))', 'VariableNames', {'RowIndex'});
for k = 1:4
    T_subj.([state_names{k} '_Rest']) = rest_avg(:,k);
    T_subj.([state_names{k} '_TaskInterblock']) = task_interblock_avg(:,k);
    T_subj.([state_names{k} '_RewardBlock']) = task_reward_avg(:,k);
    T_subj.([state_names{k} '_LossBlock']) = task_loss_avg(:,k);

    T_subj.([state_names{k} '_Diff_InterblockMinusRest']) = task_interblock_avg(:,k) - rest_avg(:,k);
    T_subj.([state_names{k} '_Diff_RewardMinusInterblock']) = task_reward_avg(:,k) - task_interblock_avg(:,k);
    T_subj.([state_names{k} '_Diff_LossMinusInterblock']) = task_loss_avg(:,k) - task_interblock_avg(:,k);
    T_subj.([state_names{k} '_Diff_RewardMinusLoss']) = task_reward_avg(:,k) - task_loss_avg(:,k);
end
writetable(T_subj, fullfile(output_dir, 'rest_vs_task_periods_subject_level.csv'));

%% ------------------------- MASK RANGE EXPORT ---------------------------
mask_rows = {};
for f = 1:numel(task_runs)
    rr = task_runs{f};

    add_rows_from_intervals(rr.name, 'RewardBlock', task_masks.(rr.name).reward_intervals_sec);
    add_rows_from_intervals(rr.name, 'LossBlock', task_masks.(rr.name).loss_intervals_sec);
    add_rows_from_intervals(rr.name, 'Interblock', task_masks.(rr.name).interblock_intervals_sec);
    add_rows_from_intervals(rr.name, 'BufferedExcluded', task_masks.(rr.name).buffered_excluded_intervals_sec);
end

T_masks = cell2table(mask_rows, 'VariableNames', ...
    {'Run','PeriodType','IntervalIndex','Start_sec','End_sec','Duration_sec'});
writetable(T_masks, fullfile(output_dir, 'task_period_time_ranges.csv'));

%% ------------------------- SAVE ----------------------------------------
results = struct();
results.output_dir = output_dir;
results.rest_avg = rest_avg;
results.task_interblock_avg = task_interblock_avg;
results.task_reward_avg = task_reward_avg;
results.task_loss_avg = task_loss_avg;
results.stats_table = T_stats;
results.task_masks = task_masks;
results.mask_table = T_masks;
results.state_names = state_names;
results.rest_tr_counts = rest_tr_counts;
results.task_tr_counts = task_tr_counts;

save(fullfile(output_dir, 'rest_vs_task_period_states.mat'), 'results');

fprintf('\nSaved outputs to: %s\n', output_dir);
fprintf('Key files:\n');
fprintf('  state_period_paired_tests.csv\n');
fprintf('  rest_vs_task_periods_subject_level.csv\n');
fprintf('  task_period_time_ranges.csv\n');

    function add_rows_from_intervals(run_name, period_type, intervals)
        for ii = 1:size(intervals,1)
            s = intervals(ii,1);
            e = intervals(ii,2);
            mask_rows(end+1,:) = {run_name, period_type, ii, s, e, e - s}; %#ok<AGROW>
        end
    end

end

%% ========================= HELPERS =====================================

function onsets_sec = read_onset_file(txtfile)
X = readmatrix(txtfile, 'FileType', 'text');
if isempty(X) || size(X,2) < 1
    error('Could not parse onset file: %s', txtfile);
end
onsets_sec = X(:,1);
end

function intervals_sec = mask_to_intervals(mask, TR)
% Convert logical TR mask into contiguous [start_sec, end_sec] intervals.
mask = mask(:);
d = diff([false; mask; false]);
starts = find(d == 1);
ends   = find(d == -1) - 1;

intervals_sec = nan(numel(starts), 2);
for i = 1:numel(starts)
    % TR index t corresponds roughly to [(t-1)*TR, t*TR)
    intervals_sec(i,1) = (starts(i)-1) * TR;
    intervals_sec(i,2) = ends(i) * TR;
end
end
