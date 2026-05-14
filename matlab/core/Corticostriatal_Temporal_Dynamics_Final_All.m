function results = Corticostriatal_Temporal_Dynamics_Final_All(cfg_input, run_name)
script_dir = fileparts(mfilename('fullpath'));
config_dir = fullfile(script_dir, '..', 'config');
if exist(config_dir, 'dir'), addpath(config_dir); end

% Edge-based coactivation states with Louvain (fcn_edgets2edgecorr).
% BURSTS: hybrid/mean-only/L2-energy OR DBSCAN (auto/user).
% Includes robust NIfTI writer and per-subject "mean positive inputs on burst TRs".
%
% Usage:
%   results = Corticostriatal_Temporal_Dynamics_Final_All(cfg, ''GAMBLING_RL'');
%   results = Corticostriatal_Temporal_Dynamics_Final_All(@user_paths, ''REST1_LR'');
%
% Paths and run-specific settings are loaded from the project config.

if nargin < 2 || isempty(run_name)
    error('Provide a config source and run_name, e.g. Corticostriatal_Temporal_Dynamics_Final_All(cfg, ''GAMBLING_RL'').');
end
cfg = load_project_config(cfg_input);
[run_cfg, resolved_results_file, resolved_export_dir] = resolve_run_paths(cfg, run_name);

results = struct();
results.run_name = run_name;

%% ------------------------- USER PARAMETERS ------------------------------
P  = run_cfg.striatal_dir;
P2 = run_cfg.cortical_dir;

Subjects             = run_cfg.subjects;
TRs                  = run_cfg.trs;
Striatal_Voxels      = 1710;
Total_Cortical_ROIs  = 21;
Target_Cortical_ROIs = 5;

dataset_type = run_cfg.dataset_type;  % 'rest' or 'task'
apply_standardization = false;        % standardize CP before detection/exports?

% ---- Burst logic --------------------------------------------------------
burst.detector           = 'hybrid_mean_mofn';
burst.coordination.mode  = 'all_pos';
burst.rule               = 'hybrid_mean_mofn';
burst.m_of_n             = 1;

burst.mode               = 'reference';
burst.reference.fit      = false;
burst.quantile           = 0.95;
burst.mixture.maxiter    = 1000;
burst.mixture.Nsub       = 200000;

template.path               = cfg.template.reference;
rest_params_file            = cfg.rest_params_file;
rest_template.reference.fit = false;
rest_train_cap              = 50000;

% ---- DBSCAN options -----------------------------------------------------
dbs.feature_space   = 'l2';
dbs.posabs_mode     = burst.coordination.mode;
dbs.fit_cap         = 30000;
dbs.run_cap         = 100000;
dbs.assign_batch    = 100000;
dbs.auto.minpts_range = 10:40;
dbs.auto.knee_frac    = 0.01;
dbs.user.eps     = 1.0;
dbs.user.MinPts  = 20;

% ---- NIfTI export -------------------------------------------------------
if isfield(cfg,'nifti_img_root') && ~isempty(cfg.nifti_img_root)
    nifti.imgRoot = cfg.nifti_img_root;
elseif isfield(cfg,'nifti') && isfield(cfg.nifti,'imgRoot')
    nifti.imgRoot = cfg.nifti.imgRoot;
else
    nifti.imgRoot = fileparts(cfg.mask_path);
end
nifti.maskPath     = cfg.mask_path;
if isfield(run_cfg,'nifti_out_dir') && ~isempty(run_cfg.nifti_out_dir)
    nifti.out_dir = run_cfg.nifti_out_dir;
else
    nifti.out_dir = fullfile(nifti.imgRoot, [run_name '_avg5_inputs_4D']);
end
nifti.scale_factor = 100;
nifti.write        = true;

% ---- CSV/plots and .mat outputs ----------------------------------------
export.enable_csv        = true;
export.enable_plots      = true;
export.dir = resolved_export_dir;
export.voxel_combo_csv   = false;
export.voxel_combo_topN  = 10;
export.voxel_combo_group_csv = true;

save_outputs = true;
if isfield(run_cfg,'save_path') && ~isempty(run_cfg.save_path)
    save_path = run_cfg.save_path;
elseif isfield(run_cfg,'output_dir') && ~isempty(run_cfg.output_dir)
    if ~exist(run_cfg.output_dir,'dir'), mkdir(run_cfg.output_dir); end
    save_path = fullfile(run_cfg.output_dir, 'efc_states_louvain_all_detectors.mat');
else
    save_path = resolved_results_file;
    save_dir = fileparts(save_path);
    if ~exist(save_dir,'dir'), mkdir(save_dir); end
end
results.output_paths = struct('results_file', save_path, 'export_dir', export.dir, 'nifti_out_dir', nifti.out_dir);
%% ------------------------------------------------------------------------

%% -------------------------- REPRO / PATHS -------------------------------
rng(42,'twister');
if exist('RandStream','class'), RandStream.setGlobalStream(RandStream('mt19937ar','Seed',42)); end
if exist('maxNumCompThreads','file')==2, maxNumCompThreads(1); end

add_project_toolboxes(cfg);

S = dir(fullfile(P,'*rStriatum*'));  [~,ix]  = sort({S.name});  S  = S(ix);
S2= dir(fullfile(P2,'*.csv')); [~,ix2] = sort({S2.name}); S2 = S2(ix2);
assert(numel(S)  >= Subjects, 'Not enough striatal files.');
assert(numel(S2) >= Subjects, 'Not enough cortical files.');

