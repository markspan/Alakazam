function [EEG, opts] = RemoveComponents(input, varargin)
%% RemoveComponents  Manually subtract ICA components chosen by hand.
%
%   The manual counterpart of AutoEyeICA: rather than pruning eye components
%   automatically by an ICLabel threshold, it opens a component selector
%   (RemoveComponentsDialog) showing every component's ICLabel class
%   probabilities and a live scalp-topography preview, and subtracts exactly
%   the components the analyst ticks (pop_subcomp). Use it to remove a
%   specific non-ocular component -- muscle, heart, line/channel noise, or a
%   single bad channel's projection -- that automatic eye pruning leaves in.
%
%   If the dataset already carries an ICA decomposition (EEG.icaweights, e.g.
%   from a preceding AutoEyeICA or decomposition step) it is reused; otherwise
%   ICA is run here (headless, no EEGLAB dialog) on the positioned scalp
%   channels and classified with ICLabel, exactly as AutoEyeICA does (channels
%   with no standard 10-5 scalp position -- EOG, ECG -- are excluded from
%   decomposition and spliced back unmodified). It works on continuous or
%   epoched data alike; segmenting first is not required.
%
%   Because the chosen component numbers are specific to one ICA
%   decomposition (ICA is not deterministic across runs), this transform is
%   inspection-driven and is not registered as recalculable: the stored
%   options record which components were removed for provenance, and a compute
%   pass subtracts them from whatever decomposition the dataset then carries.
%
%   Signature (Alakazam transformation contract):
%     [EEG, opts] = RemoveComponents(input)        % interactive selector
%     [EEG, opts] = RemoveComponents(input, opts)  % subtract opts.components
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:RemoveComponents', varargin{:});

EEG = ensureDecomposition(input);

