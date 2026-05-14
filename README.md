# Striatal State Dynamics in Human fMRI

MATLAB pipeline for identifying voxelwise corticostriatal coactivation states in HCP-YA fMRI, exporting subject/run-level summary metrics, and testing rest-task and task-period effects.

## What this repository contains

This public-facing code release consolidates the current project pipeline into four parts:

1. **State identification and metric extraction**
   - `matlab/core/Corticostriatal_Temporal_Dynamics_Final_All.m`
2. **Task-period state occupancy analyses**
   - `matlab/analysis/compare_rest_vs_task_period_states.m`
   - `matlab/analysis/compare_rest_vs_task_interblock_states.m`
3. **Pooled rest-vs-task metric comparisons**
   - `matlab/analysis/rest_vs_task_statistical_comparison_avgedRest.m`
4. **Arousal/task decomposition and residualized behavioral models**
   - `matlab/analysis/disentangle_burst_person_vs_arousal_all6.m`
   - `matlab/analysis/analyze_residualized_neural_predictors_all6.m`
5. **Documentation and configuration templates**
   - `matlab/config/path_config_template.m`
   - `docs/pipeline_overview.md`
   - `docs/reproducibility_checklist.md`

## Conceptual overview

The pipeline treats each striatal voxel's BOLD time series in the context of its five dominant frontal cortical inputs. For every frame-voxel instance, it computes a 5-dimensional corticostriatal coactivation vector, identifies high-amplitude "burst" frames using a reference thresholding scheme, clusters non-burst frames into recurrent resting coactivation states, and applies the resulting state definitions across all runs in a common reference space.

The main public outputs are:
- voxelwise/framewise state labels (`class_All`)
- subject-level state occupancy, dwell, and transition metrics
- burst composition/amplitude metrics
- run-level CSV and MAT exports used for the figures and statistics in the manuscript

## Recommended repository structure

```text
striatal-state-dynamics-pipeline/
├── README.md
├── .gitignore
├── matlab/
│   ├── core/
│   │   └── Corticostriatal_Temporal_Dynamics_Final_All.m
│   ├── analysis/
│   │   ├── compare_rest_vs_task_period_states.m
│   │   ├── compare_rest_vs_task_interblock_states.m
│   │   ├── rest_vs_task_statistical_comparison_avgedRest.m
│   │   ├── disentangle_burst_person_vs_arousal_all6.m
│   │   └── analyze_residualized_neural_predictors_all6.m
│   └── config/
│       ├── path_config_template.m
│       └── run_pipeline_example.m
├── docs/
│   ├── pipeline_overview.md
│   ├── reproducibility_checklist.md
│   └── methods_and_notes_source.txt
├── examples/
│   └── figure_generation_notes.md
└── assets/
    └── .gitkeep
```

## Inputs expected by the pipeline

### Neuroimaging inputs
- HCP-YA minimally preprocessed fMRI time series
- denoised striatal CSVs for each run
- denoised cortical CSVs for each run
- right striatal mask (`DiscoveryReplication_rStriatum_Intersect_Tightened.nii.gz`)
- Schaefer-100 frontal parcel time series restricted to the 21 right frontal parcels used in the project

### External timing files
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

### Step 2. Run the main state-identification script separately for each acquisition
Typical acquisitions:
- `REST1_LR`
- `REST1_RL`
- `REST2_LR`
- `REST2_RL`
- `GAMBLING_LR`
- `GAMBLING_RL`

Populate the corresponding `cfg.runs.<RUN_NAME>` entry in `user_paths.m`, then run:

```matlab
results = Corticostriatal_Temporal_Dynamics_Final_All([], GAMBLING_RL);
```

or, with an explicit config struct/function handle:

```matlab
cfg = user_paths();
results = Corticostriatal_Temporal_Dynamics_Final_All(cfg, REST1_LR);
```

This writes the run-level `.mat` results file (typically `efc_states_louvain_all_detectors.mat`) plus optional CSV, plot, and NIfTI exports.

### Step 3. Run summary analyses
After all acquisitions have been processed:

```matlab
results = compare_rest_vs_task_interblock_states();
results = compare_rest_vs_task_period_states();
results = rest_vs_task_statistical_comparison_avgedRest();
results = disentangle_burst_person_vs_arousal_all6();
regression_results = analyze_residualized_neural_predictors_all6();
```

Each analysis script will load `user_paths.m` automatically if no config is supplied.

These scripts generate the rest-vs-task and task-epoch summary tables used in the manuscript.

## Suggested GitHub release language for the paper

> Code used to identify corticostriatal coactivation states and reproduce the primary state-dynamic analyses is available at: **[insert GitHub URL]**.

If you want a stronger reproducibility statement:

> A curated MATLAB implementation of the corticostriatal coactivation-state pipeline, including run-level state identification and downstream rest/task statistical analyses, is available at: **[insert GitHub URL]**.

## Current caveats

- Project paths and run-specific locations are now loaded from a local config (`user_paths.m`).
- Several helper toolboxes are expected to already exist on disk.
- The repository does **not** currently include raw HCP data, denoised time series, or derived result files.
- If you add derived timing or statistical scripts developed after the current draft, keep them in `matlab/analysis/` and document their provenance clearly.

## Minimal checklist before uploading to GitHub

- [ ] verify that your local `user_paths.m` is complete for all runs
- [ ] add a license
- [ ] add a short `CITATION.cff`
- [ ] verify that each script runs from a clean MATLAB session
- [ ] remove machine-specific user names and private directories
- [ ] confirm that external dependencies are listed in the README
- [ ] optionally add one small synthetic/example dataset or a dry-run example



## Standardized outputs
All scripts now write generated files beneath a single configurable output root. Set `cfg.output_root` in `user_paths.m` to control where analysis tables, exports, and run-level results are written.

Recommended structure:
- `outputs/results/<RUN_NAME>/efc_states_louvain_all_detectors.mat`
- `outputs/exports/<RUN_NAME>/efc_exports/`
- `outputs/rest_vs_task_period_states/`
- `outputs/rest_vs_task_interblock_states/`
- `outputs/rest_vs_task_comparison_all6/`
- `outputs/burst_person_vs_arousal_all6/`
- `outputs/residualized_neural_predictors_all6/`
