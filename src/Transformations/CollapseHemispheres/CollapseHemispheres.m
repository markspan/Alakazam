function [EEG, options] = CollapseHemispheres(input, varargin)
%% CollapseHemispheres  Contralateral and ipsilateral waveforms, collapsed
%  across the hemispheres.
%
%   The N2pc and the LRP are contralateral-minus-ipsilateral differences: the
%   effect is defined relative to the side the stimulus appeared on, or the
%   hand that responded, so the electrode that counts changes from trial to
%   trial. Given bins that differ in that side, this produces the two
%   waveforms the literature reports:
%
%       contra = (left-side bins at RIGHT electrodes + right-side bins at LEFT
%                 electrodes) / 2
%       ipsi   = (left-side bins at LEFT  electrodes + right-side bins at RIGHT
%                 electrodes) / 2
%
%   WHY THIS CANNOT BE A BIN OR A CHANNEL OPERATION, which is the whole
%   reason it is its own step. It selects bins AND channel subsets in one
%   expression -- ERPLAB writes it as "contra = (b1@RH + b2@LH)/2", mixing a
%   bin operator with a channel qualifier. Alakazam's difference bins take
%   coefficient-weighted whole bins with no channel qualifier (DefineBins),
%   and its channel arithmetic is elementwise within one bin (DeriveChannels);
%   neither can express a term that reads one bin at one electrode and
%   another bin at a different one.
%
%   The composed route still works and is worth knowing, because it needs no
%   side assignment: "let C34 = C4 - C3" in Derive Channels plus
%   "bin 3 = 0.5 bin 1 - 0.5 bin 2" gives the contra-minus-ipsi DIFFERENCE
%   exactly (checked against ERPLAB to 6.7e-15 uV). What it cannot give is
%   contra and ipsi SEPARATELY, or all the lateral pairs at once, which is
%   what this does.
%
%   THE MONTAGE IS NOT ASSUMED. Pairs come from LateralPairs, which mirrors
%   electrode positions through the mid-sagittal plane and falls back to label
%   conventions (10-20 odd/even, or the L/R letter that equidistant montages
%   use) when a dataset has no locations yet. So this works on a 10-20 cap and
%   on an equidistant one, and never pairs by channel order -- see
%   LateralPairs for the montage where that would silently invert a pair.
%
%   THE MONTAGE IS ALSO PRESERVED. Each pair's collapsed waveform is written
%   to BOTH of its electrodes, so the new bins have the same channels as the
%   old ones: measuring the Contra bin at PO7 or at PO8 gives the same,
%   correct contralateral waveform, scalp maps still draw, and every
%   downstream step keeps working. Midline and unpaired electrodes have no
%   laterality to collapse, so they carry the plain mean of the two sides,
%   which is what contra and ipsi both reduce to there.
%
%   EACH SIDE IS AVERAGED BEFORE THE TWO ARE, so the sides weigh equally
%   however many bins each has -- the unweighted /2 above, and ERPLAB's. With
%   one bin a side it is exactly ERPLAB's expression. Standard errors and
%   aSME propagate as the root of the summed squared errors, the same
%   convention Average.m uses for its own combination bins.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = CollapseHemispheres(input)        % interactive dialog
%     [EEG, options] = CollapseHemispheres(input, opts)  % replay a stored struct
%
%   OPTIONS carries .leftBins and .rightBins (cell arrays of BIN LABELS, not
%   indices, so a stored template survives a bin being added or reordered),
%   .pairing ('auto', 'geometry' or 'labels'), and .contraLabel/.ipsiLabel.
%
%   See also LATERALPAIRS, COLLAPSEHEMISPHERESDIALOG,
%   DERIVECHANNELS, DEFINEBINS, AVERAGE.
% "chosen" rather than "opts", and that is not a stylistic choice: this
% function declares its second output as "options", so a bare "opts = ..."
% here would be indistinguishable from the silent bug TransformContractTest
% guards against (assigning the name the signature does NOT use, leaving the
% real output holding InitGuard's sentinel). Only "options" is assigned
% below, once, and the rest of the function reads that -- so what gets
% stored for replay is exactly what was used.
[chosen, interactive] = TransTools.InitGuard(nargin, 'Alakazam:CollapseHemispheres', varargin{:});

requireAveragedWithBins(input);
binLabels = binLabelList(input.bindesc);

if interactive
    stored = TransformSettings.get('CollapseHemispheres');
    [chosen, ok] = CollapseHemispheresDialog(binLabels, input.chanlocs, stored);
    if ~ok
        EEG = [];        % cancelled: no node, no compute
        options = [];    % the contract is two outputs; both must be assigned
        return;
    end
end

options = withDefaults(chosen);
if interactive
    TransformSettings.set('CollapseHemispheres', options);
end

leftIdx  = binIndicesFor(options.leftBins,  binLabels, 'left');
rightIdx = binIndicesFor(options.rightBins, binLabels, 'right');

pairing = LateralPairs(input.chanlocs, options.pairing);
if isempty(pairing.pairs)
    throw(MException('Alakazam:CollapseHemispheres', ...
        ['Problem in CollapseHemispheres: I''m afraid I could not match a single ' ...
         'left electrode to a right one in this montage (pairing by "%s"), so there ' ...
         'is nothing to collapse. Fill in the channel locations (Channel editor) and ' ...
         'try again, or check that the labels follow either the 10-20 odd/even ' ...
         'convention or an L/R naming.'], pairing.method));
end

EEG = input;
% REPLACE RATHER THAN APPEND, so Recalculate and template replay are
% idempotent instead of stacking a second Contra bin on the first. Same
% reason DeriveChannels replaces its derived channels.
EEG = dropBinsLabelled(EEG, {options.contraLabel, options.ipsiLabel});

[contra, ipsi] = collapse(input, leftIdx, rightIdx, pairing);
EEG = appendBin(EEG, options.contraLabel, contra, input, leftIdx, rightIdx);
EEG = appendBin(EEG, options.ipsiLabel,   ipsi,   input, leftIdx, rightIdx);

fprintf(['CollapseHemispheres: %d lateral pair(s) by %s, %d midline and %d unpaired ' ...
    'channel(s) left as the two-side mean.\n'], numel(pairing.pairs), pairing.method, ...
    numel(pairing.midline), numel(pairing.unpaired));
end

% ======================================================================= %
function [contra, ipsi] = collapse(EEG, leftIdx, rightIdx, pairing)
%COLLAPSE  The two waveforms, with their standard errors and aSME.
%   Returns a struct each, with .data (nchan x npnts), .stErr and .aSME
%   (nchan x 1), so appendBin has one thing to write per bin.
    nChan = size(EEG.data, 1);
    p = numel(leftIdx);
    q = numel(rightIdx);

    meanL = mean(EEG.data(:, :, leftIdx),  3, 'omitnan');
    meanR = mean(EEG.data(:, :, rightIdx), 3, 'omitnan');

    % Variance contributed by each side, already carrying its 1/(2p) or
    % 1/(2q) coefficient: the mean over that side's bins, then the halving
    % of the two sides.
    % stErr is channels x samples x bins but aSME is channels x bins: one
    % value per bin rather than per sample, so its bin axis is the second.
    [varL, varR]   = sideVariance(EEG, 'stErr', 3, leftIdx, rightIdx, p, q);
    [sVarL, sVarR] = sideVariance(EEG, 'aSME',  2, leftIdx, rightIdx, p, q);

    % Start from the no-laterality value, which is what both waveforms
    % reduce to at a midline or unpaired electrode, then overwrite the pairs.
    contra = struct('data', (meanL + meanR) / 2, ...
        'stErrVar', varL + varR, 'aSMEVar', sVarL + sVarR);
    ipsi = contra;

    for k = 1:numel(pairing.pairs)
        L = pairing.pairs(k).left;
        R = pairing.pairs(k).right;

        % ONE waveform per pair, written to both of its electrodes: see the
        % function header on why the montage is preserved rather than
        % reduced to one channel per pair.
        cData = (meanL(R, :) + meanR(L, :)) / 2;
        iData = (meanL(L, :) + meanR(R, :)) / 2;
        contra.data([L R], :) = [cData; cData];
        ipsi.data([L R], :)   = [iData; iData];

        cVar = varL(R, :) + varR(L, :);
        iVar = varL(L, :) + varR(R, :);
        contra.stErrVar([L R], :) = [cVar; cVar];
        ipsi.stErrVar([L R], :)   = [iVar; iVar];

        cS = sVarL(R) + sVarR(L);
        iS = sVarL(L) + sVarR(R);
        contra.aSMEVar([L R]) = [cS; cS];
        ipsi.aSMEVar([L R])   = [iS; iS];
    end

    contra = finishBin(contra, nChan);
    ipsi   = finishBin(ipsi,   nChan);
end

function [varL, varR] = sideVariance(EEG, field, binDim, leftIdx, rightIdx, p, q)
%SIDEVARIANCE  Sum of squared errors over one side's bins, divided by the
%   square of that side's coefficient. Absent when the dataset carries no
%   such field, in which case the collapsed bins carry none either rather
%   than a fabricated zero.
    if ~isfield(EEG, field) || isempty(EEG.(field))
        varL = [];
        varR = [];
        return;
    end
    v = double(EEG.(field));
    varL = sumSquaresAlong(v, binDim, leftIdx)  / (2 * p) ^ 2;
    varR = sumSquaresAlong(v, binDim, rightIdx) / (2 * q) ^ 2;
end

function s = sumSquaresAlong(v, dim, idx)
%SUMSQUARESALONG  sum(v(...,idx,...).^2, dim), selecting on DIM whichever
%   axis the caller's field keeps its bins on.
    subs = repmat({':'}, 1, max(ndims(v), dim));
    subs{dim} = idx;
    s = sum(v(subs{:}) .^ 2, dim);
end

function b = finishBin(b, nChan)
    b.stErr = sqrt(b.stErrVar);
    b.aSME  = sqrt(b.aSMEVar);
    if ~isempty(b.aSME)
        b.aSME = reshape(b.aSME, nChan, 1);
    end
    b = rmfield(b, {'stErrVar', 'aSMEVar'});
end

% ======================================================================= %
function EEG = appendBin(EEG, label, bin, source, leftIdx, rightIdx)
%APPENDBIN  Add one collapsed bin, extending data/stErr/aSME/bindesc
%   together: a dataset whose data has more bins than its bindesc is one
%   that breaks somewhere downstream rather than here.
    b = size(EEG.data, 3) + 1;
    EEG.data(:, :, b) = bin.data;
    if ~isempty(bin.stErr) && isfield(EEG, 'stErr') && ~isempty(EEG.stErr)
        EEG.stErr(:, :, b) = bin.stErr;
    end
    if ~isempty(bin.aSME) && isfield(EEG, 'aSME') && ~isempty(EEG.aSME)
        EEG.aSME(:, b) = bin.aSME;
    end

    % Built by blanking a copy of an existing descriptor rather than with
    % struct(): bindesc carries different fields depending on how the bins
    % were defined, and a new element with its own field set cannot be
    % assigned into the array at all.
    proto = EEG.bindesc(1);
    for f = fieldnames(proto)'
        proto.(f{1}) = [];
    end
    proto.label = label;
    proto.index = maxBinIndex(EEG.bindesc) + 1;
    proto.n     = contributingCounts(source.bindesc, [leftIdx, rightIdx]);
    EEG.bindesc(b) = proto;
end

function EEG = dropBinsLabelled(EEG, labels)
    keep = ~ismember(binLabelList(EEG.bindesc), labels);
    if all(keep)
        return;
    end
    EEG.data = EEG.data(:, :, keep);
    if isfield(EEG, 'stErr') && ~isempty(EEG.stErr) && size(EEG.stErr, 3) == numel(keep)
        EEG.stErr = EEG.stErr(:, :, keep);
    end
    if isfield(EEG, 'aSME') && ~isempty(EEG.aSME) && size(EEG.aSME, 2) == numel(keep)
        EEG.aSME = EEG.aSME(:, keep);
    end
    EEG.bindesc = EEG.bindesc(keep);
end

function s = contributingCounts(bindesc, idx)
%CONTRIBUTINGCOUNTS  "120+118+131", the trial counts behind a collapsed bin.
%   A count rather than a sum, following Average.m's own convention for a
%   combination bin: the collapsed waveform is not an average over one pool
%   of trials, so a single number would misdescribe it.
    parts = cell(1, numel(idx));
    for k = 1:numel(idx)
        parts{k} = char(string(bindesc(idx(k)).n));
    end
    s = strjoin(parts(~cellfun(@isempty, parts)), '+');
end

function m = maxBinIndex(bindesc)
    m = 0;
    for k = 1:numel(bindesc)
        v = bindesc(k).index;
        if ~isempty(v) && isnumeric(v) && isfinite(v)
            m = max(m, double(v));
        end
    end
end

% ======================================================================= %
function opts = withDefaults(opts)
    if ~isfield(opts, 'pairing') || isempty(opts.pairing)
        opts.pairing = 'auto';
    end
    if ~isfield(opts, 'contraLabel') || isempty(opts.contraLabel)
        opts.contraLabel = 'Contra';
    end
    if ~isfield(opts, 'ipsiLabel') || isempty(opts.ipsiLabel)
        opts.ipsiLabel = 'Ipsi';
    end
    if strcmp(opts.contraLabel, opts.ipsiLabel)
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: the contralateral and ipsilateral ' ...
             'bins would both be called "%s", so one would overwrite the other.'], ...
            opts.contraLabel));
    end
