function out_dir = get_output_dir(cfg, analysis_name, make_dir)
%GET_OUTPUT_DIR Return a standardized output directory for an analysis.
%   out_dir = GET_OUTPUT_DIR(cfg, analysis_name)
%   out_dir = GET_OUTPUT_DIR(cfg, analysis_name, make_dir)
%
% Uses cfg.output_root when available; otherwise defaults to
% fullfile(cfg.project_root, ''outputs'').

if nargin < 3 || isempty(make_dir), make_dir = true; end

if isfield(cfg, 'output_root') && ~isempty(cfg.output_root)
    base_dir = cfg.output_root;
elseif isfield(cfg, 'project_root') && ~isempty(cfg.project_root)
    base_dir = fullfile(cfg.project_root, 'outputs');
else
    error('Config must define either cfg.output_root or cfg.project_root.');
end

out_dir = fullfile(base_dir, analysis_name);
if make_dir && ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
end
