function [EEG, opts] = SourceEstimate(input, varargin)
%SOURCEESTIMATE  Invert an averaged dataset onto the template cortical sheet
%   and keep the result, so that later analyses read it instead of redoing it.
%
%   Every bin in the dataset is inverted and stored on EEG.sourceEstimate,
%   alongside a key recording exactly what produced it
%   (SourceCache.Key).
%
%   WHY THIS IS A TRANSFORMATION AND NOT A CACHE. The inversion is expensive
%   and repeatable, which is the definition of something worth storing, and
%   Alakazam already has a mechanism for exactly that: a node in the tree.
%   It carries provenance, it is invalidated when anything upstream changes,
%   the analyst can see it and delete it, and collectEntriesWithField finds
%   it through the JSON sidecar without loading the node. A private cache
%   beside all that would be a second mechanism doing the same job worse.
%
%   THE ESTIMATE IS DEFINED BY ITS FORWARD MODEL, WHICH IS WHY THE KEY
%   EXISTS. This transformation builds a forward model from THIS dataset's
%   own channels. A group analysis must use one forward model for every
%   subject, or their vertices are not comparable with one another, and it
%   now requires every subject to already be on the same montage rather than
%   quietly intersecting them (SourceClusterStats' own sharedMontage).
%
%   That requirement is what makes the estimates here worth storing. With
%   one montage across the study, this dataset's own channels ARE the
%   group's, so the key matches and the report reads the estimate off the
%   tree instead of recomputing it. Reuse is still checked rather than
%   assumed: the key must agree on mesh, method, orientation,
%   regularisation, window and rate as well, and the fingerprint must say
%   the data has not moved underneath.
%
%   WHAT IS AND IS NOT WORTH IT. On the runs that hurt, the inversion is a
%   small share of the total: about 55% of a short test but only ~3% of a
%   thousand-permutation one, where the permutations dominate. The gain here
%   is mostly in iterating -- trying several contrasts or windows against
%   one set of estimates -- and in other views reading the same node rather
%   than each inverting again.
%
%   Signature (Alakazam transformation contract):
%     [EEG, opts] = SourceEstimate(input)        % settings dialog
%     [EEG, opts] = SourceEstimate(input, opts)  % replay stored settings
%
%   See also SOURCECLUSTERSTATS, TRANSTOOLS.SOURCEESTIMATEKEY,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.INVERSESOLUTION.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SourceEstimate', varargin{:});

if ~isfield(input, 'bindesc') || isempty(input.bindesc)
    throw(MException('Alakazam:SourceEstimate', '%s', ...
        ['I''m afraid this dataset has no bins, so there is nothing to invert. ' ...
         'Run DefineBins and Average first: a source estimate is computed per bin ' ...
         'of an averaged dataset.']));
end
if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:SourceEstimate', '%s', ...
        'I''m afraid this dataset has no data, so there is nothing to invert.'));
end

if interactive
    opts = SourceEstimateDialog(input, TransformSettings.get('SourceEstimate'));
    if isempty(opts)
        EEG = [];       % cancelled -- no node, no compute
        opts = [];      % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('SourceEstimate', opts);
end

EEG = TransTools.ResolveScalpDistribution(input, 'Alakazam:SourceEstimate');
% APPENDED, NOT ASSIGNED. Running this again with a different method or
% orientation should add that estimate, not throw away the previous one:
% they answer different questions and a consumer picks by key. Re-running
% with the SAME settings replaces, since the second result supersedes the
% first rather than joining it.
EEG.sourceEstimate = SourceCache.Attach( ...
    existingEstimates(input), computeEstimates(input, opts));
end

