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
%   template, see Template1005File). A channel the template does not
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
        opts = [];   % the contract is two outputs; both must be assigned
        % (named for THIS function's own second output: assigning a
        % variable called "options" here left opts holding the Init
        % sentinel, which is what the caller then tried to store)
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
    TransTools.Template1005File('Alakazam:AutoEyeICA'));
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
        ['I''m afraid none of this dataset''s channels are scalp EEG with a standard 10-5 ' ...
         'position, so there is nothing for ICA to decompose. Please rename ' ...
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
%
%  A decomposition already computed for exactly this data is reused (see
%  TransTools.IcaCache), so changing the threshold below re-prunes rather
%  than re-decomposing, and a recalculation gives the components of the run
%  before it: nothing seeds ICA, so a fresh run would not. The decomposition
%  and ICLabel's classification do not depend on the threshold, which is why
%  they can be kept apart from it. Redecompose = true forces a fresh one.
eegOnly = pop_select(EEG, 'channel', eegIdx);
if ~isempty(which('fastica'))
    icaType = 'fastica';
else
    icaType = 'runica';
end
key = TransTools.DataKey(eegOnly.data, {EEG.chanlocs(eegIdx).labels}, icaType);
decomposition = [];
if ~logical(TransTools.FieldOr(opts, 'Redecompose', false))
    decomposition = TransTools.IcaCache('get', key);
end

if isempty(decomposition)
    if strcmp(icaType, 'fastica')
        % See TransTools.WithRestoredRng: runica leaves the session's random
        % number generator in legacy mode, where rng() is an error.
        eegOnly = TransTools.WithRestoredRng(@() pop_runica(eegOnly, 'icatype', 'fastica'));
    else
        eegOnly = TransTools.WithRestoredRng(@() pop_runica(eegOnly));
    end

    %% Classify
    eegOnly = iclabel(eegOnly, 'beta');

    decomposition = struct('key', key, 'icatype', icaType, ...
        'icaweights', eegOnly.icaweights, 'icasphere', eegOnly.icasphere, ...
        'icawinv', eegOnly.icawinv, 'icachansind', eegOnly.icachansind, ...
        'etc', pickIcaEtc(eegOnly.etc));
    TransTools.IcaCache('put', key, decomposition);
else
    fprintf('AutoEyeICA: reusing the decomposition already computed for this data.\n');
    eegOnly = restoreDecomposition(eegOnly, decomposition);
end

%% Prune every component ICLabel calls 'Eye' above the threshold
classes = eegOnly.etc.ic_classification.ICLabel.classes;
probs   = eegOnly.etc.ic_classification.ICLabel.classifications;
eyeCol  = find(strcmpi(classes, 'Eye'), 1);
if isempty(eyeCol)
    throw(MException('Alakazam:AutoEyeICA', ...
        'I''m sorry, ICLabel did not return an ''Eye'' category, so there is nothing I can prune.'));
end

eyeComps = find(probs(:, eyeCol) > opts.EyeThreshold);
fprintf('AutoEyeICA: pruned %d of %d component(s) as eye (threshold %.2f).\n', ...
    numel(eyeComps), size(probs, 1), opts.EyeThreshold);

% WHICH COMPONENTS WENT, recorded before they go. The node's own options
% carry only the threshold, and etc.ic_classification is rewritten by
% pop_subcomp below to describe the components that SURVIVE -- so once this
% has run there is no way to recover which ones were removed, or how
% confident ICLabel was about them. The data-quality report reads this field
% to say what the correction actually did, the same way it reads
% etc.alz.artefactDetectors to say what rejection did.
%
% The whole decomposition (weights, sphere, ICLabel's classification: a few
% kilobytes) is kept here too, before pruning, because the node holds only
% the pruned one. It is what lets a recalculation in a later session change
% the threshold without decomposing again (see TransTools.IcaCache).
eyeRecord = struct( ...
    'threshold',        opts.EyeThreshold, ...
    'removed',          eyeComps(:)', ...
    'nRemoved',         numel(eyeComps), ...
    'nComponents',      size(probs, 1), ...
    'eyeProbabilities', probs(eyeComps, eyeCol)', ...
    'decomposition',    decomposition);

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
merged.etc.alz.eyeICA = eyeRecord;
EEG = merged;
EEG.id = name;

% ======================================================================= %
function etc = pickIcaEtc(fullEtc)
%PICKICAETC  The parts of EEG.etc that the decomposition and its
%   classification wrote, and nothing of what was already there.
    etc = struct();
    for name = {'ic_classification', 'icaweights_beforerms', 'icasphere_beforerms'}
        if isfield(fullEtc, name{1})
            etc.(name{1}) = fullEtc.(name{1});
        end
    end

function eegOnly = restoreDecomposition(eegOnly, decomposition)
%RESTOREDECOMPOSITION  Put a stored decomposition and its classification back
%   on EEGONLY, as pop_runica and iclabel would have left them, so pop_subcomp
%   can prune it. The activations are not restored: they are weights x sphere x
%   data, and pop_subcomp computes what it needs from those.
    eegOnly.icaweights  = decomposition.icaweights;
    eegOnly.icasphere   = decomposition.icasphere;
    eegOnly.icawinv     = decomposition.icawinv;
    eegOnly.icachansind = decomposition.icachansind;
    eegOnly.icaact      = [];
    for name = fieldnames(decomposition.etc)'
        eegOnly.etc.(name{1}) = decomposition.etc.(name{1});
    end
