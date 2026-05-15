# Striatal State Dynamics in Human fMRI

MATLAB pipeline for identifying voxel-wise, frame-wise (i.e., TR-wise) striatal coactivation states with frontal cortex in HCP-YA fMRI, exporting subject/run-level summary metrics, decomposing arousal-dependent and -independent effects, comparing dynamics across resting-state and task blocks, and analyzing relationships with behavioral phenotypes.

## What this repository contains

1. **Extraction and Organization of Striatal and Cortical BOLD Data**
   - `Extract_Striatal_BOLD.sh`
   - `Extract_Cortical_BOLD.sh`
2. **State Identification and Metric Extraction**
   - `matlab/core/Corticostriatal_Temporal_Dynamics_Final_All.m`
3. **Task Block and Resting-State Comparisons**
   - `matlab/analysis/compare_rest_vs_task_period_states_pooledAcrossRuns_plusSequent.m`
4. **Arousal/task decomposition and residualized behavioral models**
   - `matlab/analysis/disentangle_burst_person_vs_arousal_all6.m`
   - `matlab/analysis/analyze_residualized_neural_predictors_all6.m`
5. **Documentation and configuration templates**
   - `matlab/config/path_config_template.m`
   - `docs/pipeline_overview.md`

## Conceptual overview

The pipeline treats each striatal voxel's BOLD time series in the context of its five dominant frontal cortical inputs. For every frame-voxel instance, it computes a 5-dimensional corticostriatal coactivation vector, identifies high-amplitude "burst" frames using Gaussian mixture modeling, clusters non-burst frames into recurrent resting coactivation states using Louvain community detection, and applies the resulting state definitions across all runs in a common reference space.

The main outputs are:
- voxelwise/framewise state labels (`class_All`)
- subject-level state occupancy, dwell, and transition metrics
- burst composition/amplitude metrics
- run-level CSV and MAT exports

## Recommended repository structure

```text
Corticostriatal-Temporal-Dynamics/
├── README.md
├── .gitignore
├── matlab/
│   ├── pre_analysis/
│   │   ├── Extract_Striatal_BOLD.sh
│   │   └── Extract_Cortical_BOLD.sh
│   ├── core/
│   │   └── Corticostriatal_Temporal_Dynamics_Final_All.m
│   ├── analysis/
│   │   ├── compare_rest_vs_task_period_states_pooledAcrossRuns_plusSequentialByRun_plusTaskOnComparisons.m
│   │   ├── disentangle_burst_person_vs_arousal_all6.m
│   │   └── analyze_residualized_neural_predictors_all6.m
│   └── config/
│       ├── path_config_template.m
│       └── run_pipeline_example.m
└── docs/
    └── pipeline_overview.md
 
```

## Inputs expected by the pipeline

### Neuroimaging inputs
- CSVs of striatal voxel-wise, frame-wise BOLD signal magnitudes for each subject for each run from denoised fMRI data
- CSVs of cortical ROI-wise, frame-wise BOLD signal magnitudes for each subject for each run from denoised fMRI data
- Striatal Mask 
- Cortical Atlas

Extract_Striatal_BOLD.sh and Extract_Cortical_BOLD.sh generate the subject-level run-specific CSV inputs expected by the MATLAB pipeline. Their output locations should be set to match the corresponding paths configured in cfg.runs.<RUN_NAME> within user_paths.m

### Task timing files
- `win.txt`
- `loss.txt`
- `win_LR.txt`
- `loss_LR.txt`

### Spreadsheet / behavioral metadata
- subject-level spreadsheet with sLFO columns, demographics, and behavioral outcomes
- configured via `cfg.subject_vars_file` in `user_paths.m`

### External MATLAB dependencies
- eFC helper functions (`fcn` directory)
- NIfTI toolbox (`load_untouch_nii`, `save_untouch_nii`, etc.)
- Brain Connectivity Toolbox

## How to run the pipeline

### Step 1. Edit paths and acquisition-specific settings
Before running anything, duplicate `matlab/config/path_config_template.m` to `user_paths.m` and edit it for your local environment.

### Step 2. Run the BOLD extraction scripts in the terminal using AFNI
These will generate the subject-level run-specific CSV inputs expected by the MATLAB pipeline.

### Step 3. Run the main state-identification script separately for each acquisition
Typical acquisitions:
- `REST1_LR`
- `REST1_RL`
- `REST2_LR`
- `REST2_RL`
- `GAMBLING_LR`
- `GAMBLING_RL`

Populate the corresponding `cfg.runs.<RUN_NAME>` entry in `user_paths.m`, then run:

```matlab
results = Corticostriatal_Temporal_Dynamics_Final_All([], 'GAMBLING_RL');
```

or, with an explicit config struct/function handle:

```matlab
cfg = user_paths();
results = Corticostriatal_Temporal_Dynamics_Final_All(cfg, 'REST1_LR');
```

This writes the run-level `.mat` results file (typically `efc_states_louvain_all_detectors.mat`) plus optional CSV, plot, and NIfTI exports.

### Step 4. Run summary analyses
After all acquisitions have been processed:

```matlab
results = compare_rest_vs_task_period_states_pooledAcrossRuns_plusSequent();
results = disentangle_burst_person_vs_arousal_all6();
regression_results = analyze_residualized_neural_predictors_all6();
```

Each analysis script will load `user_paths.m` automatically if no config is supplied.

## Standardized outputs
All scripts write generated files beneath a single configurable output root. Set `cfg.output_root` in `user_paths.m` to control where analysis tables, exports, and run-level results are written.

Recommended structure:
- `outputs/results/<RUN_NAME>/efc_states_louvain_all_detectors.mat`
- `outputs/exports/<RUN_NAME>/efc_exports/`
- `outputs/rest_vs_task_period_states/`
- `outputs/burst_person_vs_arousal_all6/`
- `outputs/residualized_neural_predictors_all6/`
