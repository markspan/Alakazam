function ctx = fieldtripStepContext(transformId, input, result)
%FIELDTRIPSTEPCONTEXT  What a FieldTrip script needs to know about one step
%   of an Alakazam analysis beyond its options: its input's sample rate,
%   channels and format, and, for a step whose outcome FieldTrip cannot
%   reproduce by itself, that outcome.
%
%   CTX = fieldtripStepContext(TRANSFORMID, INPUT, RESULT) reads INPUT (the
%   dataset the step ran on) and RESULT (what it produced) and returns
%     .srate, .labels, .format   of INPUT
%     .decision                  for some steps, below; [] for the others
%
%   DECISIONS, NOT METHODS. Some of Alakazam's steps have no FieldTrip
%   counterpart: the bin language, ERPLAB's artefact detectors, a manual
%   rejection. Rather than approximate them, the exported script reads back
%   what they decided, so that it reproduces this analysis instead of a
%   similar one, and says so:
%     DefineBins    .epochStart (the sample of INPUT each trial starts at,
%                   which DefineBins records), .pnts, .offset (the samples
%                   before the anchor, negative), .bins (the ordinary bins'
%                   indices and labels) and .membership (trials x bins,
%                   logical)
%     ManualReject, ArtefactDetect, AutoReject
%                   .rejected (the trials rejected here, whole), .partial
%                   (true when it changed parts of trials too, by rejecting
%                   or interpolating channels in them, which the script
%                   cannot carry)
%     Average       .bins: every bin's index, label and, for a combination
%                   bin, its coefficients and the bins it combines
%     AutoEyeICA, RemoveComponents
%                   .unmixing (weights times sphere), .topolabel (the
%                   channels decomposed), .removed (the components taken
%                   out), .why (how they were chosen), and .exact: whether
%                   subtracting those components from INPUT, as FieldTrip's
%                   ft_rejectcomponent does, gives RESULT. EEGLAB's
%                   pop_subcomp rebuilds the data from the components it
%                   keeps instead, which is the same thing whenever the
%                   decomposition spans the data, so this is checked on the
%                   data rather than assumed. For a re-run (see
%                   EXPORTFIELDTRIPSCRIPT) also .method, the algorithm
%                   ('fastica' or 'runica'; 'runica', EEGLAB's own, when it
%                   is not recorded), and .templates, the topographies of the
%                   removed components (channels x components)
%   A DefineBins result made before epochStart was recorded is refused with
%   a message: recompute the step to export it.
%
%   ITS OWN FUNCTION, AND PURE, so that the export can be tested on results
%   computed in a test, and the app's collector (onExportFieldTripScript)
%   only has to find the datasets.
%
%   See also EXPORTFIELDTRIPSCRIPT, FIELDTRIPTRANSFORMCALL.
    ctx = struct('srate', double(input.srate), 'labels', {channelLabels(input)}, ...
        'format', upper(char(string(TransTools.FieldOr(input, 'DataFormat', '')))), ...
        'decision', []);
    switch char(transformId)
        case 'DefineBins'
            ctx.decision = definedTrials(result);
        case {'ManualReject', 'ArtefactDetect', 'AutoReject'}
            ctx.decision = rejectedTrials(input, result);
        case 'Average'
            ctx.decision = struct('bins', {binList(result)});
        case {'AutoEyeICA', 'RemoveComponents'}
            ctx.decision = icaDecision(transformId, input, result);
    end
end

% ======================================================================= %
function labels = channelLabels(EEG)
    labels = {};
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs)
        labels = cellstr(string({EEG.chanlocs.labels}));
    end
end

