function [EEG, opts] = AutoGEDAI(input, opts)
%% AutoGEDAI  Denoise EEG with GEDAI (generalized eigenvalue decomposition).
%
%   Runs GEDAI (Ros et al., 2025), an EEGLAB plugin that separates brain
%   signal from artifacts using generalized eigenvalue decomposition against
%   a theoretical leadfield-based reference covariance, with automatic
%   signal/artifact-subspace thresholding (SENSAI). It is a broadband
%   alternative (or complement) to AutoEyeICA: run whichever suits the
%   dataset, or neither.
%
%   GEDAI is not bundled with Alakazam or the EEGLAB plugin registry (it is
%   licensed PolyForm Noncommercial 1.0.0: free for personal, noncommercial
%   research use, a separate licence is required for commercial use -- see
%   https://github.com/neurotuning/GEDAI-master/blob/master/LICENSE). The
%   first time this transformation runs on a machine without it, a dialog
%   explains this and asks permission before downloading it into
%   Documents/MATLAB; declining leaves it uninstalled and throws, with
%   instructions to install it manually instead.
%
%   Inputs:
%       input - EEG dataset to denoise.
%       opts  - Struct with fields Strength, Leadfield, LowCut, RejectEpochs,
%               EpochENOVA, RejectChannels, ChannelENOVA, Parallel. If not
%               provided, a settings dialog prompts for them once; the chosen
%               values are returned so a later replay skips the dialog. Only
%               a subset of GEDAI's own options is exposed -- everything else
%               (epoch size, smoothing window, visualisation) uses GEDAI's
%               own defaults.
%
%   Outputs:
%       EEG   - Denoised dataset. Diagnostics (SENSAI score, per-epoch and
%               per-channel ENOVA) are kept in EEG.etc.GEDAI.
%       opts  - Struct with the settings used.
%
%   GEDAI's leadfield-based denoising only works on real scalp EEG channels.
%   Eligibility is decided against GEDAI's own bundled 343-electrode 10-5
%   system template (auxiliaries/standard_1005.elc) -- the same electrode
%   set GEDAI's 'precomputed' mode itself matches channels against by label
%   -- so AutoGEDAI has no dipfit dependency. A channel not in that set
%   (e.g. EOG, ECG) is excluded from GEDAI and spliced back into its
%   original slot, unmodified, once denoising is done. Throws if *no*
%   channel matches.
%
%   opts.Parallel is only ever honoured when a GPU is actually present
%   (gpuDeviceCount > 0): GEDAI's own parfor-based CPU band processing
%   (GEDAI.m's wavelet-band denoising loop) accumulates band results into a
%   reduction variable that is never reset before falling back to
%   non-parallel processing after a parfor error -- and MATLAB documents a
%   parfor reduction variable's value as undefined after a mid-loop error --
%   so a single transient per-band failure (which parallel CPU workers hit
%   far more often than a lone serial run) silently corrupts the output by
%   accumulating the full band set on top of a stale partial sum, with no
%   error surfaced. This reproduced as "sometimes great, sometimes unusable"
%   results from identical settings/data on a GPU-less machine. On a machine
%   with no GPU, this option is therefore forced to 'no' regardless of the
%   dialog choice; reported upstream.
%
%   See also: AutoEyeICA.

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:AutoGEDAI', 'Problem in AutoGEDAI: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end

%% GEDAI is an optional, noncommercially-licensed plugin: make sure it is
%  installed (with consent) before configuring or running anything.
ensureGEDAI();
ensureGpuDeviceCountShim();

if (ischar(opts) || isstring(opts)) && strcmpi(opts, 'Init')
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
    if hasParallelToolbox
        parallelChoices = {'yes', 'no'};
    else
        parallelChoices = {'no', 'yes'};
    end

    % Seed every field from the last time this ran in the current workspace
    % (TransformSettings), falling back to the literal defaults below the
    % first time. For popup fields (settingsdlg shows a cell array as a
    % dropdown, defaulting to its first entry), the remembered choice is
    % moved to the front of its own choice list rather than replacing it,
    % so every option is still selectable.
    stored = TransformSettings.get('AutoGEDAI');
    if isempty(stored)
        stored = struct('Strength', 'auto', 'Leadfield', 'precomputed', 'LowCut', 0.5, ...
            'RejectEpochs', 'no', 'EpochENOVA', 0.9, ...
            'RejectChannels', 'no', 'ChannelENOVA', 0.9, 'Parallel', parallelChoices{1});
    end
    strengthChoices       = putFirst({'auto', 'auto+', 'auto-'}, stored.Strength);
    leadfieldChoices      = putFirst({'precomputed', 'interpolated'}, stored.Leadfield);
    rejectEpochsChoices   = putFirst({'no', 'yes'}, stored.RejectEpochs);
    rejectChannelsChoices = putFirst({'no', 'yes'}, stored.RejectChannels);
    parallelChoices       = putFirst(parallelChoices, stored.Parallel);

    opts = TransformOptionsDialog( ...
        'Description', 'Denoise EEG with GEDAI (generalized eigenvalue decomposition against a leadfield reference).', ...
        'title', 'AutoGEDAI options', ...
        'separator', 'Denoising:', ...
        {'Denoising strength'; 'Strength'}, strengthChoices, ...
        {'Leadfield matrix'; 'Leadfield'}, leadfieldChoices, ...
        {'Low-cut frequency (Hz)'; 'LowCut'}, stored.LowCut, ...
        'separator', 'Bad epoch rejection:', ...
        {'Reject bad epochs'; 'RejectEpochs'}, rejectEpochsChoices, ...
        {'Epoch ENOVA threshold (0-1)'; 'EpochENOVA'}, stored.EpochENOVA, ...
        'separator', 'Bad channel rejection:', ...
        {'Reject bad channels'; 'RejectChannels'}, rejectChannelsChoices, ...
        {'Channel ENOVA threshold (0-1)'; 'ChannelENOVA'}, stored.ChannelENOVA, ...
        'separator', 'Performance:', ...
        {'Use parallel processing'; 'Parallel'}, parallelChoices);
    if isempty(opts)
        % Cancelled: nothing to persist (leave the remembered settings
        % untouched) and nothing to run -- Alakazam.onTransformation
        % treats an empty EEG as "cancelled", not an error.
        EEG = [];
        return;
    end
    TransformSettings.set('AutoGEDAI', opts);
end

EEG = input;
[~, name, ~] = fileparts(EEG.File);
EEG.id = name;

%% GEDAI's leadfield-based denoising only works on real scalp EEG channels.
%  Eligibility is decided against GEDAI's OWN bundled 343-electrode 10-5
%  template (auxiliaries/standard_1005.elc) -- the same electrode set its
%  'precomputed' mode itself matches channels against by label -- rather
%  than dipfit's, so AutoGEDAI has no dipfit dependency at all (GEDAI
%  already ships everything it needs) and eligibility exactly matches what
%  GEDAI itself will accept. A channel not in that list (EOG, ECG, ...) is
%  excluded from GEDAI and spliced back into its original slot, unmodified,
%  once denoising is done.
gedaiElc = gedaiElcFile();
templateLabels = lower(string({readlocs(gedaiElc).labels}));
ownLabels = lower(string({EEG.chanlocs.labels}));
hasPos = ismember(ownLabels, templateLabels);
eegIdx = find(hasPos);
otherIdx = find(~hasPos);

if isempty(eegIdx)
    throw(MException('Alakazam:AutoGEDAI', ...
        ['None of this dataset''s channels match GEDAI''s standard 10-5 ' ...
         'electrode set, so there is nothing for GEDAI to denoise. ' ...
         'Rename channels to match 10-5 nomenclature first.']));
end
if ~isempty(otherIdx)
    fprintf('AutoGEDAI: excluding %d channel(s) not in GEDAI''s standard electrode set (not denoised): %s\n', ...
        numel(otherIdx), strjoin({EEG.chanlocs(otherIdx).labels}, ', '));
end

% 'interpolated' mode needs every channel to carry X/Y/Z ('precomputed'
% matches by label alone and ignores position); fill from the same template
% used for eligibility, so positions and matching stay consistent.
EEG = TransTools.FillChanlocs(EEG, 'Alakazam:AutoGEDAI', gedaiElc);

%% Map the exposed options onto GEDAI's positional arguments; everything not
%  exposed here keeps GEDAI's own default (epoch size 12 cycles, no
%  smoothing window, signal_type 'eeg', no visualisation popup).
epochThreshold = inf;
if strcmpi(opts.RejectEpochs, 'yes')
    epochThreshold = opts.EpochENOVA;