% ======================================================================= %
function estimate = computeEstimates(EEG, opts)
%COMPUTEESTIMATES  One inversion per bin, on this dataset's own channels.
    TransTools.ensureFieldTrip('Source estimates');

    % THE SAME CHANNEL SET Brain3D and the scalp views resolve, not simply
    % every label in the file. A stored estimate is reusable only when the
    % consumer's channel set matches it exactly, so choosing a different
    % rule here would make the estimate correct and useless. Non-scalp
    % channels (EOG, ECG) have no template position and drop out anyway;
    % taking the same route makes that agreement deliberate rather than
    % coincidental.
    EEG = TransTools.ResolveScalpDistribution(EEG, 'Alakazam:SourceEstimate');
    labels = {EEG.ScalpChanlocs.labels};
    [leadfield, sourcemodel, resolvedLabels, elec, headmodel] = ...
        TransTools.BuildSourceForwardModel(labels, opts.SourceSpace);
    normals = TransTools.SurfaceNormals(sourcemodel);
    vertexLabels = TransTools.SourceVertexLabels(size(sourcemodel.pos, 1));

    have = labels;
    [tf, reorder] = ismember(lower(resolvedLabels), lower(have));
    if ~all(tf)
        throw(MException('Alakazam:SourceEstimate', '%s', ...
            'The forward model needs a channel this dataset does not carry.'));
    end

    bins = {EEG.bindesc.label};
    if size(EEG.data, 3) < numel(bins)
        throw(MException('Alakazam:SourceEstimate', '%s', sprintf( ...
            'This dataset describes %d bins but its data holds %d.', ...
            numel(bins), size(EEG.data, 3))));
    end

    solveOpts = struct('RegParam', opts.RegParam);
    if strcmpi(opts.Orientation, 'normal')
        solveOpts.Orientation = 'normal';
        solveOpts.Normals     = normals;
    end

    % Every bin shares one time base -- the same window and rate applied to
    % the same EEG.times -- so it is settled once, before the loop, and the
    % output can be allocated whole rather than on the first pass.
    [~, times] = prepareBin(EEG, reorder, 1, opts);
    values  = zeros(numel(vertexLabels), numel(times), numel(bins));
    binInfo = repmat(struct('residualVariance', NaN, 'scaleLabel', '', ...
        'scaleNote', '', 'lambda', NaN), 1, numel(bins));

    for b = 1:numel(bins)
        binValues = prepareBin(EEG, reorder, b, opts);
        [source, info] = TransTools.InverseSolution(binValues, leadfield, elec, headmodel, ...
            opts.Method, solveOpts);
        values(:, :, b) = source;
        % Kept because consumers display it: Brain3D puts the residual
        % variance in its axes title and the scale label on its colour bar,
        % and recomputing an inverse purely to recover two strings and a
        % number would defeat the point of having stored the estimate.
        binInfo(b) = struct('residualVariance', info.ResidualVariance, ...
            'scaleLabel', info.ScaleLabel, 'scaleNote', info.ScaleNote, ...
            'lambda', info.Lambda);
    end

    estimate = struct();
    estimate.values       = values;              % vertices x time x bin
    estimate.times        = times;               % ms
    estimate.bins         = bins;
    estimate.vertexLabels = {vertexLabels};
    estimate.info         = binInfo;             % one per bin, in bins order
    estimate.key          = SourceCache.Key(resolvedLabels, opts);
    % Bound to the data it was computed from, so that a later transformation
    % inheriting this field cannot pass it off as its own. See
    % SourceCache.Fingerprint.
    estimate.dataFingerprint = SourceCache.Fingerprint(EEG);
end

function [values, times] = prepareBin(EEG, reorder, bin, opts)
%PREPAREBIN  This bin's scalp data, restricted and decimated by the SAME
%   function SourceClusterStats uses (TransTools.RestrictAndDecimate), which
%   is what lets the key assert the two are interchangeable.
    % TWO STEPS, NOT ONE. reorder indexes into the SCALP channel set
    % (EEG.ScalpChanlocs), not into EEG.data's own channel dimension, which
    % also carries EOG and anything else without a template position. Using
    % it directly on EEG.data selects a different set of channels entirely
    % and inverts them as though they were the resolved ones: the estimate
    % comes out plausible, wrong, and impossible to spot afterwards.
    scalpData = EEG.data(EEG.ScalpHasPos, :, bin);
    values = double(scalpData(reorder, :));
    times  = reshape(EEG.times, 1, []);
    if numel(times) ~= size(values, 2)
        throw(MException('Alakazam:SourceEstimate', '%s', sprintf( ...
            ['This dataset has %d latencies for %d samples of data, so timing ' ...
             'cannot be trusted.'], numel(times), size(values, 2))));
    end

    [values, times] = TransTools.RestrictAndDecimate(values, times, ...
        TransTools.FieldOr(opts, 'TimeWindow', []), ...
        TransTools.FieldOr(opts, 'ResampleHz', []), 'Alakazam:SourceEstimate');
end

function existing = existingEstimates(EEG)
%EXISTINGESTIMATES  Whatever this dataset already carries, as an array.
%   Inherited estimates are kept: SourceCache.Lookup refuses
%   any whose fingerprint no longer matches the data, so a stale one costs
%   space rather than correctness, and discarding it here would throw away a
%   valid estimate whenever a dataset simply passed through untouched.
    existing = [];
    if isfield(EEG, 'sourceEstimate') && ~isempty(EEG.sourceEstimate)
        existing = EEG.sourceEstimate;
    end
end