function d = definedTrials(result)
    if ~strcmpi(TransTools.FieldOr(result, 'DataFormat', ''), 'EPOCHED')
        d = [];   % tags only: nothing was cut
        return;
    end
    alz = TransTools.FieldOr(TransTools.FieldOr(result, 'etc', struct()), 'alz', struct());
    if ~isfield(alz, 'epochStart')
        throw(MException('Alakazam:exportFieldTripScript', ['I''m afraid this DefineBins ' ...
            'result was made before Alakazam recorded where each trial starts in the ' ...
            'recording, which a FieldTrip script needs to cut the same trials. Would you ' ...
            'recalculate the DefineBins step and export again?']));
    end
    nTrials = size(result.data, 3);
    ordinary = find(arrayfun(@(b) isempty(b.combo), result.bindesc));
    membership = false(nTrials, numel(ordinary));
    for j = 1:numel(ordinary)
        membership(TransTools.BinTrials(result, ordinary(j)), j) = true;
    end
    d = struct('epochStart', reshape(double(alz.epochStart), [], 1), ...
        'pnts', size(result.data, 2), ...
        'offset', round(result.times(1) / 1000 * result.srate), ...
        'bins', struct('index', num2cell([result.bindesc(ordinary).index]), ...
            'label', {result.bindesc(ordinary).label}), ...
        'membership', membership);
end

function d = rejectedTrials(input, result)
    gone = @(x) reshape(all(isnan(x), [1 2]), 1, []);
    wasGone = gone(input.data);
    isGone = gone(result.data);
    rejected = find(isGone & ~wasGone);
    % Anything else this step changed in the trials it kept: a channel set
    % to NaN in one trial, or interpolated there.
    before = double(input.data(:, :, ~isGone));
    after = double(result.data(:, :, ~isGone));
    changed = isnan(after) ~= isnan(before) | (abs(after - before) > 0 & ~isnan(after) & ~isnan(before));
    d = struct('rejected', rejected, 'partial', any(changed(:)));
end

function d = icaDecision(transformId, input, result)
    alz = TransTools.FieldOr(TransTools.FieldOr(result, 'etc', struct()), 'alz', struct());
    if strcmp(transformId, 'AutoEyeICA')
        record = TransTools.FieldOr(alz, 'eyeICA', struct());
        % AutoEyeICA's own record indexes the channels it decomposed; the
        % result's icachansind maps them onto the whole dataset.
        chans = TransTools.FieldOr(result, 'icachansind', []);
        why = sprintf('ICLabel''s eye class above %g', TransTools.FieldOr(record, 'threshold', NaN));
    else
        record = TransTools.FieldOr(alz, 'manualICA', struct());
        chans = [];
        if isfield(record, 'decomposition')
            chans = record.decomposition.icachansind;
        end
        why = 'chosen by hand';
    end
    if ~isfield(record, 'decomposition') || isempty(record.decomposition) || isempty(chans)
        throw(MException('Alakazam:exportFieldTripScript', ['I''m afraid this %s result was ' ...
            'made before Alakazam kept the ICA decomposition beside it, which a FieldTrip ' ...
            'script needs to remove the same components. Would you recalculate the %s step ' ...
            'and export again?'], transformId, transformId));
    end
    dec = record.decomposition;
    unmixing = double(dec.icaweights) * double(dec.icasphere);
    mixing = double(dec.icawinv);
    removed = reshape(double(record.removed), 1, []);
    labels = channelLabels(input);
    x = reshape(double(input.data(chans, :, :)), numel(chans), []);
    y = reshape(double(result.data(chans, :, :)), numel(chans), []);
    predicted = x - mixing(:, removed) * (unmixing(removed, :) * x);
    scale = max(1, max(abs(y), [], 'all', 'omitnan'));
    exact = max(abs(predicted - y), [], 'all', 'omitnan') <= 1e-6 * scale;
    method = char(string(TransTools.FieldOr(dec, 'icatype', '')));
    if ~ismember(method, {'fastica', 'runica'})
        method = 'runica';
    end
    d = struct('unmixing', unmixing, 'topolabel', {reshape(labels(chans), [], 1)}, ...
        'removed', removed, 'why', why, 'exact', exact, 'method', method, ...
        'templates', mixing(:, removed));
end

function bins = binList(result)
    bins = struct('index', {}, 'label', {}, 'coeff', {}, 'combines', {});
    for b = 1:numel(result.bindesc)
        combo = TransTools.FieldOr(result.bindesc(b), 'combo', []);
        coeff = [];
        combines = [];
        if ~isempty(combo)
            coeff = [combo.coeff];
            combines = [combo.bin];
        end
        bins(end + 1) = struct('index', result.bindesc(b).index, 'label', result.bindesc(b).label, ...
            'coeff', coeff, 'combines', combines); %#ok<AGROW>
    end
end
