function [EEG, opts] = Baseline(input, varargin)
%% Baseline  Subtract each channel's mean over a time window, per trial.
%
%   The window is given in ms and taken to the nearest sample at each end,
%   the earlier one when an end lies exactly halfway between two samples,
%   and an end beyond the epoch is taken to the epoch's first or last sample
%   (TransTools.NearestSample): FieldTrip's rule (ft_preprocessing's
%   baselinewindow, ft_timelockbaseline) and ERPLAB's. A window lying wholly
%   outside the epoch is refused, where FieldTrip would skip the correction.
%   Rejected samples (NaN) inside the window are left out of the mean, as
%   FieldTrip's ft_preproc_baselinecorrect leaves them out, and stay NaN.
%
%   Inputs:
%       input - Struct containing the EEG dataset and related information.
%       opts  - Struct with Start and Stop (ms). If not provided, the
%               options dialog is shown.
%
%   Outputs:
%       EEG   - The baseline-corrected dataset; EEG.etc.alz.baseline records
%               the window as asked (ms) and as used (samples and ms).
%       opts  - The options used.
%
%   TOOLBOX OR OWN CODE. The rule is FieldTrip's and ERPLAB's, so the result
%   is theirs: FieldTripReferenceTest holds it to ft_preprocessing's
%   demean with the same window. It is written out here rather than called
%   because it is one mean and one subtraction over Alakazam's own data
%   layout. EEGLAB's pop_rmbase takes the samples inside the window instead
%   and refuses a window reaching past the epoch, so it would differ by a
%   sample wherever a window's ends fall between samples. This used to take
%   the sample at or before each end, one sample earlier than FieldTrip and
%   ERPLAB for a window starting between samples.

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Baseline', varargin{:});

if ~isfield(input, 'data')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: I''m afraid this dataset has no data at all, so there is nothing to baseline-correct.'));
end

% TransTools.FieldOr, not a bare input.DataFormat: this condition is true when
% the field is ABSENT as well as when it is wrong, and reading it directly then
% throws a raw "Unrecognized field name" from inside the very message meant to
% explain the problem. The format is named rather than assumed to be
% continuous, since the commonest way to reach this is running Baseline on an
% Average node, which is averaged, not continuous.
dataFormat = char(string(TransTools.FieldOr(input, 'DataFormat', 'not set')));
if (length(size(input.data)) < 3 || ~strcmpi(dataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Baseline', sprintf([ ...
        'Problem in Baseline: this needs segmented (epoched) data, and this dataset ' ...
        'is not (DataFormat = "%s"). Please segment it first (e.g. with DefineBins), ' ...
        'then run Baseline on the segmented result -- baseline correction belongs ' ...
        'before Average, not after it.'], dataFormat)));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: I''m afraid this dataset is missing its trial count, so it cannot be treated as segmented data.'));
end

if interactive
    stored = TransformSettings.get('Baseline');
    if isempty(stored)
        stored = struct('Start', -100, 'Stop', 0);
    end
    % The preview draws every channel's average over trials, computed once
    % here rather than on every keystroke.
    butterfly = mean(double(input.data), 3, 'omitnan');
    opts = TransformOptionsDialog(...
        'Description', ['Subtract each channel''s mean over a window, in ms, from the ' ...
            'whole epoch. The shaded band in the preview is the window.'], ...
        'title' , 'Baseline options',...
        'separator' , 'Location:',...
        {'Start'; 'Start'}, stored.Start, ...
        {'Stop'; 'Stop'}, stored.Stop, ...
        {'The window, over every channel''s average'; 'Preview'}, DialogFields.Plot( ...
            @(ax, values) drawWindow(ax, input.times, butterfly, values.Start, values.Stop)));
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
    TransformSettings.set('Baseline', opts);
end

times = double(input.times(:)).';
if opts.Stop < opts.Start
    throw(MException('Alakazam:Baseline', sprintf([ ...
        'Problem in Baseline: the window''s start (%g ms) comes after its stop (%g ms), ' ...
        'I''m afraid. Would you swap them?'], opts.Start, opts.Stop)));
end
[first, last] = TransTools.WindowSamples(times, opts.Start, opts.Stop, 'Alakazam:Baseline', 'baseline window');

EEG = input;
EEG.data = EEG.data - mean(EEG.data(:, first:last, :), 2, 'omitnan');
EEG.etc.alz.baseline = struct('windowMs', [opts.Start, opts.Stop], ...
    'samples', [first, last], 'samplesMs', times([first, last]));
end

% ======================================================================= %
function drawWindow(ax, times, butterfly, startMs, stopMs)
%DRAWWINDOW  The dialog's preview: every channel's average over trials, and
%   the baseline window shaded behind them, so a window that catches the
%   response, or misses the epoch, is seen before it is applied.
    if isempty(times) || size(butterfly, 2) ~= numel(times)
        title(ax, 'No time axis to preview.', 'FontWeight', 'normal', 'FontSize', 9);
        return;
    end
    finite = butterfly(isfinite(butterfly));
    if isempty(finite)
        limits = [-1 1];
    else
        limits = [min(finite), max(finite)];
        if limits(1) == limits(2)
            limits = limits + [-1 1];
        end
    end
    lo = min(startMs, stopMs);
    hi = max(startMs, stopMs);
    patch(ax, [lo hi hi lo], limits([1 1 2 2]), [0.29 0.50 0.79], ...
        'FaceAlpha', 0.18, 'EdgeColor', 'none');
    hold(ax, 'on');
    plot(ax, times, butterfly.', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.5);
    xline(ax, 0, ':');
    hold(ax, 'off');
    xlim(ax, [times(1), times(end)]);
    ylim(ax, limits);
    xlabel(ax, 'ms');
    ylabel(ax, 'uV');
end
