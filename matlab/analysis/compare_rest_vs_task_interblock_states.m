function results = compare_rest_vs_task_interblock_states(cfg_input)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end
if nargin < 1, cfg_input = []; end


% Compare state occupancy during:
%   (1) REST runs
%   (2) task inter-block periods in GAMBLING runs
%
% Paths are loaded from the project config.

cfg = load_project_config(cfg_input);

%% ------------------------- CONFIGURATION -------------------------------
rest_run_names = {'REST1_LR','REST1_RL','REST2_LR','REST2_RL'};
rest_files = cellfun(@(rn) get_results_file(cfg, rn), rest_run_names, 'UniformOutput', false);

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

output_dir = get_output_dir(cfg, 'rest_vs_task_interblock_states');

TR = 0.72;
TRs_rest = cfg.runs.REST1_LR.trs;
TRs_task = cfg.runs.GAMBLING_RL.trs;
Striatal_Voxels = 1710;
state_names = {'Rest1','Rest2','Rest3','Burst'};

% Block duration from onset files
block_duration_sec = 28.0;
block_duration_tr = round(block_duration_sec / TR);

% Hemodynamic buffer after each block offset
post_block_buffer_tr = 10;

%% ------------------------- REST OCCUPANCY ------------------------------
fprintf('Processing REST runs...\n');

rest_state_means = []; % subj x state x run

for f = 1:numel(rest_files)
    D = load(rest_files{f}, 'class_All');
    if ~isfield(D, 'class_All')
        error('class_All not found in %s', rest_files{f});
    end

    labels = D.class_All(:);
    n_subjects = numel(labels) / (TRs_rest * Striatal_Voxels);
    if abs(n_subjects - round(n_subjects)) > 1e-8
        error('REST class_All size mismatch in %s', rest_files{f});
    end
    n_subjects = round(n_subjects);

    S3 = reshape(labels, TRs_rest, Striatal_Voxels, n_subjects);

    run_means = nan(n_subjects, 4);
    for k = 1:4
        occ = squeeze(mean(S3 == k, 2) * 100); % TR x subj
        run_means(:,k) = mean(occ, 1, 'omitnan')';
    end

    rest_state_means(:,:,f) = run_means; %#ok<AGROW>
end

rest_avg = mean(rest_state_means, 3, 'omitnan'); % subj x state

%% ------------------------- TASK INTERBLOCK OCCUPANCY -------------------
fprintf('Processing task inter-block periods...\n');

task_interblock_state_means = []; % subj x state x run
task_masks = struct();

for f = 1:numel(task_runs)
    rr = task_runs{f};

    D = load(rr.matfile, 'class_All');
    if ~isfield(D, 'class_All')
        error('class_All not found in %s', rr.matfile);
    end

    labels = D.class_All(:);
    n_subjects = numel(labels) / (TRs_task * Striatal_Voxels);
    if abs(n_subjects - round(n_subjects)) > 1e-8
        error('TASK class_All size mismatch in %s', rr.matfile);
    end
    n_subjects = round(n_subjects);

    S3 = reshape(labels, TRs_task, Striatal_Voxels, n_subjects);

    win_onsets_sec  = read_onset_file(rr.winfile);
    loss_onsets_sec = read_onset_file(rr.lossfile);

    win_onsets_tr  = round(win_onsets_sec ./ TR) + 1;
    loss_onsets_tr = round(loss_onsets_sec ./ TR) + 1;

    block_mask = false(TRs_task,1);

    % mark win blocks
    for i = 1:numel(win_onsets_tr)
        s = win_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1 + post_block_buffer_tr);
        block_mask(s:e) = true;
    end

    % mark loss blocks
    for i = 1:numel(loss_onsets_tr)
        s = loss_onsets_tr(i);
        e = min(TRs_task, s + block_duration_tr - 1 + post_block_buffer_tr);
        block_mask(s:e) = true;
    end

    interblock_mask = ~block_mask;

    task_masks.(rr.name).block_mask = block_mask;
    task_masks.(rr.name).interblock_mask = interblock_mask;
    task_masks.(rr.name).win_onsets_tr = win_onsets_tr;
    task_masks.(rr.name).loss_onsets_tr = loss_onsets_tr;

    run_means = nan(n_subjects, 4);
    for k = 1:4
        occ = squeeze(mean(S3 == k, 2) * 100); % TR x subj
        run_means(:,k) = mean(occ(interblock_mask,:), 1, 'omitnan')';
    end

    task_interblock_state_means(:,:,f) = run_means; %#ok<AGROW>
end

task_interblock_avg = mean(task_interblock_state_means, 3, 'omitnan'); % subj x state

%% ------------------------- PAIRED TESTS -------------------------------
fprintf('Running paired tests...\n');

rows = {};
for k = 1:4
    x_rest = rest_avg(:,k);
    x_task = task_interblock_avg(:,k);

    valid = ~isnan(x_rest) & ~isnan(x_task);
    xr = x_rest(valid);
    xt = x_task(valid);

    [~, p, ci, stats] = ttest(xt, xr);
    diffv = xt - xr;
    dz = mean(diffv, 'omitnan') / std(diffv, 0, 'omitnan');

    rows(end+1,:) = {state_names{k}, numel(xr), ...
        mean(xr,'omitnan'), mean(xt,'omitnan'), mean(diffv,'omitnan'), ...
        stats.tstat, stats.df, p, ci(1), ci(2), dz}; %#ok<AGROW>
end

T_stats = cell2table(rows, 'VariableNames', ...
    {'State','N','Mean_Rest','Mean_TaskInterblock','Mean_Diff_TaskMinusRest', ...
     't_stat','df','p_value','CI_low','CI_high','Cohens_dz'});

writetable(T_stats, fullfile(output_dir, 'rest_vs_task_interblock_paired_tests.csv'));

%% ------------------------- SUBJECT-LEVEL EXPORT ------------------------
T_subj = table((1:size(rest_avg,1))', 'VariableNames', {'RowIndex'});
for k = 1:4
    T_subj.([state_names{k} '_Rest']) = rest_avg(:,k);
    T_subj.([state_names{k} '_TaskInterblock']) = task_interblock_avg(:,k);
    T_subj.([state_names{k} '_Diff']) = task_interblock_avg(:,k) - rest_avg(:,k);
end
writetable(T_subj, fullfile(output_dir, 'rest_vs_task_interblock_subject_level.csv'));

%% ------------------------- SAVE ----------------------------------------
results = struct();
results.output_dir = output_dir;
results.rest_avg = rest_avg;
results.task_interblock_avg = task_interblock_avg;
results.stats_table = T_stats;
results.task_masks = task_masks;
results.state_names = state_names;

save(fullfile(output_dir, 'rest_vs_task_interblock_states.mat'), 'results');

fprintf('\nSaved outputs to: %s\n', output_dir);

end

%% ========================= HELPERS =====================================

function onsets_sec = read_onset_file(txtfile)
X = readmatrix(txtfile, 'FileType', 'text');
if isempty(X) || size(X,2) < 1
    error('Could not parse onset file: %s', txtfile);
end
onsets_sec = X(:,1);
end
