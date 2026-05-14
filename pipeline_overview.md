# Pipeline overview

## 1. Build voxelwise corticostriatal coactivation vectors
For every subject, voxel, and TR:
- z-score striatal and frontal time series within subject
- multiply striatal voxel signal by each frontal parcel signal
- retain the five dominant frontal inputs per voxel
- stack all frame-voxel instances into an `(subjects × TRs × voxels) × 5` matrix

## 2. Define a common reference space
Using REST1_LR as the reference run:
- estimate burst thresholds
- estimate rest-state centroids for non-burst frames
- store thresholds / centroids in a reusable template

## 3. Label states in each acquisition
For each run:
- identify burst frames
- assign non-burst frames to reference centroids by cosine similarity
- store `class_All` and subject-level summary metrics

## 4. Summarize subject-level state dynamics
Run-level outputs include:
- occupancy
- dwell time
- transition probabilities
- burst composition
- positive-input amplitude during burst frames
- mean striatal BOLD time series

## 5. Compare rest vs task and task periods
Analysis scripts summarize:
- pooled REST vs pooled GAMBLING
- inter-block vs rest
- reward vs loss vs inter-block
- blockwise and sequential task-epoch comparisons

