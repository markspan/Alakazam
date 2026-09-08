function lines = nativeTransformCall(transformId, params, inputVar, outputVar)
%NATIVETRANSFORMCALL  One transformation as direct library calls, or {} when
%   it cannot be one.
%
%   LINES = NATIVETRANSFORMCALL(TRANSFORMID, PARAMS, INPUTVAR, OUTPUTVAR)
%   returns the MATLAB source lines that reproduce the transformation
%   TRANSFORMID, with stored options PARAMS, reading INPUTVAR and assigning
%   OUTPUTVAR. {} means this step has no faithful native spelling and the
%   caller should emit the transformation call itself.
%
%   ITS OWN FILE SO IT CAN BE TESTED. A local function inside
%   exportAnalysisScript could only be reached by generating a whole script
%   and reading the text back, and a native emission nothing can execute
%   against the transformation it replaces is a guess. Here
%   NativeExportEquivalenceTest evals these very lines and compares the
%   result field by field.
%
%   WHAT QUALIFIES. A transformation whose whole compute is a library call
%   over arguments this can spell from the stored options, INCLUDING
%   everything the transformation does around that call. That last clause
%   is the one that bites, twice over. Resample does not stop at
%   pop_resample: it rewrites EEG.times into Alakazam's seconds convention,
%   so the bare call leaves a time axis a factor of 1000 out. And it
%   returns early when the data is already at the requested rate, where
%   pop_resample instead runs and renames the set, adjusts xmax and
%   rewrites times. Both divergences were found by comparing every field;
%   neither is visible in the samples.
%
%   So the emissions below carry their transformation's guards with them.
%   The three-line version of each of these would be shorter and wrong in a
%   case nobody would notice until the numbers were already in a paper.
%
%   WHAT DOES NOT QUALIFY. Filter designs its own Kaiser windowed-sinc
%   kernel from a frequency and a dB rating (transition-band heuristics,
%   firwsord, windows, firws, then per-bin firfilt): emitting that inline
%   would copy the design logic into the script and silently diverge the
%   day Filter.m changed. AutoEyeICA runs ICA, classifies with ICLabel and
%   decides which components to drop from a probability threshold;
%   AutoGEDAI splits the montage, calls GEDAI and splices the result back.
%   A SelectData carrying a time, point or trial range converts units
%   (the dialog collects milliseconds on epoched data, pop_select always
%   wants seconds), and restating a conversion is how two routes quietly
%   disagree. Those keep the transformation call and a comment naming the
%   library that does the work (see exportAnalysisScript's libraryNote).
%
%   See also EXPORTANALYSISSCRIPT, MATLABLITERAL,
%   NATIVEEXPORTEQUIVALENCETEST.
    lines = {};
    if ~isstruct(params) || isempty(params)
        return;
    end
    switch char(transformId)
        case 'Resample'
            lines = resampleCall(params, inputVar, outputVar);
        case 'ReRef'
            lines = rerefCall(params, inputVar, outputVar);
        case 'Interpolate'
            lines = interpolateCall(params, inputVar, outputVar);
        case 'SelectData'
            lines = selectDataCall(params, inputVar, outputVar);
    end
end

% ======================================================================= %
function lines = resampleCall(params, inputVar, outputVar)
%RESAMPLECALL  pop_resample, its no-op guard, and everything Resample.m
%   does to the result: the seconds time axis, and the DataType/DataFormat
%   it normalises (a dataset carrying 'TimeDomain' comes back 'TIMEDOMAIN').
    lines = {};
    if ~isfield(params, 'NewRate') || ~isnumeric(params.NewRate) || ...
            ~isscalar(params.NewRate) || ~isfinite(params.NewRate) || params.NewRate <= 0
        return;
    end
    rate = num2str(params.NewRate, '%.10g');
    lines = { ...
        sprintf('if abs(%s - %s.srate) < eps', rate, inputVar) ...
        sprintf('    %s = %s;   %% already at this rate', outputVar, inputVar) ...
        'else' ...
        sprintf('    %s = pop_resample(%s, %s);', outputVar, inputVar, rate) ...
        sprintf(['    %s.times = ((1:%s.pnts) - 1) / %s.srate;   %% seconds, the ' ...
                 'convention Alakazam keeps continuous time in'], ...
            outputVar, outputVar, outputVar) ...
        sprintf('    %s.DataType = ''TIMEDOMAIN''; %s.DataFormat = ''CONTINUOUS'';', ...
            outputVar, outputVar) ...
        'end' ...
        };
end

% ======================================================================= %
function lines = rerefCall(params, inputVar, outputVar)
%REREFCALL  pop_reref, with the reference resolved from labels.
%   The assert is not decoration: pop_reref reads an empty reference as
%   "average reference" and would silently apply one, which is exactly the
%   case ReRef refuses with an error.
    lines = {};
    if ~isfield(params, 'mode') || isempty(params.mode)
        return;
    end
    keepref = 'off';
    if isfield(params, 'keepref') && ~isempty(params.keepref) && logical(params.keepref)
        keepref = 'on';
    end

    extra = '';
    if isfield(params, 'exclude') && iscell(params.exclude) && ~isempty(params.exclude)
        excludeVar = [outputVar '_exclude'];
        lines = [lines, {labelIndexLine(excludeVar, inputVar, params.exclude)}];
        extra = sprintf(', ''exclude'', %s', excludeVar);
    end

    if strcmpi(params.mode, 'Average')
        refExpression = '[]';
    else
        if ~isfield(params, 'refChannels') || ~iscell(params.refChannels) || ...
                isempty(params.refChannels)
            lines = {};
            return;
        end
        refVar = [outputVar '_ref'];
        lines = [lines, { ...
            labelIndexLine(refVar, inputVar, params.refChannels) ...
            sprintf(['assert(~isempty(%s), ''ReRef: none of the reference channels ' ...
                     'are in this dataset.'');'], refVar)}];
        refExpression = refVar;
    end

    lines = [lines, {sprintf('%s = pop_reref(%s, %s%s, ''keepref'', ''%s'');', ...
        outputVar, inputVar, refExpression, extra, keepref)}];
end

% ======================================================================= %
function lines = interpolateCall(params, inputVar, outputVar)
%INTERPOLATECALL  pop_interp over the channels resolved from labels.
%   Interpolate returns the dataset untouched when none of the stored
%   labels is present, so the guard travels with the call: pop_interp given
%   an empty list leaves the samples alone but still passes the set through
%   eeg_checkset, which is not the same dataset.
    lines = {};
    if ~isfield(params, 'channels') || ~iscell(params.channels) || isempty(params.channels)
        return;
    end
    method = 'spherical';
    if isfield(params, 'method') && ~isempty(params.method)
        method = char(params.method);
    end
    badVar = [outputVar '_bad'];
    lines = { ...
        labelIndexLine(badVar, inputVar, params.channels) ...
        sprintf('if isempty(%s)', badVar) ...
        sprintf('    %s = %s;   %% none of these channels are in this dataset', ...
            outputVar, inputVar) ...
        'else' ...
        sprintf('    %s = pop_interp(%s, %s, ''%s'');', outputVar, inputVar, badVar, method) ...
        'end' ...
        };
end

% ======================================================================= %
function lines = selectDataCall(params, inputVar, outputVar)
%SELECTDATACALL  pop_select, for a CHANNEL selection only.
%   See timeAxisBlock below for the axis restoration that follows the call,
%   and note that it follows the CALL rather than the step: on the no-op
%   path SelectData returns before reaching it.
    lines = {};
    if ~isfield(params, 'channels') || ~isstruct(params.channels) || ...
            ~isfield(params.channels, 'mode') || strcmp(params.channels.mode, '(off)')
        return;
    end
    for other = {'time', 'points', 'trials'}
        f = other{1};
        if isfield(params, f) && isstruct(params.(f)) && isfield(params.(f), 'mode') && ...
                ~strcmp(params.(f).mode, '(off)')
            return;     % more than channels: the transformation keeps it
        end
    end
    if ~isfield(params.channels, 'labels') || ~iscell(params.channels.labels) || ...
            isempty(params.channels.labels)
        return;
    end

    idxVar = [outputVar '_chan'];
    lines = {labelIndexLine(idxVar, inputVar, params.channels.labels)};
    if strcmp(params.channels.mode, 'Keep')
        % Keep with nothing to keep is an error in SelectData, not a no-op,
        % so there is one path here and the time axis follows it.
        lines = [lines, { ...
            sprintf(['assert(~isempty(%s), ''SelectData: none of the channels to keep ' ...
                     'are in this dataset.'');'], idxVar) ...
            sprintf('%s = pop_select(%s, ''channel'', %s);', outputVar, inputVar, idxVar)}];
        lines = [lines, timeAxisBlock(outputVar, '')];
    else
        % Remove with nothing to remove is a no-op, and must stay one. Note
        % where the time-axis block sits: SelectData returns BEFORE it on
        % that path, so a no-op keeps whatever time axis the data had.
        lines = [lines, { ...
            sprintf('if isempty(%s)', idxVar) ...
            sprintf('    %s = %s;   %% none of these channels are in this dataset', ...
                outputVar, inputVar) ...
            'else' ...
            sprintf('    %s = pop_select(%s, ''nochannel'', %s);', outputVar, inputVar, idxVar)}];
        lines = [lines, timeAxisBlock(outputVar, '    '), {'end'}];
    end
end

% ======================================================================= %
function lines = timeAxisBlock(outputVar, pad)
%TIMEAXISBLOCK  SelectData's own restoration of Alakazam's seconds axis.
%   pop_select rewrites EEG.times in milliseconds through eeg_checkset, and
%   Alakazam keeps continuous data in seconds. Whether the data is
%   continuous is a runtime fact, so the condition is emitted rather than
%   decided here.
    lines = { ...
        sprintf('%sif strcmpi(%s.DataFormat, ''CONTINUOUS'')', pad, outputVar) ...
        sprintf(['%s    %s.times = (0:%s.pnts - 1) / %s.srate;   %% seconds, as ' ...
                 'Alakazam keeps continuous time'], pad, outputVar, outputVar, outputVar) ...
        sprintf('%s    %s.xmin = %s.times(1); %s.xmax = %s.times(end);', ...
            pad, outputVar, outputVar, outputVar, outputVar) ...
        sprintf('%send', pad)};
end

% ======================================================================= %
function line = labelIndexLine(varName, inputVar, labels)
%LABELINDEXLINE  The one line every channel-label lookup needs.
%   TransTools.LabelsToIdx is exactly this: a case-insensitive match
%   against EEG.chanlocs, in dataset order. Spelling it out is a
%   translation rather than a re-implementation, and keeps the emitted
%   script free of any Alakazam helper.
    line = sprintf('%s = find(ismember(lower({%s.chanlocs.labels}), lower(%s)));', ...
        varName, inputVar, matlabLiteral(labels(:)'));
end
