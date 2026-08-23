function [EEG, options] = DefineBins(input, varargin)
%% DefineBins  Assign events to ERP bins with an event-selection language.
%
% DefineBins replaces the ERPLAB EVENTLIST + BINLISTER step with a small,
% readable event-selection language. Each statement defines one bin as a
% predicate over the events in the recording; every event that satisfies the
% predicate becomes a time-locked point for that bin. Nothing is reshaped
% here (the data stays CONTINUOUS): DefineBins only tags events with their
% bin membership, so a later EpochBins step can cut the epochs and an
% AverageBins step can average per bin.
%
% Signature (Alakazam transformation contract):
%   [EEG, options] = DefineBins(input)        % interactive: prompt for a script
%   [EEG, options] = DefineBins(input, opts)  % replay: opts is a stored struct
%
% The returned OPTIONS struct carries .script (the text the analyst typed) and
% .bins (the compiled query plan). On replay the compiled plan is evaluated
% directly against the new dataset's events - no re-parsing, no eval of text.
%
% The language itself (lexer, parser, evaluator, epoch cutter) lives in
% @DefineBinsEngine, one method per file, alongside this transformation
% (src/Transformations/DefineBins/); the modal script editor lives in
% src/Dialogs/DefineBinsDialog.m, matching every other transformation's own
% dialog. This file stays the callable transformation itself, orchestrating
% the two: the plugin contract dispatches transformations with
% feval('DefineBins', ...), which needs a plain function returning
% [EEG, options], not a class.
%
%% LANGUAGE
%
% One statement per bin (the ':' after the label is optional):
%
%   bin <n> "<label>" : <expr>
%
% <expr> is a boolean combination (and / or / not, grouped with parentheses;
% 'and' between two adjacent terms is optional) of two kinds of terms, both
% evaluated relative to a candidate event e:
%
%   * anchor     a marker code (or set of codes), true when e's own marker
%                matches one of them. Codes are integers (112) or quoted text
%                markers ("S112"); a quoted marker may use wildcards, ? for
%                any single character and * for any run ("s??" matches s + two
%                characters). A set of alternatives is written either
%                pipe-separated (112|122) or as a braced list, which reads
%                well for many markers: {"s11" "s22" "s33" "s44"} (elements
%                separated by spaces and/or commas). Both forms may be used
%                anywhere a code appears, including inside next(...)/any(...).
%
%   * relation   a constraint on a neighbouring event, measured as a signed
%                delay from e (positive = later):
%                   next(code)                the nearest following event of
%                                             that code (skipping others)
%                   prev(code)                the nearest preceding event
%                   adjacent(code)            the immediately next event must
%                                             be that code
%                   any(code) within (lo,hi]  some event of that code exists
%                                             in the window
%                Any relation may be constrained by a window:
%                   ... within (200,1200] ms
%                Interval notation is explicit about open/closed bounds and
%                takes an optional unit (ms, the default; samples; or events,
%                an ordinal count in the event stream instead of elapsed time
%                -- within [-2,-2] events means "exactly two events before",
%                immune to jitter in the interval itself, e.g. from variable
%                RTs). Windows are signed, so [-1200,-200) means "before".
%
% The epoch window to cut around every matched event is NOT part of this
% script language -- it is a separate parameter, .epoch (a struct with
% .lo/.hi/.unit), passed alongside the script rather than written as a
% statement inside it: interactively, the "Epoch start (ms)"/"Epoch stop
% (ms)" fields above the script editor in the DefineBins dialog;
% programmatically, struct('script', ..., 'epoch', struct('lo', -200,
% 'hi', 800, 'unit', 'ms')). It applies to ALL bins (they share one
% window). With it, DefineBins returns a segmented (channels x time x
% trials) dataset that plots in EpochView; without it (both fields left
% blank) the data stays continuous and only the bin tags are added.
%
% Example (the N400-style case: a target whose response falls in a plausible
% reaction-time window; the epoch window itself, e.g. -200 to 800 ms, is set
% separately as described above, not written into the script):
%
%   bin 1 "Related"   : 112 and next(118) within (200,1200] ms
%   bin 2 "Unrelated" : 122 and next(118) within (200,1200] ms
%   bin 3 "No response": (112|122) and not next(118) within (0,2000] ms
%
% Lines beginning with % or # are comments. See bin_language.md for the full
% reference.
%
%% RESULT
%
% Adds to EEG:
%   EEG.bindesc(b) : struct per bin with fields index, label, script, plan,
%                    events (indices into EEG.event), rt (per-event delay to
%                    the captured neighbour, ms; NaN when none), n, and - once
%                    epoched - trials (indices into the epoch stack).
%   EEG.event(i).bini : row vector of bin numbers this event belongs to
%                    (ERPLAB-style; an event may be in several bins).
% With an .epoch window (see above) it also segments EEG.data into
% channels x time x trials, sets DataFormat = 'EPOCHED', fills EEG.times and
% EEG.epoch (one entry per trial, tagged with its bins).
%
% See also: Epoch, Segmentation, Average, DEFINEBINSENGINE, DEFINEBINSDIALOG.

    %% Guard input
    if nargin < 1
        throw(MException('Alakazam:DefineBins', ...
            ['I''m afraid DefineBins needs a dataset to work on, and none was given ' ...
             'here. This usually happens when it''s called directly rather than run ' ...
             'from the Alakazam gallery (or dragged onto a dataset) -- would you try ' ...
             'that instead?']));
    end

    EEG = input;

    %% Mode: interactive (Init) or replay (stored options struct)
    % nargin is already known >= 1 (see the guard above), so InitGuard's own
    % "no dataset" check never fires here -- this call only supplies the
    % opts-default-to-'Init'/interactive-flag half of what it does, kept
    % separate from DefineBins' own more specific "needs a dataset" message.
    [options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DefineBins', varargin{:});

    if interactive
        template = [ ...
            '% Codes are markers; ? = any char; { } lists alternatives; | is or.'              newline ...
            '% Relations: next(c) prev(c) adjacent(c) any(c) within (lo,hi] ms/samples/events.' newline ...
            '% let names a reusable expression (codes or relations); = makes a difference bin.' newline ...
            'let related = {"s11" "s22" "s33" "s44" "s55"}'                                    newline ...
            'bin 1 "Related"    related           and next("S201") within (200,1200] ms'       newline ...
            'bin 2 "Unrelated"  "s??" not related and next("S201") within (200,1200] ms'       newline ...
            'bin 3 "Effect"     = bin 1 - bin 2' ];

        % Prefill with the last script and epoch bounds run in this workspace
        % (see TransformSettings), falling back to the built-in template on
        % first use.
        stored = TransformSettings.get('DefineBins');
        if isempty(stored); stored = struct(); end
        if isfield(stored, 'script'); default = stored.script; else; default = template; end
        if isfield(stored, 'epochStart')
            prevEpoch = {stored.epochStart, stored.epochStop};
        else
            prevEpoch = {'-200', '800'};
        end

        result = DefineBinsDialog(default, prevEpoch);
        if isempty(result)
            throw(MException('Alakazam:DefineBins', ...
                'That''s quite alright -- you cancelled the DefineBins dialog, so nothing has been changed.'));
        end

        script   = result.script;
        epochWin = DefineBinsEngine.parseEpochBounds(result.start, result.stop);   % may throw parse errors
        spec     = DefineBinsEngine.parseSpec(script);                            % may throw parse errors

        % Remember the epoch bounds regardless of whether the script itself
        % turns out to be valid -- a typo in the script is no reason to
        % discard separately-fine epoch bounds -- but both are only reached
        % (and so only remembered) once parseSpec above has already
        % succeeded, so in practice they are always saved together.
        stored.script     = script;
        stored.epochStart = result.start;
        stored.epochStop  = result.stop;
        TransformSettings.set('DefineBins', stored);

        options = struct('script', script, 'bins', spec.bins, 'epoch', epochWin);
    elseif isstruct(options) && isfield(options, 'script') && ~isfield(options, 'bins')
        % Script mode: parse a supplied script without a dialog (for scripting
        % and tests). Optionally carries an 'epoch' window struct.
        script = char(options.script);
        spec   = DefineBinsEngine.parseSpec(script);
        if isfield(options, 'epoch'); epochWin = options.epoch; else; epochWin = []; end
        options = struct('script', script, 'bins', spec.bins, 'epoch', epochWin);
    else
        if ~isstruct(options) || ~isfield(options, 'bins')
            throw(MException('Alakazam:DefineBins', ...
                ['DefineBins was asked to replay a previous run, but I''m afraid the ' ...
                 'stored settings it was given do not look like ones DefineBins itself ' ...
                 'produced (there is no .bins field). This should not normally happen ' ...
                 'from the gallery or drag-and-drop; if you are calling DefineBins ' ...
                 'programmatically, would you pass either the char/string it should ' ...
                 'parse as a script (struct(''script'', ...)), or the exact options ' ...
                 'struct DefineBins previously returned?']));
        end
        spec.bins = options.bins;
        if isfield(options, 'epoch'); epochWin = options.epoch; else; epochWin = []; end
    end
    bins = spec.bins;

    if isempty(bins)
        throw(MException('Alakazam:DefineBins', ...
            ['Your script does not define any bins, I''m afraid, so there is nothing ' ...
             'for DefineBins to do just yet. Would you add at least one line like:' newline newline ...
             '    bin 1 "My first bin" 112' newline newline ...
             '(a bin number, a quoted label, then which events belong to it).']));
    end

    %% Validate events
    if ~isfield(EEG, 'event') || isempty(EEG.event) ...
            || ~isfield(EEG.event, 'type') || ~isfield(EEG.event, 'latency')
        throw(MException('Alakazam:DefineBins', ...
            ['This dataset has no usable events for DefineBins to match against, ' ...
             'I''m afraid (EEG.event is empty, or missing the .type/.latency fields ' ...
             'every event needs). Would you check that the recording was imported ' ...
             'with its event markers intact, and that no earlier step removed them?']));
    end

    %% Match every bin's predicate against every event, and tag EEG.event
    [EEG, bindesc, centerLat] = DefineBinsEngine.evaluateBins(EEG, bins);

    %% Cut epochs when an epoch window was given (dialog), so the result plots
    %  as an epoched dataset (EpochView). Without it, the data stays continuous
    %  and only the bin tags are added.
    if ~isempty(epochWin)
        [EEG, bindesc] = DefineBinsEngine.cutEpochs(EEG, bindesc, epochWin, centerLat);
    end
    EEG.bindesc = bindesc;

    %% Interactive summary
    if interactive
        reportBins(bindesc, EEG);
    end
end

function reportBins(bindesc, EEG)
%REPORTBINS  Post-run summary popup (interactive mode only): per-bin match
%   counts and mean reaction times, plus the resulting segmentation shape.
    lines = strings(0, 1);
    for b = 1:numel(bindesc)
        d = bindesc(b);
        valid = ~isnan(d.rt);
        if any(valid)
            rtStr = sprintf('  (mean delay %.0f ms)', mean(d.rt(valid)));
        else
            rtStr = '';
        end
        lines(end+1) = sprintf('bin %d "%s": %d events%s', ...
            d.index, d.label, d.n, rtStr); %#ok<AGROW>
    end
    if isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'EPOCHED')
        lines(end+1) = sprintf('--> segmented: %d epochs x %d samples', ...
            EEG.trials, EEG.pnts); %#ok<AGROW>
    end
    helpdlg(char(strjoin(lines, newline)), 'DefineBins: bins created');
end
