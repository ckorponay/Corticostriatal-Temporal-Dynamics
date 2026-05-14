function cfg = load_project_config(cfg_input)
%LOAD_PROJECT_CONFIG Load config struct or function handle/file.
% Usage:
%   cfg = load_project_config();                % calls user_paths if available
%   cfg = load_project_config(cfg_struct);
%   cfg = load_project_config(@user_paths);
%   cfg = load_project_config('user_paths');
%
if nargin < 1 || isempty(cfg_input)
    if exist('user_paths','file') == 2
        cfg = user_paths();
    else
        error(['No configuration supplied and user_paths.m was not found. ' ...
               'Copy matlab/config/path_config_template.m to user_paths.m and edit it for your machine.']);
    end
elseif isstruct(cfg_input)
    cfg = cfg_input;
elseif isa(cfg_input, 'function_handle')
    cfg = cfg_input();
elseif ischar(cfg_input) || isstring(cfg_input)
    cfg = feval(char(cfg_input));
else
    error('Unsupported cfg_input type.');
end
end
