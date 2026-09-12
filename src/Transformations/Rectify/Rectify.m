function [EEG, options] = Rectify(input, varargin)
%% Rectify  Replace a channel's signal with its magnitude or its square.
%
%   Full wave is |x|: negatives are mirrored up, which is the rectification
%   step of a classic EMG envelope (rectify, then smooth, then measure).
%   Half wave keeps positives and sets negatives to zero, the other
%   convention in the muscle-recording literature. Squared is x^2.
%
%   SQUARED IS NOT STRICTLY RECTIFICATION, and is here because it belongs to
%   the same step of the same pipelines: both remove sign so that a
%   subsequent average or smooth measures magnitude rather than cancelling.
%   Two things about it differ from the other two modes and are recorded
%   rather than left to be inferred:
%
%     * THE UNIT CHANGES. uV becomes uV^2, which nothing downstream can see
%       by looking at the numbers -- so EEG.etc.alz.rectifySquared says so,
%       and a report or axis label can use it instead of claiming uV.
%     * THE AVERAGING ORDER HAS A STANDARD NAME HERE. Averaging x^2 across
%       trials gives TOTAL power (across-trial variance plus squared mean,
%       so induced activity is included); squaring an average gives EVOKED
%       power, the phase-locked part alone. They differ by exactly the
%       across-trial variance and answer different questions. See
%       orderNote, which names whichever one actually happened.
%
%   WHY THIS IS NOT JUST abs() OR x.^2. Three things a bare expression gets
%   wrong, and the reasons this transformation exists rather than a formula:
%
%   1. RECTIFICATION DOES NOT COMMUTE WITH AVERAGING, and that is the
%      single easiest way to produce a confidently wrong result here:
%      mean(|x|) is not |mean(x)|. Rectifying single trials and then
%      averaging gives a strictly positive envelope whose baseline sits
%      above zero (it accumulates noise magnitude, not signal), which is
%      exactly what an EMG envelope wants and exactly wrong for an ERP.
%      Rectifying an average instead measures the magnitude of the evoked
%      response and nothing else. Both are legitimate; silently allowing
%      either without saying which happened is not. This says which, in
%      the console line and in the recorded provenance below.
%
%   2. A REJECTED SAMPLE MUST STAY REJECTED. Alakazam writes rejection as
%      NaN (see TransTools.InterpolateFlaggedCells for the convention), and
%      abs(NaN) is NaN, so the arithmetic is already safe -- but a rectified
%      channel whose NaNs had been filled would silently re-enter averaging
%      as real data. The counts printed below are computed over finite
%      samples only, so "how much of this channel was actually rectified"
%      is answerable afterwards.
%
%   3. THE RESULT IS NO LONGER A SIGNED VOLTAGE, and nothing downstream can
%      tell by looking. A rectified channel has no meaningful polarity, so
%      peak-to-peak measures, baseline correction and scalp maps all mean
%      something different on it. EEG.etc.alz.rectified records which
%      channels were rectified and how -- the same auditability argument
%      InterpolateFlaggedCells makes for its own mask: a step that changes
%      what the numbers MEAN, while leaving them looking ordinary, has to
%      leave a trace or the data-quality report cannot see it.
%
%   CHANNEL SUBSETTING IS DELIBERATELY NOT OFFERED. BrainVision Analyzer's
%   Rectify dialog carries a "Keep Remaining Channels" option, because it
%   has no general channel-selection step; Alakazam has SelectData (a
%   pop_select front end), so duplicating a destructive channel drop here
%   would be a second way to do the same thing, with its own bugs. Rectify
%   rectifies; SelectData selects.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Rectify(input)        % interactive dialog
%     [EEG, options] = Rectify(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Rectify', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:Rectify', ...
        'Problem in Rectify: I''m afraid this dataset has no data to rectify.'));
end

MODES = {'Full wave (|x|)', 'Half wave (negatives to zero)', 'Squared (x^2)'};

labels = channelLabels(input);
if interactive
    stored = TransformSettings.get('Rectify');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('Channels', {{}}, 'Mode', MODES{1});
    end
    options = TransformOptionsDialog( ...
        'Description', ['Replace the selected channels with their magnitude or their ' ...
            'square. Full wave is |x| (the EMG-envelope convention); half wave keeps ' ...
            'positives and zeroes negatives; squared is x^2, which also changes the unit ' ...
            'to uV^2. Note that doing this to single trials and then averaging is not the ' ...
            'same as doing it to an average -- for squared those are total and evoked ' ...
            'power respectively. Both are recorded, so the choice stays visible ' ...
            'afterwards.'], ...
        'title', 'Rectify options', ...
        'separator', 'Channels to rectify:', ...
        {'Channels'; 'Channels'}, multiSelectField(labels, TransTools.FieldOr(stored, 'Channels', {})), ...
        'separator', 'Rectification:', ...
        {'Mode'; 'Mode'}, TransTools.PutFirst(MODES, TransTools.FieldOr(stored, 'Mode', MODES{1})));
    if isempty(options)
        EEG = [];       % cancelled -- no node, no compute
        options = [];   % the contract is two outputs; both must be assigned
        return;
    end
    if isempty(options.Channels)
        throw(MException('Alakazam:Rectify', ...
            'Problem in Rectify: no channels were selected, so there is nothing to rectify.'));
    end
    TransformSettings.set('Rectify', options);