end
channelThreshold = inf;
if strcmpi(opts.RejectChannels, 'yes')
    channelThreshold = opts.ChannelENOVA;
end
% GEDAI's own parfor-based CPU band processing has a reliability bug (see
% the top-of-file note): a transient per-band failure can silently corrupt
% the result instead of erroring, and this is far likelier to actually
% trigger when running many CPU workers with no GPU to offload onto. Honour
% the user's Parallel choice only when a GPU is actually present; a
% GPU-less machine always gets the safe non-parallel path regardless of the
% dialog selection. ensureGpuDeviceCountShim (above) guarantees
% gpuDeviceCount is callable here even without Parallel Computing Toolbox.
useParallel = strcmpi(opts.Parallel, 'yes') && gpuDeviceCount > 0;
if strcmpi(opts.Parallel, 'yes') && ~useParallel
    fprintf(['AutoGEDAI: parallel processing was requested but no GPU was found; ' ...
        'running non-parallel instead (see AutoGEDAI.m for why).\n']);
end

%% Denoise just the positioned channels.
eegOnly = pop_select(EEG, 'channel', eegIdx);
[EEGclean, ~, SENSAI_score, ~, ~, ~, ENOVA_per_epoch, ~, ~, ENOVA_per_channel] = GEDAI( ...
    eegOnly, opts.Strength, 12, opts.LowCut, opts.Leadfield, useParallel, false, ...
    epochThreshold, channelThreshold, 'eeg', Inf);