if interactive
    icl = EEG.etc.ic_classification.ICLabel;
    % Draw the component topographies with template-native theta/radius, the
    % same way ScalpDistribution builds its ScalpChanlocs. The decomposed
    % channels were positioned by FillChanlocs -> pop_chanedit('lookup'),
    % which rewrites theta to a '+X' nose convention (rotated 90 degrees from
    % the template's '+Y'); DrawScalpMap reads the stored theta, so passing
    % those directly would draw every map rotated 90 degrees. Re-derive the
    % polar coordinates straight from the template by label instead.
    dispLocs = TransTools.TemplateScalpLocs(EEG.chanlocs(EEG.icachansind), ...
        TransTools.Template1005File('Alakazam:RemoveComponents'));
    % An equivalent dipole per component, for its residual variance: a
    % physical criterion independent of ICLabel's classifier, and most
    % informative where the two disagree. Only on the interactive path,
    % because it costs seconds per component and nothing but the selector
    % reads it. See TransTools.ComponentDipoles for why a dipole fit is the
    % right question to ask of a component and the wrong one to ask of an ERP.
    rv = TransTools.ComponentDipoles(EEG);

    [removed, ok] = RemoveComponentsDialog(icl, EEG.icawinv, dispLocs, EEG.icaact, EEG.srate, rv);
    if ~ok
        EEG = [];   % cancelled -- no node, no compute
        opts = [];   % the contract is two outputs; both must be assigned
        % (named for THIS function's own second output: assigning a
        % variable called "options" here left opts holding the Init
        % sentinel, which is what the caller then tried to store)
        return;
    end
    opts = struct('components', removed(:)');
    TransformSettings.set('RemoveComponents', opts);
end

if ~isfield(opts, 'components') || isempty(opts.components)
    return;   % nothing selected: keep the decomposed dataset unchanged
end

EEG = pop_subcomp(EEG, opts.components(:)', 0);
end

% ======================================================================= %
function EEG = ensureDecomposition(input)
%ENSUREDECOMPOSITION  Return INPUT with a usable ICA decomposition and ICLabel
%   classification. An existing decomposition is reused (and classified if it
%   has not been already); otherwise ICA is run on the positioned scalp
%   channels and the weights are merged back onto the full dataset -- the same
%   channel-eligibility pattern AutoEyeICA uses.
    EEG = input;
    if isfield(EEG, 'File') && ~isempty(EEG.File)
        [~, name, ~] = fileparts(EEG.File);
        EEG.id = name;
    end

    if isfield(EEG, 'icaweights') && ~isempty(EEG.icaweights) && ...
            isfield(EEG, 'icawinv') && ~isempty(EEG.icawinv) && ...
            isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind)
        if ~hasICLabel(EEG)
            EEG = classifyOnSubset(EEG);
        end
        if ~isfield(EEG, 'icaact') || isempty(EEG.icaact)
            % A reused decomposition does not always carry its activations
            % (EEGLAB sometimes leaves icaact empty and computes it lazily) --
            % the manual selector's own time-course/spectrum preview needs
            % them, so fill them in here rather than at every call site that
            % might need them.
            EEG = eeg_checkset(EEG, 'ica');
        end
        return;
    end

    EEG = TransTools.FillChanlocs(EEG, 'Alakazam:RemoveComponents', ...
        TransTools.Template1005File('Alakazam:RemoveComponents'));
    % Decompose the scalp EEG channels only. A channel needs a scalp position
    % (hasPos) AND must not be a peripheral (EOG/ECG/...): EOG electrodes often
    % carry real coordinates beside/below the eyes, so they pass hasPos and,
    % if left in, dominate the decomposition and plot as blobs outside the
    % head. Exclude them by type (guessed from the label so this works even
    % when the dataset arrived pre-positioned but untyped).
    EEG.chanlocs = guessChannelTypes(EEG.chanlocs);
    hasPos  = arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), EEG.chanlocs);
    isBrain = eegChannelMask(EEG.chanlocs);
    eegIdx  = find(hasPos & isBrain);
    if isempty(eegIdx)
        throw(MException('Alakazam:RemoveComponents', ...
            ['None of this dataset''s channels are scalp EEG with a standard ' ...
             '10-5 position, so there is nothing for ICA to decompose. Set ' ...
             'channel locations (Channel editor) first, or run a decomposition step.']));
    end

    eegOnly = pop_select(EEG, 'channel', eegIdx);
    % Always give pop_runica an explicit algorithm so it runs headless: with
    % no options it opens EEGLAB's own ICA GUI. ICA needs no epoching -- runica
    % decomposes continuous and epoched data alike (epoched data is just
    % reshaped to 2-D internally), so nothing here requires segmented data.
    % Wrapped because runica seeds itself with the legacy rand('state', ...)
    % syntax, which leaves the whole session unable to call rng(). See
    % TransTools.WithRestoredRng.
    if ~isempty(which('fastica'))
        eegOnly = TransTools.WithRestoredRng(@() pop_runica(eegOnly, 'icatype', 'fastica'));
    else
        eegOnly = TransTools.WithRestoredRng(@() ...
            pop_runica(eegOnly, 'icatype', 'runica', 'extended', 1));
    end
    eegOnly = iclabel(eegOnly, 'beta');

    EEG.icaweights  = eegOnly.icaweights;
    EEG.icasphere   = eegOnly.icasphere;
    EEG.icawinv     = eegOnly.icawinv;
    EEG.icaact      = eegOnly.icaact;
    EEG.icachansind = eegIdx(eegOnly.icachansind);
    EEG.etc.ic_classification = eegOnly.etc.ic_classification;
end

function tf = hasICLabel(EEG)
    tf = isfield(EEG, 'etc') && isstruct(EEG.etc) && ...
        isfield(EEG.etc, 'ic_classification') && ...
        isfield(EEG.etc.ic_classification, 'ICLabel') && ...
        isfield(EEG.etc.ic_classification.ICLabel, 'classifications') && ...
        ~isempty(EEG.etc.ic_classification.ICLabel.classifications);
end

function EEG = classifyOnSubset(EEG)
%CLASSIFYONSUBSET  Run ICLabel on an existing decomposition. ICLabel needs the
%   decomposed channels' locations, so classify a channel subset carrying the
%   same ICA fields, then copy the classification back.
    eegOnly = pop_select(EEG, 'channel', EEG.icachansind);
    eegOnly.icaweights  = EEG.icaweights;
    eegOnly.icasphere   = EEG.icasphere;
    eegOnly.icawinv     = EEG.icawinv;
    eegOnly.icachansind = 1:numel(EEG.icachansind);
    eegOnly.icaact      = [];
    eegOnly = eeg_checkset(eegOnly);
    eegOnly = iclabel(eegOnly, 'beta');
    EEG.etc.ic_classification = eegOnly.etc.ic_classification;
end