else
    options = opts;
end

idx = TransTools.LabelsToIdx(input, TransTools.FieldOr(options, 'Channels', {}));
if isempty(idx)
    % A stored selection replayed onto a dataset that has none of those
    % channels: a no-op, not an error -- the same choice Interpolate makes,
    % so a template can cross a montage without stopping the branch.
    fprintf(['Rectify: none of the recorded channels (%s) are in this dataset, ' ...
        'so nothing was rectified.\n'], strjoin(cellstr(string(options.Channels)), ', '));
    EEG = input;
    return;
end

mode = modeOf(TransTools.FieldOr(options, 'Mode', MODES{1}));

EEG = input;
block = EEG.data(idx, :, :);
finiteBefore = isfinite(block);
nNegative = nnz(block < 0 & finiteBefore);
switch mode
    case 'half'
        block(finiteBefore & block < 0) = 0;
    case 'squared'
        block = block .^ 2;
    otherwise
        block = abs(block);
end
EEG.data(idx, :, :) = block;

nTrials = size(input.data, 3);
fprintf('Rectify (%s): %d channel(s), %d of %d finite samples were negative -- %s.\n', ...
    modeName(mode), numel(idx), nNegative, nnz(finiteBefore), orderNote(mode, nTrials));

EEG = recordRectified(EEG, idx, mode, nTrials);
end

% ======================================================================= %
function mode = modeOf(choice)
%MODEOF  'full' | 'half' | 'squared' from the dialog's own wording.
    text = lower(char(string(choice)));
    if startsWith(text, 'half')
        mode = 'half';
    elseif startsWith(text, 'squared') || contains(text, 'x^2')
        mode = 'squared';
    else
        mode = 'full';
    end
end

function name = modeName(mode)
    switch mode
        case 'half';    name = 'half wave';
        case 'squared'; name = 'squared';
        otherwise;      name = 'full wave';
    end
end

function note = orderNote(mode, nTrials)
%ORDERNOTE  Which side of Average this ran on, and what that makes the
%   result -- the wording differs by mode because the consequence does.
%
%   SQUARING IS WHERE THIS MATTERS MOST, and it has a standard name.
%   Averaging x^2 across trials gives TOTAL power: the variance across
%   trials plus the squared mean, so induced (non-phase-locked) activity is
%   included. Squaring an average instead gives EVOKED power, the
%   phase-locked part alone. They answer different questions and differ by
%   exactly the across-trial variance, so which one a number is cannot be
%   left to be inferred from the node's position in the tree.
    if nTrials > 1
        switch mode
            case 'squared'
                note = sprintf(['single-trial data (%d trials): a later Average will give ' ...
                    'TOTAL power (evoked + induced)'], nTrials);
            otherwise
                note = sprintf(['single-trial data (%d trials): a later Average will average ' ...
                    'MAGNITUDES, giving a positive-baseline envelope'], nTrials);
        end
    else
        switch mode
            case 'squared'
                note = 'already-averaged data: this is EVOKED power (phase-locked only)';
            otherwise
                note = 'already-averaged data: the magnitude of the evoked response was taken';
        end
    end
end

% ======================================================================= %
function EEG = recordRectified(EEG, idx, mode, nTrials)
%RECORDRECTIFIED  Note the rectification in EEG.etc.alz.rectified.
%   Written defensively for the same reason InterpolateFlaggedCells writes
%   its own mask that way: EEG.etc is EEGLAB's free-form field and may be
%   absent, empty, or not a struct at all on data that has been through
%   other toolboxes, and none of those may error here.
%
%   OR-ed with any earlier round, so rectifying twice (or rectifying a
%   different channel set later) keeps both records rather than replacing
%   them -- a channel that has been rectified cannot be un-rectified, so the
%   mask only ever grows.
    nChan = size(EEG.data, 1);

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || isempty(EEG.etc)
        EEG.etc = struct();
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz) || isempty(EEG.etc.alz)
        EEG.etc.alz = struct();
    end

    mask = false(1, nChan);
    if isfield(EEG.etc.alz, 'rectified')
        stored = EEG.etc.alz.rectified;
        if islogical(stored) && isequal(size(stored), [1, nChan])
            mask = stored;
        end
        % A stored mask of the wrong width belongs to a differently shaped
        % dataset (a channel edit since it was written), so it is dropped
        % rather than misaligned.
    end
    mask(idx) = true;
    EEG.etc.alz.rectified = mask;

    EEG.etc.alz.rectifyMode = mode;      % 'full' | 'half' | 'squared'
    EEG.etc.alz.rectifiedBeforeAveraging = nTrials > 1;

    % SQUARING CHANGES THE UNIT, which no downstream step can see by
    % looking at the numbers: uV becomes uV^2. Recorded so a report or a
    % later reader can say so rather than labelling a power axis in uV.
    EEG.etc.alz.rectifySquared = strcmp(mode, 'squared');
end

% ======================================================================= %
function labels = channelLabels(EEG)
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'labels')
        labels = cellfun(@(s) char(string(s)), {EEG.chanlocs.labels}, 'UniformOutput', false);
    else
        labels = arrayfun(@(i) sprintf('ch%d', i), 1:size(EEG.data, 1), 'UniformOutput', false);
    end
end
