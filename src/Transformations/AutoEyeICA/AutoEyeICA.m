function [EEG, opts] = AutoEyeICA(input, opts)
%% AutoEyeICA  ICA-decompose, classify with ICLabel, and prune eye components.
%
%   Runs ICA decomposition (pop_runica), classifies the resulting components
%   with ICLabel, and removes every component whose 'Eye' probability exceeds
%   a threshold (pop_subcomp) -- fully automatically, with no manual
%   component picking. Replaces the old two-step Decompose ICA + RemoveComp
%   pipeline (decompose-and-classify, then a separate manual pop_viewprops /
%   pop_subcomp pass).
%
%   Inputs:
%       input - EEG dataset to decompose and clean.
%       opts  - Struct with field EyeThreshold (0-1). If not provided, a
%               settings dialog prompts for it once; the chosen value is
%               returned so a later replay skips the dialog.
%
%   Outputs:
%       EEG   - Dataset with eye components subtracted. ICA weights and the
%               ICLabel classifications (EEG.etc.ic_classification) are kept.
%       opts  - Struct with the EyeThreshold used.

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:AutoEyeICA', 'Problem in AutoEyeICA: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end

if (ischar(opts) || isstring(opts)) && strcmpi(opts, 'Init')
    opts = uiextras.settingsdlg( ...
        'Description', 'Components with an ICLabel ''Eye'' probability above this threshold are removed.', ...
        'title', 'AutoEyeICA options', ...
        'separator', 'Eye component threshold:', ...
        {'Probability (0-1)'; 'EyeThreshold'}, 0.8);
end

EEG = input;
[~, name, ~] = fileparts(EEG.File);
EEG.id = name;

%% Decompose
%  Use FastICA automatically when it is installed, so the ICA-algorithm
%  dialog is skipped; otherwise fall back to pop_runica's own default
%  (and its dialog), unchanged from before.
if ~isempty(which('fastica'))
    EEG = pop_runica(EEG, 'icatype', 'fastica');
else
    EEG = pop_runica(EEG);
end

%% ICLabel needs scalp locations; auto-fill from a standard montage template
%  when none are set, rather than opening the interactive Channel Editor.
hasLocs = isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) ...
    && isfield(EEG.chanlocs, 'X') && ~all(cellfun(@isempty, {EEG.chanlocs.X}));
if ~hasLocs
    EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
end

%% Classify
EEG = iclabel(EEG, 'beta');

%% Prune every component ICLabel calls 'Eye' above the threshold
classes = EEG.etc.ic_classification.ICLabel.classes;
probs   = EEG.etc.ic_classification.ICLabel.classifications;
eyeCol  = find(strcmpi(classes, 'Eye'), 1);
if isempty(eyeCol)
    throw(MException('Alakazam:AutoEyeICA', ...
        'ICLabel did not return an ''Eye'' category; cannot prune.'));
end

eyeComps = find(probs(:, eyeCol) > opts.EyeThreshold);
fprintf('AutoEyeICA: pruned %d of %d component(s) as eye (threshold %.2f).\n', ...
    numel(eyeComps), size(probs, 1), opts.EyeThreshold);
if ~isempty(eyeComps)
    EEG = pop_subcomp(EEG, eyeComps, 0);
end
