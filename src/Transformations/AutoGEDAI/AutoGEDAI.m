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

if (ischar(opts) || isstring(opts)) && strcmpi(opts, 'Init')
    hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
    if hasParallelToolbox
        parallelChoices = {'yes', 'no'};
    else
        parallelChoices = {'no', 'yes'};
    end

    opts = uiextras.settingsdlg( ...
        'Description', 'Denoise EEG with GEDAI (generalized eigenvalue decomposition against a leadfield reference).', ...
        'title', 'AutoGEDAI options', ...
        'separator', 'Denoising:', ...
        {'Denoising strength'; 'Strength'}, {'auto', 'auto+', 'auto-'}, ...
        {'Leadfield matrix'; 'Leadfield'}, {'precomputed', 'interpolated'}, ...
        {'Low-cut frequency (Hz)'; 'LowCut'}, 0.5, ...
        'separator', 'Bad epoch rejection:', ...
        {'Reject bad epochs'; 'RejectEpochs'}, {'no', 'yes'}, ...
        {'Epoch ENOVA threshold (0-1)'; 'EpochENOVA'}, 0.9, ...
        'separator', 'Bad channel rejection:', ...
        {'Reject bad channels'; 'RejectChannels'}, {'no', 'yes'}, ...
        {'Channel ENOVA threshold (0-1)'; 'ChannelENOVA'}, 0.9, ...
        'separator', 'Performance:', ...
        {'Use parallel processing'; 'Parallel'}, parallelChoices);
end

EEG = input;
[~, name, ~] = fileparts(EEG.File);
EEG.id = name;

%% GEDAI needs scalp locations; auto-fill from a standard montage template
%  when none are set, rather than opening the interactive Channel Editor.
%  (Same fallback as AutoEyeICA uses for ICLabel.)
hasLocs = isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) ...
    && isfield(EEG.chanlocs, 'X') && ~all(cellfun(@isempty, {EEG.chanlocs.X}));
if ~hasLocs
    EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
end

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
useParallel = strcmpi(opts.Parallel, 'yes');

%% Denoise
[EEGclean, ~, SENSAI_score, ~, ~, ~, ENOVA_per_epoch, ~, ~, ENOVA_per_channel] = GEDAI( ...
    EEG, opts.Strength, 12, opts.LowCut, opts.Leadfield, useParallel, false, ...
    epochThreshold, channelThreshold, 'eeg', Inf);

EEG = EEGclean;
EEG.id = name;
EEG.etc.GEDAI = struct('SENSAI_score', SENSAI_score, ...
    'ENOVA_per_epoch', ENOVA_per_epoch, 'ENOVA_per_channel', ENOVA_per_channel, ...
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
function ensureGEDAI()
%ENSUREGEDAI  Make sure the GEDAI plugin is on the path, with consent.
%   GEDAI is not in the EEGLAB plugin registry and is licensed for
%   noncommercial use only, so -- unlike the registry plugins and FastICA,
%   which EEGLabEnvironment installs quietly at startup -- it is installed
%   lazily here, on first use, only after the user explicitly agrees.
    if ~isempty(which('GEDAI'))
        return; % already available
    end

    gedaiUrl = 'https://github.com/neurotuning/GEDAI-master/archive/refs/tags/v1.7.zip';

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
