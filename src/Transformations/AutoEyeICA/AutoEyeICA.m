function [EEG, opts] = AutoEyeICA(input, varargin)
%% AutoEyeICA  ICA-decompose, classify with ICLabel, and prune eye components.
%
%   Runs ICA decomposition (pop_runica), classifies the resulting components
%   with ICLabel, and removes every component whose 'Eye' probability exceeds
%   a threshold (pop_subcomp) -- fully automatically, with no manual
%   component picking. Replaces the old two-step Decompose ICA + RemoveComp
%   pipeline (decompose-and-classify, then a separate manual pop_viewprops /
%   pop_subcomp pass).
%
%   ICA decomposition and ICLabel classification both need a real X/Y/Z
%   scalp position for every included channel (dipfit's standard 10-5
%   template, see Dipfit1005File). A channel the template does not
%   recognise -- most commonly an EOG or ECG channel, which has no scalp
%   position at all -- is excluded from decomposition entirely and spliced
%   back into its original slot, unmodified, once pruning is done: the same
%   pattern AutoGEDAI uses for its own leadfield-based channel eligibility.
%   Throws if *no* channel has a usable position.
%
%   Inputs:
%       input - EEG dataset to decompose and clean.
%       opts  - Struct with field EyeThreshold (0-1). If not provided, a
%               settings dialog prompts for it once; the chosen value is
%               returned so a later replay skips the dialog.
%
%   Outputs:
%       EEG   - Dataset with eye components subtracted. ICA weights and the
%               ICLabel classifications (EEG.etc.ic_classification) are kept,
%               scoped to the positioned channels that were actually
%               decomposed (see EEG.icachansind).
%       opts  - Struct with the EyeThreshold used.

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:AutoEyeICA', varargin{:});

if interactive
    stored = TransformSettings.get('AutoEyeICA');
    if isempty(stored)
        stored = struct('EyeThreshold', 0.8);
    end
    opts = TransformOptionsDialog( ...
        'Description', 'Components with an ICLabel ''Eye'' probability above this threshold are removed.', ...
        'title', 'AutoEyeICA options', ...
        'separator', 'Eye component threshold:', ...
        {'Probability (0-1)'; 'EyeThreshold'}, stored.EyeThreshold);
    if isempty(opts)
        % Cancelled: nothing to persist (leave the remembered settings
        % untouched) and nothing to run -- Alakazam.onTransformation
        % treats an empty EEG as "cancelled", not an error.
        EEG = [];
        return;
    end
    TransformSettings.set('AutoEyeICA', opts);
end

EEG = input;
[~, name, ~] = fileparts(EEG.File);
EEG.id = name;

%% ICA and ICLabel need a real X/Y/Z scalp position for every included
%  channel, from dipfit's standard 10-5 (343-electrode) template. A
%  channel the template does not recognise (e.g. EOG, ECG) is excluded
%  from decomposition entirely and spliced back into its original slot,
%  unmodified, once pruning is done -- see AutoGEDAI for the same pattern.
EEG = TransTools.FillChanlocs(EEG, 'Alakazam:AutoEyeICA', ...
    TransTools.Dipfit1005File('Alakazam:AutoEyeICA'));
% Eligible = has a scalp position AND is not a peripheral (EOG/ECG/...). EOG
% electrodes often carry real coordinates beside the eyes, so they pass hasPos
% and, if decomposed, dominate the ICA and plot outside the head; exclude them
% by type (guessed from the label, so pre-positioned untyped data works too).
EEG.chanlocs = guessChannelTypes(EEG.chanlocs);
hasPos   = arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), EEG.chanlocs);
eligible = hasPos & eegChannelMask(EEG.chanlocs);
eegIdx   = find(eligible);
otherIdx = find(~eligible);

if isempty(eegIdx)
    throw(MException('Alakazam:AutoEyeICA', ...
        ['None of this dataset''s channels are scalp EEG with a standard 10-5 ' ...
         'position, so there is nothing for ICA to decompose. Rename ' ...
         'channels to match 10-5 nomenclature, or set their locations ' ...
         'manually (Edit > Channel locations) first.']));
end
if ~isempty(otherIdx)
    fprintf('AutoEyeICA: excluding %d non-scalp channel(s) (peripheral or unpositioned; not decomposed): %s\n', ...
        numel(otherIdx), strjoin({EEG.chanlocs(otherIdx).labels}, ', '));
end

%% Decompose just the positioned channels.
%  Use FastICA automatically when it is installed, so the ICA-algorithm
%  dialog is skipped; otherwise fall back to pop_runica's own default
%  (and its dialog), unchanged from before.
eegOnly = pop_select(EEG, 'channel', eegIdx);
if ~isempty(which('fastica'))
    eegOnly = pop_runica(eegOnly, 'icatype', 'fastica');
else
    eegOnly = pop_runica(eegOnly);
end

%% Classify
eegOnly = iclabel(eegOnly, 'beta');

%% Prune every component ICLabel calls 'Eye' above the threshold
classes = eegOnly.etc.ic_classification.ICLabel.classes;
probs   = eegOnly.etc.ic_classification.ICLabel.classifications;
eyeCol  = find(strcmpi(classes, 'Eye'), 1);
if isempty(eyeCol)
    throw(MException('Alakazam:AutoEyeICA', ...
        'ICLabel did not return an ''Eye'' category; cannot prune.'));
end

eyeComps = find(probs(:, eyeCol) > opts.EyeThreshold);
fprintf('AutoEyeICA: pruned %d of %d component(s) as eye (threshold %.2f).\n', ...
    numel(eyeComps), size(probs, 1), opts.EyeThreshold);
if ~isempty(eyeComps)
    eegOnly = pop_subcomp(eegOnly, eyeComps, 0);
end

%% Re-insert the excluded (unpositioned) channels at their original slots,
%  unmodified -- they were excluded from decomposition entirely, so
%  pruning never touched their data and no realignment is needed (ICA
%  does not change the sample/trial count). icachansind is remapped from
%  eegOnly's own local 1..N indices back to indices into the full channel
%  list, so it still correctly identifies which channels the kept ICA
%  weights/classifications belong to.
merged = EEG;
merged.data(eegIdx, :, :) = eegOnly.data;
merged.icaweights  = eegOnly.icaweights;
merged.icasphere   = eegOnly.icasphere;
merged.icawinv     = eegOnly.icawinv;
merged.icaact      = eegOnly.icaact;
merged.icachansind = eegIdx(eegOnly.icachansind);
merged.etc.ic_classification = eegOnly.etc.ic_classification;
EEG = merged;
EEG.id = name;