%% Re-insert the excluded (non-EEG) channels at their original positions,
%  unmodified, so the returned dataset still has every original channel.
%  pop_select preserves the given channel order, so eegIdx (ascending)
%  lines up 1:1 with EEGclean's channels. Only .data needs merging back:
%  chanlocs for eegIdx were already fully populated by FillChanlocs before
%  the split, and GEDAI does not rename or reposition channels, so the
%  original (already-filled) chanlocs still describe them correctly --
%  copying EEGclean's own chanlocs back in risks a struct field mismatch
%  (pop_select/GEDAI may add or drop chanlocs fields) for no real benefit.
%
%  GEDAI's epoch rejection can shrink the sample/trial count; if it did, the
%  excluded channels' original-length data no longer lines up with
%  EEGclean's, and there is no way to know which epochs/samples GEDAI kept.
if ~isequal(size(EEGclean.data, 2), size(EEG.data, 2)) ...
        || ~isequal(size(EEGclean.data, 3), size(EEG.data, 3))
    throw(MException('Alakazam:AutoGEDAI', ...
        ['Cannot re-insert the excluded channels: GEDAI''s epoch rejection ' ...
         'changed the number of samples or trials, so the excluded ' ...
         'channels'' original data no longer lines up. Disable epoch ' ...
         'rejection, or run AutoGEDAI on a dataset with only 10-5-' ...
         'matched channels.']));
end
merged = EEG;
merged.data(eegIdx, :, :) = EEGclean.data;
EEG = merged;
EEG.id = name;
EEG.etc.GEDAI = struct('SENSAI_score', SENSAI_score, ...
    'ENOVA_per_epoch', ENOVA_per_epoch, 'ENOVA_per_channel', ENOVA_per_channel, ...
    'channelIndices', eegIdx, 'excludedChannels', {{EEG.chanlocs(otherIdx).labels}}, ...
    'options', opts);

fprintf('AutoGEDAI: SENSAI score %.3f.\n', SENSAI_score);
if epochThreshold < inf
    fprintf('AutoGEDAI: %d epoch(s) exceeded the ENOVA threshold (%.2f).\n', ...
        sum(ENOVA_per_epoch > epochThreshold), epochThreshold);
end
if channelThreshold < inf
    fprintf('AutoGEDAI: %d channel(s) exceeded the ENOVA threshold (%.2f).\n', ...
        sum(ENOVA_per_channel > channelThreshold), channelThreshold);
end
end

% ======================================================================= %
function choices = putFirst(choices, value)
%PUTFIRST  Move VALUE to the front of the cell array CHOICES, if present.
%   settingsdlg shows a cell-array field as a popup defaulting to its first
%   entry, so this is how a remembered choice becomes the dialog's default
%   without dropping any of the other selectable choices. Leaves CHOICES
%   unchanged if VALUE is not one of them.
    idx = find(strcmpi(choices, value), 1);
    if ~isempty(idx)
        choices = [choices(idx), choices(1:idx - 1), choices(idx + 1:end)];
    end
end