fprintf('Checking file dimensions for first subject...
');
T_test = readtable(fullfile(P, S(1).name), 'NumHeaderLines', 1);
fprintf('Striatal file: %d rows, %d cols
', height(T_test), width(T_test));
T2_test = readtable(fullfile(P2, S2(1).name), 'NumHeaderLines', 1);
fprintf('Cortical file: %d rows, %d cols
', height(T2_test), width(T2_test));

% NIfTI prep
if nifti.write
    if ~exist(nifti.out_dir,'dir'), mkdir(nifti.out_dir); end
    mask   = load_untouch_nii(nifti.maskPath);
    maskSz = size(mask.img);
    in_brain = find(mask.img(:)>0);
    assert(numel(in_brain)==Striatal_Voxels,'Mask voxels != Striatal_Voxels.');
end

%% ------------------------ Fixed Top-5 (Option A) ------------------------
rh_frontal_cols = [60 61 62 63 64 66 72 73 76 78 79 83 84 85 86 88 94 95 96 97 98];
assert(numel(rh_frontal_cols)==Total_Cortical_ROIs,'ROI index mismatch.');

TPL = struct();
if ~burst.reference.fit || ~rest_template.reference.fit
    if exist(template.path,'file')==2
        fprintf('Loading reference template: %s\n', template.path);
        TPL_loaded = load(template.path);
        if isfield(TPL_loaded,'mu_for_z'),    mu_for_z    = TPL_loaded.mu_for_z; end
        if isfield(TPL_loaded,'sigma_for_z'), sigma_for_z = TPL_loaded.sigma_for_z; end
        if isfield(TPL_loaded,'tau_vec'),     tau_vec     = TPL_loaded.tau_vec; end
        if isfield(TPL_loaded,'tau_mean'),    tau_mean    = TPL_loaded.tau_mean; end
        if isfield(TPL_loaded,'centroids_z'), centroids_z = TPL_loaded.centroids_z; end
        if isfield(TPL_loaded,'K_rest'),      K_rest      = TPL_loaded.K_rest; end
        if isfield(TPL_loaded,'FixedTop5Idx'),   FixedTop5Idx    = TPL_loaded.FixedTop5Idx; end
        if isfield(TPL_loaded,'FixedTop5_ROIid'),FixedTop5_ROIid = TPL_loaded.FixedTop5_ROIid; end
        TPL = merge_structs(TPL, TPL_loaded);
    else
        fprintf('Warning: Template file not found: %s\n', template.path);
    end
end
if exist('tau_mean','var'),   fprintf('[TEMPLATE] Using tau_mean=%.3f (z)\n', tau_mean); end
if exist('centroids_z','var'),fprintf('[TEMPLATE] Using K_rest=%d rest centroids from template\n', size(centroids_z,1)); end
if exist('FixedTop5Idx','var'), fprintf('[TEMPLATE] Using fixed top-5 per voxel from template\n'); end
use_fixed_from_template = exist('FixedTop5Idx','var') && ~isempty(FixedTop5Idx);

if ~use_fixed_from_template
    fprintf('Pass 1/2: accumulating group static FC to choose fixed top-5 per voxel...\n');
    GroupStatic = zeros(Striatal_Voxels, Total_Cortical_ROIs, 'double');
    for i = 1:Subjects
        fprintf('Processing subject %d for top-5 selection...\n', i);
        T  = readtable(fullfile(P, S(i).name), 'NumHeaderLines',1);
        Xs = double(table2array(T))';  Zs = zscore(Xs, 0, 1); clear T Xs
        T2 = readtable(fullfile(P2,S2(i).name),'NumHeaderLines',1);
        Xc = double(table2array(T2));  Xc = Xc(:, rh_frontal_cols);
        Zc = zscore(Xc, 0, 1); clear T2 Xc
        GroupStatic = GroupStatic + (Zs' * Zc) / TRs;    % Vox x 21
    end
    GroupStatic = GroupStatic / Subjects;
    FixedTop5Idx     = zeros(Striatal_Voxels, Target_Cortical_ROIs, 'uint8');
    FixedTop5_ROIid  = zeros(Striatal_Voxels, Target_Cortical_ROIs, 'uint16');
    for x = 1:Striatal_Voxels
        [~, idx] = maxk(GroupStatic(x,:), Target_Cortical_ROIs);
        FixedTop5Idx(x,:)    = uint8(idx);
        FixedTop5_ROIid(x,:) = uint16(rh_frontal_cols(idx));
    end
    fprintf('Fixed top-5 chosen per voxel.\n');
    if strcmpi(burst.mode,'reference') && burst.reference.fit
        TPL.FixedTop5Idx   = FixedTop5Idx;
        TPL.FixedTop5_ROIid= FixedTop5_ROIid;
    end
end

%% ----------------------- Build CP matrix (Pass 2) -----------------------
fprintf('Pass 2/2: building CP matrix + Jaccard...\n');
N_total = Subjects*TRs*Striatal_Voxels;
Final_EdgeTimeseries_Top5 = zeros(N_total, Target_Cortical_ROIs);
Top5_ROIid_Subject  = zeros(Striatal_Voxels, Subjects, Target_Cortical_ROIs,'uint16');
Jaccard_Subject     = zeros(Striatal_Voxels, Subjects);
StriatalBOLD_Mean_TS= zeros(TRs, Subjects);

I=1;
for i=1:Subjects
    fprintf('Processing subject %d for CP matrix...\n', i);
    T = readtable(fullfile(P,S(i).name),'NumHeaderLines',1);
    X = double(table2array(T))';  StriatalBOLD_Mean_TS(:,i)=mean(X,2,'omitnan'); 
    z1 = zscore(X, 0, 1);  clear T X
    T2 = readtable(fullfile(P2,S2(i).name),'NumHeaderLines',1);
    X2 = double(table2array(T2)); X2=X2(:,rh_frontal_cols); 
    z2 = zscore(X2, 0, 1);  clear T2 X2
    for x=1:Striatal_Voxels
        CP = z1(:,x) .* z2;                             % TRs x 21
        [~,idx5s] = maxk(mean(CP,1),Target_Cortical_ROIs);
        Top5_ROIid_Subject(x,i,:) = uint16(rh_frontal_cols(idx5s));
        set_fixed = double(FixedTop5_ROIid(x,:));
        set_subj  = double(squeeze(Top5_ROIid_Subject(x,i,:)))';
        Jaccard_Subject(x,i) = numel(intersect(set_fixed,set_subj))/numel(union(set_fixed,set_subj));
        idx5  = double(FixedTop5Idx(x,:));
        CP5   = CP(:,idx5);                              % TRs x 5
        Final_EdgeTimeseries_Top5(I:I+TRs-1,:) = CP5;
        I=I+TRs;
    end
end

%% ---------------- Standardization & Template load/save ------------------
fprintf('Computing empirical statistics from correlation products...\n');
mu_for_z    = mean(Final_EdgeTimeseries_Top5, 'all');
sigma_for_z = std( Final_EdgeTimeseries_Top5, 0, 'all'); if sigma_for_z == 0, sigma_for_z = 1; end
if strcmpi(burst.mode,'reference') && ~burst.reference.fit
    fprintf('[TEMPLATE] Using template mu=%.6f, sigma=%.6f\n', mu_for_z, sigma_for_z);
elseif strcmpi(dataset_type, 'task') && exist(rest_params_file, 'file')
    fprintf('[CROSS-CONDITION] Loading rest standardization parameters...\n');
    rest_params = load(rest_params_file); mu_for_z = rest_params.mu_for_z; sigma_for_z = rest_params.sigma_for_z;
    fprintf('[CROSS-CONDITION] Using rest-derived mu=%.6f, sigma=%.6f\n', mu_for_z, sigma_for_z);
else
    fprintf('[CURRENT-DATA] Using empirical mu=%.6f, sigma=%.6f\n', mu_for_z, sigma_for_z);
    if strcmpi(dataset_type, 'rest')
        save(rest_params_file, 'mu_for_z', 'sigma_for_z');
        fprintf('[REST] Saved standardization parameters for task comparison\n');
    end
end

% Build CP array used downstream (standardized if requested)
if apply_standardization
    fprintf('Applying standardization to correlation products...\n');
    CPz_for_fit = (Final_EdgeTimeseries_Top5 - mu_for_z) ./ sigma_for_z;
else
    fprintf('Skipping standardization - using raw correlation products\n');
    CPz_for_fit = Final_EdgeTimeseries_Top5;
end

% ===== ROBUST NIFTI WRITER: always runs if nifti.write ===================
if nifti.write
    fprintf('[NIfTI] Attempting writes (%s values)...\n', tern(apply_standardization,'standardized','raw'));

    % Preconditions
    assert(exist('mask','var')==1 && ~isempty(mask), '[NIfTI] mask not loaded.');
    assert(exist('in_brain','var')==1 && ~isempty(in_brain), '[NIfTI] in_brain index not set.');
    if ~exist(nifti.out_dir,'dir'), mkdir(nifti.out_dir); end
    assert(exist(nifti.out_dir,'dir')==7, '[NIfTI] Cannot create out_dir: %s', nifti.out_dir);

    % Writer availability
    has_gz  = exist('save_untouch_nii_gz','file')==2;
    has_nii = exist('save_untouch_nii','file')==2;
    has_mk  = exist('make_nii','file')==2;  % optional fallback
    assert(has_gz || has_nii || has_mk, ...
        '[NIfTI] No writer found: need save_untouch_nii_gz or save_untouch_nii (NIfTI_20140122).');

    % Memory check for full 4D
    maskSz = size(mask.img);
    bytes_needed = double(numel(mask.img)) * double(TRs) * 4; % single precision
    use_series = bytes_needed > 2.5e9;  % ~2.5 GB threshold
    if use_series
        fprintf('[NIfTI] 4D volume would be ~%.1f GB — writing 3D time-series instead.\n', bytes_needed/1e9);
    end

    for i = 1:Subjects
        fprintf('[NIfTI] Subject %d of %d...\n', i, Subjects);

        % Compute mean-of-5 per TR for this subject
        subj_avg5 = zeros(TRs, Striatal_Voxels, 'single');
        for x = 1:Striatal_Voxels
            idx0 = ((i-1)*Striatal_Voxels + (x-1))*TRs + (1:TRs);
            CP5_here = CPz_for_fit(idx0, :);                % TRs x 5 (raw or standardized)
            subj_avg5(:, x) = single(mean(CP5_here, 2));
        end

        if ~use_series
            % Build 4D: [X Y Z T]
            vol4d = zeros([maskSz TRs],'single');
            for t = 1:TRs
                frame = zeros(maskSz,'single');
                frame(in_brain) = subj_avg5(t,:)' * nifti.scale_factor;
                vol4d(:,:,:,t) = frame;
            end

            gm = mask; gm.img = vol4d;
            gm.hdr.dime.datatype = 16; gm.hdr.dime.bitpix = 32;
            gm.hdr.dime.dim(1) = 4;    gm.hdr.dime.dim(5) = TRs;

            out_gz = fullfile(nifti.out_dir, sprintf('Subj%03d_avg5inputs_4D.nii.gz', i));
            if has_gz
                save_untouch_nii_gz(gm, out_gz);
            elseif has_nii
                out_nii = strrep(out_gz, '.nii.gz', '.nii');
                save_untouch_nii(gm, out_nii);
                try, gzip(out_nii); delete(out_nii); catch, warning('[NIfTI] gzip failed: %s', out_nii); end
            else
                nii4 = make_nii(vol4d); save_nii(nii4, strrep(out_gz, '.gz',''));
            end

            fprintf('[NIfTI]  Wrote 4D → %s\n', out_gz);
        else
            % Write per-TR 3D series
            series_dir = fullfile(nifti.out_dir, sprintf('Subj%03d_avg5inputs_3Dseries', i));
            if ~exist(series_dir,'dir'), mkdir(series_dir); end

            for t = 1:TRs
                frame = zeros(maskSz,'single');
                frame(in_brain) = subj_avg5(t,:)' * nifti.scale_factor;

                gm = mask; gm.img = frame;
                gm.hdr.dime.datatype = 16; gm.hdr.dime.bitpix = 32;
                gm.hdr.dime.dim(1) = 3;    gm.hdr.dime.dim(5) = 1;

                out_gz = fullfile(series_dir, sprintf('Subj%03d_t%04d.nii.gz', i, t));
                if has_gz
                    save_untouch_nii_gz(gm, out_gz);
                elseif has_nii
                    out_nii = strrep(out_gz, '.nii.gz', '.nii');
                    save_untouch_nii(gm, out_nii);
                    try, gzip(out_nii); delete(out_nii); catch, warning('[NIfTI] gzip failed: %s', out_nii); end
                else
                    nii3 = make_nii(frame); save_nii(nii3, strrep(out_gz, '.gz',''));
                end
            end

            fprintf('[NIfTI]  Wrote 3D series → %s (TRs=%d)\n', series_dir, TRs);
        end
    end
end
% =========================================================================

% Build per-input base (for tau_vec) & mean-of-5 (for tau_mean)
switch lower(burst.coordination.mode)
    case 'all_abs', base_for_tau = abs(CPz_for_fit);
    otherwise,      base_for_tau = max(CPz_for_fit,0);
end
m5_all = mean(base_for_tau,2);

% Learn/Load tau_vec
switch lower(burst.mode)
    case 'reference'
        if burst.reference.fit
            single_tau = mixture_threshold_1d_fast(base_for_tau(:), burst.mixture.maxiter, burst.mixture.Nsub);
            tau_vec = repmat(single_tau, 1, Target_Cortical_ROIs);
            TPL.mu_for_z     = mu_for_z;    TPL.sigma_for_z = sigma_for_z;
            TPL.tau_vec      = tau_vec;     TPL.coordination = burst.coordination;
        else
            tau_vec = TPL.tau_vec;
        end
    case 'mixture'
        single_tau = mixture_threshold_1d_fast(base_for_tau(:), burst.mixture.maxiter, burst.mixture.Nsub);
        tau_vec = repmat(single_tau, 1, Target_Cortical_ROIs);
        fprintf('[MIXTURE] Learned single tau=%.3f for all inputs\n', single_tau);
    case 'quantile'
        single_tau = quantile(base_for_tau(:), burst.quantile);
        tau_vec = repmat(single_tau, 1, Target_Cortical_ROIs);
        fprintf('[QUANTILE] Used %.2f quantile tau=%.3f for all inputs\n', burst.quantile, single_tau);
    otherwise
        error('Unknown burst.mode: %s', burst.mode);
end

% tau_mean
if strcmpi(burst.mode,'reference') && ~burst.reference.fit && isfield(TPL,'tau_mean')
    tau_mean = TPL.tau_mean; fprintf('[TEMPLATE] Using template tau_mean=%.3f\n', tau_mean);
else
    tau_mean = mixture_threshold_1d_fast(m5_all, burst.mixture.maxiter, burst.mixture.Nsub);
    if burst.reference.fit, TPL.tau_mean = tau_mean; end
    fprintf('[FITTED] tau_mean=%.3f for current dataset\n', tau_mean);
end

if strcmpi(burst.mode,'reference') && burst.reference.fit
    save(template.path,'-struct','TPL','-v7'); fprintf('Saved reference template → %s\n', template.path);
end

%% ---------------- Per-input pass mask & counts --------------------------
N = size(CPz_for_fit,1);
pass_mask  = false(N,Target_Cortical_ROIs);
pass_count = zeros(N,1,'uint8');
for j=1:Target_Cortical_ROIs
    col = CPz_for_fit(:,j);
    switch lower(burst.coordination.mode)
        case 'all_abs', colb = abs(col);
        otherwise,      colb = max(col,0);
    end
    pm = colb >= tau_vec(j);
    pass_mask(:,j)=pm; pass_count = pass_count + uint8(pm);
end

%% ------------------------- BURST DETECTION ------------------------------
fprintf('Burst detector: %s\n', burst.detector);
switch lower(burst.detector)
    case 'hybrid_mean_mofn'
        m_of_n_eff = clamp_round(burst.m_of_n, 1, Target_Cortical_ROIs);
        is_burst = (m5_all >= tau_mean) & (pass_count >= m_of_n_eff);
        burst_descr = sprintf('HYBRID: tau_mean=%.3f z, m=%d, coord=%s', tau_mean, m_of_n_eff, burst.coordination.mode);
    case 'mean_only'
        is_burst = (m5_all >= tau_mean);
        burst_descr = sprintf('MEAN-ONLY: tau_mean=%.3f z, coord=%s', tau_mean, burst.coordination.mode);
    case 'l2_energy'
        l2 = sqrt(mean(base_for_tau.^2,2));
        tau_l2 = mixture_threshold_1d_fast(l2, burst.mixture.maxiter, burst.mixture.Nsub);
        is_burst = (l2 >= tau_l2);
        burst_descr = sprintf('L2-ENERGY: tau_L2=%.3f, coord=%s', tau_l2, burst.coordination.mode);
    case {'dbscan_auto','dbscan_user'}
        Xfeat = build_dbscan_features(CPz_for_fit, dbs.feature_space, dbs.posabs_mode);
        switch lower(burst.detector)
            case 'dbscan_user'
                eps_use    = dbs.user.eps;   minpts_use = dbs.user.MinPts;
                fprintf('[DBSCAN user] eps=%.4f, MinPts=%d\n', eps_use, minpts_use);
            otherwise
                fprintf('[DBSCAN auto] parameter search on fit subset (cap=%d)...\n', dbs.fit_cap);
                [eps_use, minpts_use] = dbscan_choose_auto(Xfeat, dbs);
                fprintf('→ chosen eps=%.4f, MinPts=%d\n', eps_use, minpts_use);
        end
        fprintf('[DBSCAN] final clustering on run subset (cap=%d) + batch assign (%.0f)...\n', dbs.run_cap, dbs.assign_batch);
        is_burst = dbscan_classify_all(Xfeat, eps_use, minpts_use, dbs);
        burst_descr = sprintf('DBSCAN: eps=%.4f, MinPts=%d, feat=%s (%s)', eps_use, minpts_use, dbs.feature_space, dbs.posabs_mode);
    otherwise
        error('Unknown burst.detector: %s', burst.detector);
end

burst_fraction = 100*mean(is_burst);
fprintf('Bursts: %s | burst fraction=%.4f%%\n', burst_descr, burst_fraction);
fprintf('Dataset type: %s | Total frames: %d | Burst frames: %d\n', dataset_type, numel(is_burst), sum(is_burst));
if apply_standardization
    fprintf('Standardization: APPLIED\n');
else
    fprintf('Standardization: SKIPPED\n');
end

% ===== NEW: Subject-wise mean of positive inputs on burst TRs ============
TRs_per_subject = TRs * Striatal_Voxels;
SubjectAvgPos5_onBursts_raw = nan(Subjects,1);
SubjectAvgPos5_onBursts_z   = nan(Subjects,1);
SubjectBurstFrameCount      = zeros(Subjects,1);
for s = 1:Subjects
    idx_s = (s-1)*TRs_per_subject + (1:TRs_per_subject);
    isb_s = is_burst(idx_s);
    if any(isb_s)
        pos_raw = mean( max(Final_EdgeTimeseries_Top5(idx_s, :), 0), 2);  % ReLU then avg over 5
        SubjectAvgPos5_onBursts_raw(s) = mean(pos_raw(isb_s));

        if apply_standardization
            pos_z = mean( max(CPz_for_fit(idx_s, :), 0), 2);
        else
            pos_z = mean( max( (Final_EdgeTimeseries_Top5(idx_s, :) - mu_for_z) ./ sigma_for_z, 0), 2);
        end
        SubjectAvgPos5_onBursts_z(s) = mean(pos_z(isb_s));

        SubjectBurstFrameCount(s) = nnz(isb_s);
    else
        SubjectAvgPos5_onBursts_raw(s) = NaN;
        SubjectAvgPos5_onBursts_z(s)   = NaN;
        SubjectBurstFrameCount(s)      = 0;
    end
end
fprintf('Computed SubjectAvgPos5_onBursts (raw & z). Median burst frames/subject = %d\n', median(SubjectBurstFrameCount));
% =========================================================================

%% ----------------------- REST STATES via Louvain ------------------------
indx_Burst = find(is_burst); indx_Rest = find(~is_burst);
have_rest_template = exist('TPL','var') && isfield(TPL,'centroids_z');
if ~rest_template.reference.fit && ~have_rest_template
    if exist(template.path,'file')==2
        TL = load(template.path); TPL = merge_structs(TPL, TL);
    else
        fprintf('Warning: No rest template found, will fit new one\n');
        rest_template.reference.fit = true;
    end
end

if ~rest_template.reference.fit && isfield(TPL,'centroids_z')
    centroids_z = TPL.centroids_z;  K_rest = size(centroids_z,1);
    fprintf('Loaded rest-template centroids (K_rest=%d)\n', K_rest);
else
    n_rest = numel(indx_Rest); if n_rest==0, error('No rest frames found.'); end
    train_n = min(rest_train_cap, n_rest);
    idx_train = randsample(indx_Rest, train_n);
    R_train   = Final_EdgeTimeseries_Top5(idx_train,:);

    if apply_standardization
        R_train_z = (R_train - mu_for_z) ./ sigma_for_z;
    else
        R_train_z = R_train;
    end

    W = fcn_edgets2edgecorr(R_train_z'); W=(W+W')/2; W(1:train_n+1:end)=0;
    n  = size(W,1); M = uint32((1:n)'); Q0=-1; Q1=0;
    while (Q1-Q0)>1e-7
        Q0=Q1; [M,Q1] = community_louvain(W,[],M,'negative_asym');
    end
    M_train = M; K_rest = double(max(M_train));
    M_train = canonicalize_by_signed_mean_ascending(M_train, R_train_z);
    centroids_z = zeros(K_rest, size(R_train_z,2));
    for k=1:K_rest, centroids_z(k,:) = mean(R_train_z(M_train==k,:),1); end
    if rest_template.reference.fit
        TPL.centroids_z = centroids_z; TPL.K_rest = K_rest;
        save(template.path,'-struct','TPL','-v7'); fprintf('Saved rest centroids into template.\n');
    end
end

R_all   = Final_EdgeTimeseries_Top5(indx_Rest,:);
if apply_standardization
    R_all_z = (R_all - mu_for_z) ./ sigma_for_z;
else
    R_all_z = R_all;
end
assigned_rest = assign_by_cosine(R_all_z, centroids_z);   % 1..K_rest

% Compact labels: 1..K_rest for rest, K_rest+1 = Burst
N = size(Final_EdgeTimeseries_Top5,1);
class_All = zeros(N,1,'uint16');
class_All(indx_Rest)  = uint16(assigned_rest);
burst_label           = uint16(K_rest+1);
class_All(indx_Burst) = burst_label;

%% ------------------------ Metrics & Exports (key ones) ------------------
TRs_per_subject = TRs*Striatal_Voxels;

occ = nan(Subjects, K_rest+1);
for s=1:Subjects
    idx = (s-1)*TRs_per_subject + (1:TRs_per_subject);
    labs_s = class_All(idx);
    for k=1:K_rest+1, occ(s,k)=mean(labs_s==k); end
end
TRs_in_CP_State_SubjectMean = 100*mean(occ,1);
TRs_in_CP_State_SubjectSE   = 100*std(occ,0,1)/sqrt(Subjects);

K_total = K_rest+1; D=size(Final_EdgeTimeseries_Top5,2);
labels  = class_All(:); N_total=numel(labels);
counts_per_state = accumarray(double(labels),1,[K_total 1],@sum,0);
Avg_CP_State = zeros(K_total,D);
for d=1:D
    sums_d = accumarray(double(labels),Final_EdgeTimeseries_Top5(:,d),[K_total 1],@sum,0);
    Avg_CP_State(:,d) = sums_d./max(counts_per_state,1);
end
TRs_in_CP_State_Global = 100*(counts_per_state(:)'/N_total);

S3 = reshape(labels, TRs, Striatal_Voxels, Subjects);
A  = double(S3(1:end-1,:,:)); B=double(S3(2:end,:,:));
pair_idx = sub2ind([K_total K_total], A(:), B(:));
Transitions = reshape(accumarray(pair_idx,1,[K_total*K_total,1],@sum,0),[K_total K_total]);

Total_State_Voxels = zeros(TRs,Subjects,K_total,'uint32');
for k=1:K_total, Total_State_Voxels(:,:,k)=squeeze(sum(S3==k,2)); end
Percent_Striatum_in_State = 100*double(Total_State_Voxels)/Striatal_Voxels;

AverageDuration_inTRs_subject = nan(K_total,Subjects);
for k=1:K_total
    Mk = (S3==k);
    prev = cat(1,false(1,Striatal_Voxels,Subjects), Mk(1:end-1,:,:));
    run_starts = Mk & ~prev;
    frames_by_subj = squeeze(sum(sum(Mk,1),2));
    runs_by_subj   = squeeze(sum(sum(run_starts,1),2));
    denom = runs_by_subj(:); denom(denom==0)=NaN;
    AverageDuration_inTRs_subject(k,:) = (frames_by_subj(:)./denom).';
end
AverageDuration_inTRs_Mean = mean(AverageDuration_inTRs_subject,2,'omitnan');
AverageDuration_inTRs_SE   = std(AverageDuration_inTRs_subject,0,2,'omitnan')/sqrt(Subjects);

% k-of-5 dwell on bursts
PC3 = reshape(pass_count, TRs, Striatal_Voxels, Subjects);
IB3 = reshape(is_burst,   TRs, Striatal_Voxels, Subjects);
SubjectDwell_BurstK = nan(Subjects,5);
for s=1:Subjects
    Mk_burst = IB3(:,:,s);
    for k=1:5
        Mk_k = Mk_burst & (PC3(:,:,s)==k);
        if any(Mk_k(:))
            prev = cat(1,false(1,Striatal_Voxels),Mk_k(1:end-1,:));
            run_starts = Mk_k & ~prev;
            frames = sum(Mk_k(:)); runs = sum(run_starts(:));
            SubjectDwell_BurstK(s,k) = frames/runs;
        end
    end
end

% Subject transition probabilities
TransProb_subject = nan(Subjects,K_total,K_total);
for s=1:Subjects
    As = double(S3(1:end-1,:,s)); Bs=double(S3(2:end,:,s));
    idxs=sub2ind([K_total K_total],As(:),Bs(:));
    C=reshape(accumarray(idxs,1,[K_total*K_total,1],@sum,0),[K_total K_total]);
    rs=sum(C,2); TransProb_subject(s,:,:) = C./max(rs,1);
end

% Subject-level percents & ratios & avg k on bursts
SubjectPercent_RestStates    = nan(Subjects,max(3,K_rest));
SubjectPercent_BurstTotal    = nan(Subjects,1);
SubjectPercent_Burst_k       = nan(Subjects,5);
Rest3_to_Rest1_Ratio_Subject = nan(Subjects,1);
SubjectAvgK_onBursts         = nan(Subjects,1);
for s=1:Subjects
    idx  = (s-1)*TRs*Striatal_Voxels + (1:TRs*Striatal_Voxels);
    labs = class_All(idx); pc=pass_count(idx); ib=is_burst(idx);
    for r=1:K_rest, SubjectPercent_RestStates(s,r)=100*mean(labs==r); end
    SubjectPercent_BurstTotal(s)=100*mean(ib);
    for k=1:5, SubjectPercent_Burst_k(s,k)=100*mean(ib & (pc==k)); end
    if any(ib), SubjectAvgK_onBursts(s)=mean(double(pc(ib))); end
    if K_rest>=3
        a=mean(labs==3); b=mean(labs==1); if b>0, Rest3_to_Rest1_Ratio_Subject(s)=a/b; end
    end
end

% Group timecourses
Group_Timecourse_Percent_State_Mean = squeeze(mean(Percent_Striatum_in_State,2,'omitnan'));
Group_Timecourse_Percent_State_SE   = squeeze(std( Percent_Striatum_in_State,0,2,'omitnan'))/sqrt(Subjects);

% Jaccard stability
Jaccard_MeanPerVoxel = mean(Jaccard_Subject,2,'omitnan');
Jaccard_SDPerVoxel   = std(Jaccard_Subject,0,2,'omitnan');
Jaccard_SEPerVoxel   = Jaccard_SDPerVoxel/sqrt(Subjects);

% Voxel input combo tracking (optional heavy exports)
PM4 = reshape(pass_mask, TRs, Striatal_Voxels, Subjects, Target_Cortical_ROIs);
VoxelInputBurstCounts = zeros(Striatal_Voxels, Subjects, 5,'uint32');
for s=1:Subjects
    IB_s = IB3(:,:,s); PM_s=squeeze(PM4(:,:,s,:));
    counts5 = squeeze(sum(PM_s & repmat(IB_s,1,1,5),1)); % Vox x 5
    VoxelInputBurstCounts(:,s,:) = uint32(counts5);
end
VoxelComboCounts_Subject = zeros(Striatal_Voxels, Subjects,31,'uint32');
bitw = uint8(reshape(2.^(0:4),1,1,5));
for s=1:Subjects
    IB_s=IB3(:,:,s); PM_s=squeeze(PM4(:,:,s,:));
    code = uint8(sum(uint8(PM_s).*bitw,3)); code(~IB_s)=0; % 0..31
    idx=find(code>0);
    if ~isempty(idx)
        [~,v_idx]=ind2sub(size(code),idx);
        counts=accumarray([v_idx(:), double(code(idx))],1,[Striatal_Voxels 31],@sum,0);
        VoxelComboCounts_Subject(:,s,:)=uint32(counts);
    end
end
VoxelComboCounts_AllSubjects = squeeze(sum(VoxelComboCounts_Subject, 2));
TotalBurstFrames_perVoxel = squeeze(sum(sum(IB3, 1), 3));
den = double(TotalBurstFrames_perVoxel(:)); den(den==0) = NaN;
VoxelComboPct_AllSubjects = (double(VoxelComboCounts_AllSubjects) ./ den) * 100;

% k-of-5 composition among bursts (for CSV)
pc_burst = double(pass_count(is_burst));
Kof5_burst_counts = accumarray(pc_burst+1,1,[6 1],@sum,0)'; % 0..5 -> 1..6
Kof5_burst_counts = Kof5_burst_counts(2:6); % keep 1..5
den_burst = max(sum(Kof5_burst_counts),1);
Kof5_burst_pct = 100*(Kof5_burst_counts/den_burst);

ExportPaths = do_exports_and_plots();

% Summary struct
row_sums = sum(Transitions,2); TransProb = Transitions./max(row_sums,1);
stateNames = [arrayfun(@(k)sprintf('Rest %d',k),1:K_rest,'UniformOutput',false), {'Burst'}];
StateSummary = repmat(struct('name',[],'global_occupancy_pct',[],'subject_mean_occupancy_pct',[],...
    'subject_se_occupancy_pct',[],'avg_cp_profile',[],'avg_dwell_trs_mean',[],...
    'avg_dwell_trs_se',[],'transition_prob_row',[]), K_rest+1,1);
for k=1:K_rest+1
    StateSummary(k).name = stateNames{k};
    StateSummary(k).global_occupancy_pct       = TRs_in_CP_State_Global(k);
    StateSummary(k).subject_mean_occupancy_pct = TRs_in_CP_State_SubjectMean(k);
    StateSummary(k).subject_se_occupancy_pct   = TRs_in_CP_State_SubjectSE(k);
    StateSummary(k).avg_cp_profile             = Avg_CP_State(k,:);
    StateSummary(k).avg_dwell_trs_mean         = AverageDuration_inTRs_Mean(k);
    StateSummary(k).avg_dwell_trs_se           = AverageDuration_inTRs_SE(k);
    StateSummary(k).transition_prob_row        = TransProb(k,:);
end

fprintf('\n=== BURST DETECTION SUMMARY ===\n');
fprintf('Dataset type: %s | Burst frames: %d (%.2f%%)\n', dataset_type, sum(is_burst), burst_fraction);
if any(~isnan(SubjectAvgPos5_onBursts_raw)), fprintf('Mean of positive inputs on bursts (raw): mean=%.4f\n', mean(SubjectAvgPos5_onBursts_raw,'omitnan')); end
fprintf('================================\n\n');

% Save / return
if save_outputs
    results_out = struct( ...
        'dataset_type',dataset_type,'mu_for_z',mu_for_z,'sigma_for_z',sigma_for_z,'tau_vec',tau_vec,'tau_mean',tau_mean, ...
        'burst_detector',burst.detector,'K_rest',K_rest,'centroids_z',exist_var('centroids_z'), ...
        'class_All',class_All,'burst_label',uint16(K_rest+1), ...
        'Avg_CP_State',Avg_CP_State,'TRs_in_CP_State_Global',TRs_in_CP_State_Global, ...
        'TRs_in_CP_State_SubjectMean',TRs_in_CP_State_SubjectMean, ...
        'TRs_in_CP_State_SubjectSE',TRs_in_CP_State_SubjectSE, ...
        'Transitions',Transitions,'TransProb',TransProb, ...
        'Total_State_Voxels',Total_State_Voxels,'Percent_Striatum_in_State',Percent_Striatum_in_State, ...
        'AverageDuration_inTRs_subject',AverageDuration_inTRs_subject, ...
        'AverageDuration_inTRs_Mean',AverageDuration_inTRs_Mean,'AverageDuration_inTRs_SE',AverageDuration_inTRs_SE, ...
        'pass_count',pass_count,'is_burst',is_burst,'Kof5_burst_counts',Kof5_burst_counts, 'Kof5_burst_pct',Kof5_burst_pct, ...
        'SubjectPercent_RestStates',SubjectPercent_RestStates(:,1:K_rest), ...
        'SubjectPercent_BurstTotal',SubjectPercent_BurstTotal,'SubjectPercent_Burst_k',SubjectPercent_Burst_k, ...
        'SubjectAvgK_onBursts',SubjectAvgK_onBursts,'SubjectDwell_BurstK',SubjectDwell_BurstK, ...
        'TransProb_subject',TransProb_subject, ...
        'StriatalBOLD_Mean_TS',StriatalBOLD_Mean_TS, ...
        'Group_Timecourse_Percent_State_Mean',Group_Timecourse_Percent_State_Mean, ...
        'Group_Timecourse_Percent_State_SE',Group_Timecourse_Percent_State_SE, ...
        'FixedTop5Idx',FixedTop5Idx,'FixedTop5_ROIid',FixedTop5_ROIid, ...
        'Top5_ROIid_Subject',Top5_ROIid_Subject,'Jaccard_Subject',Jaccard_Subject, ...
        'Jaccard_MeanPerVoxel',Jaccard_MeanPerVoxel,'VoxelInputBurstCounts',VoxelInputBurstCounts, ...
        'VoxelComboCounts_Subject',VoxelComboCounts_Subject,'VoxelComboCounts_AllSubjects',VoxelComboCounts_AllSubjects, ...
        'VoxelComboPct_AllSubjects',VoxelComboPct_AllSubjects,'TotalBurstFrames_perVoxel',TotalBurstFrames_perVoxel, ...
        'SubjectAvgPos5_onBursts_raw', SubjectAvgPos5_onBursts_raw, ...
        'SubjectAvgPos5_onBursts_z',   SubjectAvgPos5_onBursts_z, ...
        'SubjectBurstFrameCount',      SubjectBurstFrameCount, ...
        'ExportPaths',ExportPaths,'StateSummary',StateSummary, ...
        'apply_standardization',apply_standardization);
    save(save_path,'-struct','results_out','-v7.3');
    results = results_out;
else
    results = struct('dataset_type',dataset_type,'K_rest',K_rest,'StateSummary',StateSummary,'ExportPaths',ExportPaths, ...
                     'burst_fraction',burst_fraction,'burst_detector',burst.detector,'apply_standardization',apply_standardization);
end
assignin('base','results',results);

%% ========================= Nested helpers ==============================
    function v = exist_var(name)
        if exist(name,'var'), v = eval(name); else, v=[]; end
    end
    function X = standardize_cp(CP, mu, sigma)
        X = (CP - mu) ./ sigma; X(:, sigma==0) = 0;
    end
    function tau = mixture_threshold_1d_fast(s, maxiter, Nsub)
        s = s(:); s = s(~isnan(s) & ~isinf(s));
        if isempty(s) || all(s==0), tau = 0; return; end
        if numel(s)>Nsub, rng(42); s = s(randsample(numel(s),Nsub)); end
        q25 = quantile(s,0.25); q75=quantile(s,0.75);
        if q25==q75
            mu=mean(s); sd=std(s); if sd==0, tau=max(mu,0); return; end
            c0=[mu-sd; mu+sd];
        else
            c0=[q25; q75];
        end
        try, opts=statset('MaxIter',maxiter,'Display','off'); [lbl, ctr] = kmeans(s,2,'Start',c0,'MaxIter',maxiter,'Options',opts);
        catch, [lbl, ctr] = kmeans(s,2,'Start',c0,'MaxIter',maxiter);
        end
        if numel(unique(lbl))<2
            t0=mean(c0); left=s(s<=t0); right=s(s>t0);
            m1=mean(left); m2=mean(right);
            if isnan(m1)||isnan(m2)||m1==m2, tau=max(t0,0); return; end
            s1=std(left); if ~isfinite(s1)||s1==0, s1=eps; end
            s2=std(right);if ~isfinite(s2)||s2==0, s2=eps; end
            w1=numel(left)/numel(s); w2=1-w1; w1=max(w1,eps); w2=max(w2,eps);
        else
            m1=min(ctr); m2=max(ctr);
            i1=find(ctr==m1,1); i2=find(ctr==m2,1);
            s1=std(s(lbl==i1)); if ~isfinite(s1)||s1==0, s1=eps; end
            s2=std(s(lbl==i2)); if ~isfinite(s2)||s2==0, s2=eps; end
            w1=mean(lbl==i1); w2=1-w1; w1=max(w1,eps); w2=max(w2,eps);
        end
        A = (1/(2*s1^2)) - (1/(2*s2^2));
        B = (-m1/(s1^2)) + (m2/(s2^2));
        C = (m1^2)/(2*s1^2) - (m2^2)/(2*s2^2) - log((s2*w1)/(s1*w2));
        if abs(A)<1e-12
            x_star = -C/B;
        else
            disc = B^2 - 4*A*C;
            if disc<0
                x_star = (m1+m2)/2;
            else
                r1 = (-B - sqrt(disc))/(2*A);
                r2 = (-B + sqrt(disc))/(2*A);
                rr = sort([r1 r2]); lo=min(m1,m2); hi=max(m1,m2);
                if rr(1)>=lo && rr(1)<=hi, x_star=rr(1);
                elseif rr(2)>=lo && rr(2)<=hi, x_star=rr(2);
                else, x_star=(m1+m2)/2;
                end
            end
        end
        tau = max(x_star,0);
    end
    function X = build_dbscan_features(CPz, space, posabs_mode)
        switch lower(posabs_mode), case 'all_abs', base = abs(CPz); otherwise, base = max(CPz,0); end
        switch lower(space)
            case 'inputs', X = base;
            case 'm5',     X = mean(base,2);
            case 'l2',     X = sqrt(mean(base.^2,2));
            otherwise,     error('Unknown dbs.feature_space: %s', space);
        end
        if size(X,2)==1, X = X(:); end
    end
    function [eps_use, minpts_use] = dbscan_choose_auto(X, dbs)
        N = size(X,1); fit_n = min(dbs.fit_cap, N);
        fitIdx = randsample(N, fit_n); Xfit = X(fitIdx,:);
        Kmax = min(max(dbs.auto.minpts_range), max(3, size(Xfit,1)-1));
        if Kmax < 3, eps_use = 0; minpts_use = 3; return; end
        fprintf('  [auto] k-NN up to K=%d on %d points...\n', Kmax, size(Xfit,1));
        [~, Dk] = knnsearch(Xfit, Xfit, 'K', Kmax+1, 'NSMethod','kdtree'); kD = Dk(:,2:end);
        k_coarse_all = 10:5:40; k_coarse = intersect(k_coarse_all, 1:Kmax); k_coarse = k_coarse(k_coarse>=3);
        if isempty(k_coarse), k_coarse = min(Kmax, max(3, dbs.auto.minpts_range)); end
        best = struct('score',-Inf,'k',[],'eps',[]);
        fprintf('  [auto] coarse MinPts trials: %s\n', mat2str(k_coarse));
        for kc = k_coarse
            eps_c = knee_eps(kD(:,kc), dbs.auto.knee_frac);
            [idx_c,~] = call_dbscan(Xfit, eps_c, kc);
            sc = score_dbscan(idx_c);
            fprintf('    coarse k=%d → eps=%.4f | score=%.4f\n', kc, eps_c, sc);
            if sc > best.score, best = struct('score',sc,'k',kc,'eps',eps_c); end
        end
        k_ref = best.k-2:best.k+2; k_ref = intersect(k_ref, 1:Kmax); k_ref = k_ref(k_ref>=3);
        fprintf('  [auto] refine around k=%d with: %s\n', best.k, mat2str(k_ref));
        for k = k_ref
            eps_k = knee_eps(kD(:,k), dbs.auto.knee_frac);
            [idx_k,~] = call_dbscan(Xfit, eps_k, k);
            sc = score_dbscan(idx_k);
            fprintf('    refine k=%d → eps=%.4f | score=%.4f\n', k, eps_k, sc);
            if sc > best.score, best = struct('score',sc,'k',k,'eps',eps_k); end
        end
        eps_use    = best.eps; minpts_use = best.k;
    end
    function eps = knee_eps(kdist_vec, knee_frac)
        kd = sort(kdist_vec(:),'ascend'); q  = 1 - knee_frac;
        eps = kd( max(1, min(numel(kd), round(q*numel(kd)))) ); if eps<=0, eps = kd(end); end
    end
    function sc = score_dbscan(idx)
        labs = idx(:); is_noise = (labs==-1); unl = unique(labs(~is_noise));
        if isempty(unl), sc = -Inf; return; end
        penalty = (numel(unl)>1);
        counts = arrayfun(@(u)sum(labs==u), unl);
        rest_frac = max(counts)/numel(labs);
        sc = rest_frac - 0.25*penalty;
    end
    function [idx, corepts] = call_dbscan(X, eps, minpts)
        dbf = str2func('dbscan');
        try, [idx, corepts] = dbf(X, eps, minpts, 'Distance','euclidean');
        catch, idx = dbf(X, eps, minpts, 'Distance','euclidean'); corepts = [];
        end
    end
    function is_burst = dbscan_classify_all(X, eps_use, minpts_use, dbs)
        N = size(X,1); run_n = min(dbs.run_cap, N);
        runIdx = randsample(N, run_n); Xrun = X(runIdx,:);
        [idx_run,~] = call_dbscan(Xrun, eps_use, minpts_use);
        labs = idx_run(:); unl = unique(labs(labs~=-1));
        if isempty(unl), is_burst = true(N,1); return; end
        counts = arrayfun(@(u)sum(labs==u), unl);
        [~,ixmax] = max(counts); rest_label = unl(ixmax);
        rest_run_mask = (labs==rest_label);
        Xrest = Xrun(rest_run_mask,:); if isempty(Xrest), is_burst = true(N,1); return; end
        K = minpts_use;
        is_burst = true(N,1);
        is_burst(runIdx(rest_run_mask)) = false;
        remain = true(N,1); remain(runIdx) = false; remIdx = find(remain);
        batch = dbs.assign_batch; start = 1;
        while start <= numel(remIdx)
            stop = min(numel(remIdx), start+batch-1); sub = remIdx(start:stop); Xq = X(sub,:);
            [~, Dq] = knnsearch(Xrest, Xq, 'K', K, 'NSMethod','kdtree');
            kth = Dq(:, end); is_rest_here = kth <= eps_use;
            is_burst(sub) = ~is_rest_here; start = stop + 1;
        end
    end
    function M_out = canonicalize_by_signed_mean_ascending(M_in, Rz)
        K = double(max(M_in)); frame_mean = mean(Rz,2);
        avg_by_cluster = accumarray(double(M_in), frame_mean, [K 1], @mean, 0);
        [~,ord] = sort(avg_by_cluster,'ascend'); map=zeros(K,1); map(ord)=1:K;
        M_out = uint32(map(double(M_in)));
    end
    function assigned = assign_by_cosine(Rz, centroids_z)
        c_norms = sqrt(sum(centroids_z.^2,2))'; c_norms(c_norms==0)=1;
        r_norms = sqrt(sum(Rz.^2,2));           r_norms(r_norms==0)=1;
        S = (Rz*centroids_z')./r_norms./c_norms; [~,assigned]=max(S,[],2);
    end
    function S = merge_structs(S,T)
        f=fieldnames(T); for ii=1:numel(f), S.(f{ii})=T.(f{ii}); end
    end
    function x = clamp_round(x, lo, hi), x = round(x); x = max(lo, min(hi, x)); end
    function out = tern(cond, a, b), if cond, out=a; else, out=b; end, end
    function ExportPaths = do_exports_and_plots()
        ExportPaths = struct();
        if export.enable_csv || export.enable_plots
            if ~exist(export.dir,'dir'), mkdir(export.dir); end
        end
        if export.enable_plots
            figs_dir = fullfile(export.dir,'figs'); if ~exist(figs_dir,'dir'), mkdir(figs_dir); end
        end
        % Subject metrics table (+ transitions)
        if export.enable_csv
            subjID = arrayfun(@(s)sprintf('Subj%03d',s),(1:Subjects)','UniformOutput',false);
            T_subj = table(subjID,'VariableNames',{'Subject'});
            for r=1:K_rest, T_subj.(sprintf('Rest%d_pct',r)) = SubjectPercent_RestStates(:,r); end
            T_subj.Burst_total_pct = SubjectPercent_BurstTotal;
            for k=1:5, T_subj.(sprintf('Burst_k%d_pct',k)) = SubjectPercent_Burst_k(:,k); end
            T_subj.Burst_avg_k_on_bursts = SubjectAvgK_onBursts;
            for r=1:K_rest, T_subj.(sprintf('Rest%d_dwell_TRs',r)) = AverageDuration_inTRs_subject(r,:)'; end
            T_subj.Burst_dwell_TRs = AverageDuration_inTRs_subject(K_rest+1,:)';
            for k=1:5, T_subj.(sprintf('Burst_k%d_dwell_TRs',k)) = SubjectDwell_BurstK(:,k); end
            if K_rest>=3, T_subj.Rest3_to_Rest1_Ratio = Rest3_to_Rest1_Ratio_Subject; end
            % NEW columns: positive-input mean on burst TRs
            T_subj.Burst_avgPos5_input_raw = SubjectAvgPos5_onBursts_raw;
            T_subj.Burst_avgPos5_input_z   = SubjectAvgPos5_onBursts_z;
            T_subj.Burst_nBurstFrames      = SubjectBurstFrameCount;
            % State transition probs
            stateShort = [arrayfun(@(k)sprintf('Rest%d',k),1:K_rest,'UniformOutput',false), {'Burst'}];
            for i=1:K_total, for j=1:K_total
                colName = sprintf('Tprob_%s_to_%s', stateShort{i}, stateShort{j});
                T_subj.(colName) = squeeze(TransProb_subject(:,i,j));
            end, end
            p_csv = fullfile(export.dir,'subject_metrics.csv'); writetable(T_subj,p_csv);
            ExportPaths.subject_metrics = p_csv;

            % subject BOLD mean TS
            T_bold = array2table(StriatalBOLD_Mean_TS,'VariableNames', matlab.lang.makeValidName(subjID));
            T_bold = addvars(T_bold,(1:TRs)','Before',1,'NewVariableNames','TR');
            p_csv2 = fullfile(export.dir,'subject_bold_mean_timeseries.csv'); writetable(T_bold,p_csv2);
            ExportPaths.subject_bold_mean_timeseries = p_csv2;

            % group timecourses mean±SE
            varNames=cell(1,2*(K_rest+1));
            for k=1:(K_rest+1)
                nm = tern(k<=K_rest, sprintf('Rest%d',k), 'Burst');
                varNames{2*k-1}=sprintf('%s_mean',nm); varNames{2*k}=sprintf('%s_se',nm);
            end
            M=zeros(TRs,2*(K_rest+1));
            for k=1:(K_rest+1)
                M(:,2*k-1)=Group_Timecourse_Percent_State_Mean(:,k);
                M(:,2*k)  =Group_Timecourse_Percent_State_SE(:,k);
            end
            T_group=array2table(M,'VariableNames',varNames);
            T_group=addvars(T_group,(1:TRs)','Before',1,'NewVariableNames','TR');
            p_csv3=fullfile(export.dir,'group_timecourses_state_pct.csv'); writetable(T_group,p_csv3);
            ExportPaths.group_timecourses_state_pct = p_csv3;

            % burst k composition among bursts
            T_burst = table((1:5)', Kof5_burst_counts', Kof5_burst_pct','VariableNames',{'k_of_5','count','percent_of_bursts'});
            p_csv4 = fullfile(export.dir,'burst_k_composition_among_bursts.csv'); writetable(T_burst,p_csv4);
            ExportPaths.burst_k_composition_among_bursts = p_csv4;

            % tau thresholds
            T_tau = table((1:size(CPz_for_fit,2))', tau_vec','VariableNames',{'input_dim','tau_threshold_z'});
            p_csv5=fullfile(export.dir,'tau_vec_thresholds.csv'); writetable(T_tau,p_csv5);
            ExportPaths.tau_vec_thresholds = p_csv5;
            T_tau_mean = table(tau_mean,'VariableNames',{'tau_mean_z'});
            p_csv6=fullfile(export.dir,'tau_mean_threshold.csv'); writetable(T_tau_mean,p_csv6);
            ExportPaths.tau_mean_threshold = p_csv6;

            % Jaccard stability per voxel (+ fixed ROI IDs)
            T_jac = table((1:Striatal_Voxels)', Jaccard_MeanPerVoxel, Jaccard_SDPerVoxel, Jaccard_SEPerVoxel, ...
                'VariableNames',{'Voxel','Jaccard_mean','Jaccard_sd','Jaccard_se'});
            for d=1:Target_Cortical_ROIs
                T_jac.(sprintf('FixedROI_%d',d)) = double(FixedTop5_ROIid(:,d));
            end
            p_csv7=fullfile(export.dir,'voxel_top5_jaccard_stability.csv'); writetable(T_jac,p_csv7);
            ExportPaths.voxel_top5_jaccard_stability = p_csv7;

            % voxel combo counts across all subjects
            if export.voxel_combo_group_csv
                rows = Striatal_Voxels*31;
                Voxel=zeros(rows,1,'uint32'); Mask=zeros(rows,1,'uint16');
                Count=zeros(rows,1,'uint32'); Pct=zeros(rows,1); Combo=strings(rows,1);
                ptr=0;
                for v=1:Striatal_Voxels
                    roi5=double(FixedTop5_ROIid(v,:));
                    labels31 = combo_labels_from_roiids(roi5);
                    for m=1:31
                        ptr=ptr+1; Voxel(ptr)=v; Mask(ptr)=m;
                        Count(ptr)=VoxelComboCounts_AllSubjects(v,m);
                        Pct(ptr)=VoxelComboPct_AllSubjects(v,m);
                        Combo(ptr)=labels31{m};
                    end
                end
                Voxel=Voxel(1:ptr); Mask=Mask(1:ptr); Count=Count(1:ptr); Pct=Pct(1:ptr); Combo=Combo(1:ptr);
                T_combo = table(Voxel,Mask,Combo,Count,Pct,'VariableNames',{'Voxel','ComboMask','ComboLabel','Count','PercentOfBurstFrames'});
                p_csv8=fullfile(export.dir,'voxel_combo_counts_all_subjects.csv'); writetable(T_combo,p_csv8);
                ExportPaths.voxel_combo_counts_all_subjects=p_csv8;
            end
        end
        if export.enable_plots
            figs_dir = fullfile(export.dir,'figs'); if ~exist(figs_dir,'dir'), mkdir(figs_dir); end
            f=figure('Color','w','Position',[100 100 1000 500]); hold on
            t=(1:TRs)'; cols=lines(K_rest+1);
            for k=1:(K_rest+1)
                mu=Group_Timecourse_Percent_State_Mean(:,k); se=Group_Timecourse_Percent_State_SE(:,k);
                fill([t;flipud(t)],[mu-se;flipud(mu+se)],cols(k,:),'FaceAlpha',0.12,'EdgeColor','none'); plot(t,mu,'Color',cols(k,:),'LineWidth',1.8);
            end
            leg=cell(1,K_rest+1); for k=1:K_rest, leg{k}=sprintf('Rest %d',k); end; leg{K_rest+1}='Burst';
            legend(leg,'Location','bestoutside'); xlabel('TR'); ylabel('% voxels'); title('Group timecourses (mean \pm SE)');
            grid on; box off; p1=fullfile(figs_dir,'group_timecourse_pct.png'); exportgraphics(f,p1, 'Resolution',200); close(f);
            ExportPaths.group_timecourse_pct = p1;

            f2=figure('Color','w','Position',[200 200 550 420]); bar(1:5,Kof5_burst_pct,'FaceAlpha',0.85);
            xlabel('k of 5 inputs ≥ per-input thresholds'); ylabel('% of burst TRs');
            title('Burst composition'); grid on; box off; p2=fullfile(figs_dir,'burst_k_composition.png'); exportgraphics(f2,p2,'Resolution',200); close(f2);
            ExportPaths.burst_k_composition = p2;
        end
    end
    function labels31 = combo_labels_from_roiids(roi5)
        roi5 = roi5(:).'; labels31 = cell(31,1);
        for m=1:31
            bits = logical(bitget(m,1:5)); ids = sort(double(roi5(bits)));
            labels31{m} = strjoin(string(ids),'+');
        end
    end
end % ===== end main function =====