end

function idx = binIndicesFor(wanted, binLabels, side)
%BININDICESFOR  Bin positions for a list of bin LABELS, erroring by name on
%   one that is not there. Stored options name bins rather than numbering
%   them, so replaying a template onto a dataset whose bins were reordered
%   either works or says which bin it wanted, instead of collapsing the
%   wrong two conditions.
    if isempty(wanted)
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: I''m afraid no bin is assigned to the ' ...
             '%s side, and both sides are needed to tell contralateral from ' ...
             'ipsilateral.'], side));
    end
    wanted = cellstr(string(wanted));
    idx = zeros(1, numel(wanted));
    for k = 1:numel(wanted)
        hit = find(strcmp(binLabels, wanted{k}), 1);
        if isempty(hit)
            throw(MException('Alakazam:CollapseHemispheres', ...
                ['Problem in CollapseHemispheres: I''m afraid this dataset has no bin ' ...
                 'called "%s" (its bins are: %s).'], wanted{k}, strjoin(binLabels, ', ')));
        end
        idx(k) = hit;
    end
    if numel(unique(idx)) ~= numel(idx)
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: a bin is listed twice on the %s side, ' ...
             'which would weight it double.'], side));
    end
end

function requireAveragedWithBins(input)
%REQUIREAVERAGEDWITHBINS  Contra and ipsi are defined over bin AVERAGES, so
%   this needs an Average node carrying bins. FieldOr, not a bare field
%   read, because a dataset from an older release may not have DataFormat at
%   all and should get this explanation rather than a field error.
    fmt = char(string(TransTools.FieldOr(input, 'DataFormat', 'not set')));
    if ~strcmpi(fmt, 'Averaged')
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: I''m afraid this needs averaged data ' ...
             'and this dataset is not averaged (DataFormat = "%s"). Collapsing over ' ...
             'hemispheres combines bin AVERAGES, so run Average first.'], fmt));
    end
    if ~isfield(input, 'bindesc') || isempty(input.bindesc)
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: I''m afraid this average carries no bins, ' ...
             'so there is no left-side and right-side condition to collapse. Define ' ...
             'bins (DefineBins) before averaging.']));
    end
    if numel(input.bindesc) < 2
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: I''m afraid this average has only one ' ...
             'bin, and telling contralateral from ipsilateral needs one bin per side.']));
    end
    if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
        throw(MException('Alakazam:CollapseHemispheres', ...
            ['Problem in CollapseHemispheres: I''m afraid this dataset has no channel ' ...
             'list, so left and right electrodes cannot be matched.']));
    end
end

function labels = binLabelList(bindesc)
    labels = arrayfun(@(b) char(string(b.label)), bindesc(:)', 'UniformOutput', false);
end