% ======================================================================= %
function ensureGEDAI()
%ENSUREGEDAI  Make sure the GEDAI plugin is on the path, with consent.
%   GEDAI is not in the EEGLAB plugin registry and is licensed for
%   noncommercial use only, so -- unlike the registry plugins and FastICA,
%   which EEGLabEnvironment installs quietly at startup -- it is installed
%   lazily here, on first use, only after the user explicitly agrees.
    if ~isempty(which('GEDAI'))
        return; % already available this session
    end

    % addpath (inside installFromZip) is deliberately session-only, so a
    % previous install is not back on the path in a fresh MATLAB session
    % even though it is still on disk. Reattach it quietly here instead of
    % re-asking for consent (already given) and re-downloading (unnecessary)
    % every single time Alakazam starts.
    existing = EEGLabEnvironment.findInstalled('GEDAI', 'GEDAI.m');
    if ~isempty(existing)
        addpath(existing);
        return;
    end

    gedaiUrl = 'https://github.com/neurotuning/GEDAI-master/archive/refs/tags/v1.7.zip';

    % LEGACY-JAVA-GUI: questdlg is a classic Java/AWT dialog, not a
    % uifigure -- see migration.md's "old-style Java-based graphics"
    % checklist.
    answer = questdlg([ ...
        'AutoGEDAI needs the GEDAI EEGLAB plugin (neurotuning/GEDAI-master), ', ...
        'which was not found on the MATLAB path.', newline, newline, ...
        'GEDAI is licensed under the PolyForm Noncommercial License 1.0.0: ', ...
        'free for personal, noncommercial research use; a separate licence ', ...
        'is required for commercial use. Full terms: ', ...
        'https://github.com/neurotuning/GEDAI-master/blob/master/LICENSE', newline, newline, ...
        'Download and install GEDAI v1.7 now into your Documents/MATLAB folder?'], ...
        'GEDAI not found', ...
        'Download and install', 'Cancel', 'Download and install');

    if ~strcmp(answer, 'Download and install')
        throw(MException('Alakazam:AutoGEDAI', ...
            ['GEDAI is required but was not found on the MATLAB path, and its ' ...
             'installation was declined. Install it manually from ' ...
             'https://github.com/neurotuning/GEDAI-master (extract into your ' ...
             'eeglab/plugins folder), or run AutoGEDAI again and accept the ' ...
             'download prompt.']));
    end

    EEGLabEnvironment.installFromZip(gedaiUrl, 'GEDAI', 'GEDAI.m');
end

% ======================================================================= %
function ensureGpuDeviceCountShim()
%ENSUREGPUDEVICECOUNTSHIM  Work around a GEDAI bug: it calls the real
%   gpuDeviceCount() (Parallel Computing Toolbox) directly to auto-detect
%   GPU acceleration, with no check that the toolbox providing it is even
%   installed and no try/catch around that specific call, so it throws
%   "Unrecognized function or variable" outright on a machine without it,
%   instead of falling back to its own CPU path.
%
%   Adds src/Compat (a fixed shim reporting zero GPUs) to the path, but
%   only when the real gpuDeviceCount is missing, so a machine that
%   genuinely has Parallel Computing Toolbox (and hence real GPU
%   detection) is never shadowed.
    if ~isempty(which('gpuDeviceCount'))
        return; % the real one (Parallel Computing Toolbox) is available
    end
    srcRoot   = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    compatDir = fullfile(srcRoot, 'Compat');
    if exist(fullfile(compatDir, 'gpuDeviceCount.m'), 'file') == 2
        addpath(compatDir);
    end
end

% ======================================================================= %
function elc = gedaiElcFile()
%GEDAIELCFILE  Absolute path to GEDAI's own bundled 10-5 electrode template.
%   GEDAI ships its own copy of the 343-electrode 10-5 system template (an
%   .elc file, ASA format, precomputed via OpenMEEG -- see
%   auxiliaries/standard_1005.elc in the GEDAI plugin) and adds its
%   containing 'auxiliaries' folder to the path itself
%   (fileparts(which('GEDAI'))), so this is resolved the same way rather
%   than depending on dipfit for something GEDAI already provides. Called
%   after ensureGEDAI, so GEDAI (and hence this file) is guaranteed to be on
%   the path already.
    gedaiRoot = fileparts(which('GEDAI'));
    elc = fullfile(gedaiRoot, 'auxiliaries', 'standard_1005.elc');
    if exist(elc, 'file') ~= 2
        throw(MException('Alakazam:AutoGEDAI', ...
            'GEDAI''s bundled electrode template was not found at %s.', elc));
    end
end
