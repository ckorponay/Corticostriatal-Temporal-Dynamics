#!/bin/tcsh -xef

#requires AFNI

set subjList = ()

foreach subj ($subjList)

3dmaskdump -noijk  -mask /path/to/Striatal_Mask.nii.gz /path/to/denoised/{$subj}_fMRI_4D.nii.gz > /path/to/{$subj}_fMRI_4D.1D

1dcat -csvout /path/to/{$subj}_fMRI_4D.1D > /path/to/{$subj}_fMRI_4D.csv

end
