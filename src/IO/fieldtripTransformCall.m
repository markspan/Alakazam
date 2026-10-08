function step = fieldtripTransformCall(transformId, params, ctx, names, why)
%FIELDTRIPTRANSFORMCALL  One step of an Alakazam analysis as FieldTrip code.
%
%   STEP = fieldtripTransformCall(TRANSFORMID, PARAMS, CTX, NAMES) returns
%     .lines    the source lines, reading NAMES.in and assigning NAMES.out
%     .status   how faithful they are:
%                 'exact'        FieldTrip computes what Alakazam computed
%                                (each such translation has a case in
%                                FieldTripExportEquivalenceTest);
%                 'decision'     FieldTrip cannot make this step's choices,
%                                so the script reads back the ones Alakazam
%                                made (which trials, which rejected);
%                 'approximate'  close, with the difference said;
%                 'none'         no FieldTrip counterpart: a marked block,
%                                and the script carries on without the step
%     .summary  a few words for the script's header and the step's comment,
%               the same for every recording run the same way
%     .detail   this recording's own numbers (how many trials, how many
%               components), for the header only, so that recordings run
%               the same way can share one loop in the script
%     .sidecar  what the lines read from the file NAMES.icaFile names, as a
%               struct for writeExportSidecars, or [] when they read none
%   PARAMS are the step's stored options and CTX what fieldtripStepContext
%   read from its input and result. NAMES carries the variable names:
%   .in, .out (FieldTrip data), .trials (the table of trials read from the
%   sidecar), .step (this step's number, naming its column there) and
%   .binColumns (the bin numbers whose membership the trials' trialinfo
%   holds, in column order; set by the DefineBins step), .icaFile (the
%   file an ICA step's decomposition is written to beside the script) and,
%   optionally, .icaCode, the MATLAB expression the script names it by
%   (built from the recording's stem, so that a loop can share it), and
%   .mode: 'reproduce' (the default) or 'rerun' (see EXPORTFIELDTRIPSCRIPT).
%
%   STEP = fieldtripTransformCall(..., WHY) marks the step not translated,
%   for the reason WHY: the assembler's way of refusing a step it cannot
%   place (a second DefineBins, a rejection before any trials were cut).
%
%   WHY SO MUCH IS EXACT. Most of Alakazam's preprocessing is the same
%   arithmetic FieldTrip does, often by the same code: Filter's Kaiser
%   windowed sinc is built by firfilt's firws, windows and kaiserbeta, which
%   FieldTrip ships too (preproc/private), so a low-pass of a given order,
%   cutoff and deviation is one kernel in both, and both apply it zero-phase
%   with the edges padded by the first and last sample. Baseline uses
%   FieldTrip's window rule. A linear derived channel is a weighted sum.
%
%   WHAT IS NOT. A step whose result depends on a choice (the bin language,
%   a threshold detector, a manual rejection, an ICA classification) is
%   carried as that choice (status 'decision'). A step FieldTrip has no
%   counterpart for at all is marked, never imitated: an imitation that
%   nothing checks looks authoritative and can quietly differ, which is the
%   same rule nativeTransformCall follows for the EEGLAB script.
%
%   See also EXPORTFIELDTRIPSCRIPT, FIELDTRIPSTEPCONTEXT, NATIVETRANSFORMCALL.
    if nargin >= 5 && ~isempty(why)
        step = untranslated(transformId, params, names, why);
        return;
    end
    switch char(transformId)
        case 'ReRef'
            step = reref(params, ctx, names);
        case 'DeriveChannels'
            step = derive(params, ctx, names);
        case 'SelectData'
            step = selectData(params, names);
        case 'Filter'
            step = filterStep(params, ctx, names);
        case 'DefineBins'
            step = defineBins(params, ctx, names);
        case 'Baseline'
            step = baseline(params, ctx, names);
        case {'ManualReject', 'ArtefactDetect', 'AutoReject'}
            step = rejection(transformId, ctx, names);
        case 'Average'
            step = average(ctx, names);
        case {'AutoEyeICA', 'RemoveComponents'}
            step = icaStep(transformId, ctx, names);
        otherwise
            step = untranslated(transformId, params, names, '');
    end
end

% ======================================================================= %
function step = result(status, summary, lines, detail, sidecar)
    if nargin < 4
        detail = '';
    end
    if nargin < 5
        sidecar = [];
    end
    step = struct('lines', {lines}, 'status', status, 'summary', summary, 'detail', detail, ...
        'sidecar', sidecar);
end

function lines = preprocessing(cfgLines, names)
%PREPROCESSING  A cfg built by CFGLINES, then ft_preprocessing on it.
    lines = [{'cfg = [];'}, cfgLines, {sprintf('%s = ft_preprocessing(cfg, %s);', names.out, names.in)}];
end

% ======================================================================= %
function step = reref(params, ctx, names)
    implicitRef = strtrim(char(string(TransTools.FieldOr(params, 'implicitRef', ''))));
    exclude = asRow(TransTools.FieldOr(params, 'exclude', {}));
    exclude = exclude(~cellfun(@isempty, exclude));
    if ~isempty(exclude)
        step = untranslated('ReRef', params, names, ['FieldTrip re-references every ' ...
            'channel, and these options leave some out (exclude)']);
        return;
    end
    average = strcmpi(char(string(params.mode)), 'Average');
    cfg = {'cfg.reref = ''yes'';'};
    if average
        cfg{end + 1} = 'cfg.refchannel = ''all'';';
        summary = 'average reference';
    else
        refs = asRow(params.refChannels);
        cfg{end + 1} = sprintf('cfg.refchannel = %s;', matlabLiteral(refs));
        summary = sprintf('reference %s', strjoin(refs, ' and '));
    end
    if ~isempty(implicitRef)
        cfg{end + 1} = sprintf('cfg.implicitref = %s;', matlabLiteral(implicitRef));
        summary = sprintf('%s, %s as the implicit reference', summary, implicitRef);
    end
    lines = preprocessing(cfg, names);
    keep = logical(TransTools.FieldOr(params, 'keepref', false));
    if ~average && ~keep
        % pop_reref drops the reference channels unless asked to keep them.
        refs = asRow(params.refChannels);
        lines = [lines, {'cfg = [];', ...
            sprintf('cfg.channel = %s;', matlabLiteral([{'all'}, strcat('-', refs)])), ...
            sprintf('%s = ft_selectdata(cfg, %s);', names.out, names.out)}];
    end
    step = result('exact', summary, lines);
    if ~isempty(ctx) && strcmp(ctx.format, 'AVERAGED')
        step = untranslated('ReRef', params, names, 'it ran on averaged data');
    end
end

% ======================================================================= %
function step = derive(params, ctx, names)
%DERIVE  Each let statement as a weighted sum of channels, when it is one.
%   The weights are found by running Derive Channels' own parser
%   (TransTools.ApplyDerivations) on probe data: channel k set to a unit
%   impulse at sample k gives each derived channel's weight on channel k,
%   and random data then confirm the statement is linear, with no constant.
    text = char(string(TransTools.FieldOr(params, 'derivations', '')));
    labels = ctx.labels;
    n = numel(labels);
    probe = struct('chanlocs', struct('labels', labels), 'nbchan', n, 'srate', 1, ...
        'trials', 1, 'pnts', n + 5);
    rng0 = RandStream('mt19937ar', 'Seed', 1);
    random = randn(rng0, n, 4);
    probe.data = [eye(n), zeros(n, 1), random];
    try
        [probed, added] = TransTools.ApplyDerivations(probe, text);
    catch err
        step = untranslated('DeriveChannels', params, names, err.message);
        return;
    end
    rows = (n + 1):size(probed.data, 1);
    weights = probed.data(rows, 1:n);
    constant = probed.data(rows, n + 1);
    predicted = weights * random;
    linear = all(abs(constant) < 1e-12) && ...
        all(abs(probed.data(rows, n + 2:end) - predicted) <= 1e-9 * max(1, abs(predicted)), 'all');
    if ~linear
        step = untranslated('DeriveChannels', params, names, ['a statement is not a weighted ' ...
            'sum of channels']);
        return;
    end
    lines = {};
    if ~strcmp(names.in, names.out)
        lines{end + 1} = sprintf('%s = %s;', names.out, names.in);
    end
    for k = 1:numel(added)
        used = find(weights(k, :) ~= 0);
        lines{end + 1} = sprintf('%s = addChannel(%s, %s, %s, %s);', names.out, names.out, ...
            matlabLiteral(added{k}), matlabLiteral(labels(used)), ...
            matlabLiteral(weights(k, used))); %#ok<AGROW>
    end
    textLines = strsplit(strtrim(text), newline);
    lines = [{'% Alakazam''s statements:'}, strcat({'%   '}, textLines), lines];
    step = result('exact', sprintf('derived %s', strjoin(added, ', ')), lines);
end

% ======================================================================= %
function step = selectData(params, names)
    off = @(f) ~isfield(params, f) || strcmp(params.(f).mode, '(off)') || ...
        (strcmp(f, 'trials') && isempty(params.(f).indices));
    if ~(off('time') && off('points') && off('trials'))
        step = untranslated('SelectData', params, names, ['only a selection of channels is ' ...
            'translated so far']);
        return;
    end
    if off('channels')
        step = result('exact', 'nothing selected', {sprintf('%s = %s;', names.out, names.in)});
        return;
    end
    labels = asRow(params.channels.labels);
    if strcmp(params.channels.mode, 'Keep')
        channel = labels;
        summary = sprintf('keep %d channels', numel(labels));
    else
        channel = [{'all'}, strcat('-', labels)];
        summary = sprintf('remove %s', strjoin(labels, ', '));
    end
    step = result('exact', summary, {'cfg = [];', ...
        sprintf('cfg.channel = %s;', matlabLiteral(channel)), ...
        sprintf('%s = ft_selectdata(cfg, %s);', names.out, names.in)});
end

% ======================================================================= %
function step = filterStep(params, ctx, names)
%FILTERSTEP  Each of Filter's windowed-sinc filters as FieldTrip's firws
%   with the same order, cutoff and Kaiser deviation, in Filter's order.
    if logical(TransTools.FieldOr(params, 'perChannel', false))
        step = untranslated('Filter', params, names, 'it filters channels separately');
        return;
    end
    if isfield(params, 'designed') && isstruct(params.designed) && ...
            logical(TransTools.FieldOr(params.designed, 'enabled', false))
        step = untranslated('Filter', params, names, 'it applies a filter from the Filter Designer');
        return;
    end
    if strcmp(ctx.format, 'AVERAGED')
        step = untranslated('Filter', params, names, 'it ran on averaged data');
        return;
    end
    kinds = {'highpass', 'high', 'hp'; 'lowpass', 'low', 'lp'; 'notch', 'notch', 'bs'};
    lines = {};
    parts = {};
    current = names.in;
    for k = 1:size(kinds, 1)
        spec = TransTools.FieldOr(params, kinds{k, 1}, struct('enabled', false));
        if ~logical(TransTools.FieldOr(spec, 'enabled', false))
            continue;
        end
        d = filterDesign(kinds{k, 2}, spec, ctx.srate);
        p = kinds{k, 3};
        if strcmp(p, 'bs')
            edges = d.fc * ctx.srate / 2;
            freq = sprintf('cfg.bsfreq = %s;', matlabLiteral(edges));
            parts{end + 1} = sprintf('band-stop %g to %g Hz', edges(1), edges(2)); %#ok<AGROW>
        else
            freq = sprintf('cfg.%sfreq = %s;', p, num2str(d.freq, '%.10g'));
            parts{end + 1} = sprintf('%s %g Hz', kinds{k, 2}, d.freq); %#ok<AGROW>
        end
        lines = [lines, {'cfg = [];', sprintf('cfg.%sfilter = ''yes'';', p), freq, ...
            sprintf('cfg.%sfilttype = ''firws'';', p), ...
            sprintf('cfg.%sfiltord = %d;', p, d.order), ...
            sprintf('cfg.%sfiltwintype = ''kaiser'';', p), ...
            sprintf('cfg.%sfiltdev = %s;', p, num2str(d.dev, '%.17g')), ...
            sprintf('%s = ft_preprocessing(cfg, %s);', names.out, current)}]; %#ok<AGROW>
        current = names.out;
    end
    if isempty(lines)
        step = result('exact', 'no filter enabled', {sprintf('%s = %s;', names.out, names.in)});
        return;
    end
    step = result('exact', sprintf('Kaiser windowed sinc: %s', strjoin(parts, ', ')), lines);
end

% ======================================================================= %
function step = defineBins(params, ctx, names)
    d = ctx.decision;
    if isempty(d)
        step = result('exact', 'bins tagged, nothing cut', {sprintf('%s = %s;', names.out, names.in)});
        return;
    end
    script = char(string(TransTools.FieldOr(params, 'script', '')));
    columns = arrayfun(@(b) sprintf('bin_%d', b.index), d.bins, 'UniformOutput', false);
    lines = [{'% FieldTrip has no bin language, so the trials Alakazam cut are read back:', ...
        '% each one''s first and last sample and the bins it belongs to. Its bin script:'}, ...
        strcat({'%   '}, strsplit(strtrim(script), newline)), ...
        {'cfg = [];', ...
        sprintf('cfg.trl = [%s.begsample, %s.endsample, %s.offset, %s{:, %s}, %s.trial];', ...
            names.trials, names.trials, names.trials, names.trials, matlabLiteral(columns), names.trials), ...
        sprintf('%s = ft_redefinetrial(cfg, %s);', names.out, names.in)}];
    status = 'decision';
    summary = 'trials and their bins, read from the trial table';
    detail = sprintf('%d trials in %d bins', size(d.membership, 1), numel(d.bins));
    if any(d.epochStart < 1)
        status = 'approximate';
        summary = [summary, '; some trials began before the recording and are padded in Alakazam'];
    end
    step = result(status, summary, lines, detail);
end

% ======================================================================= %
function step = baseline(params, ctx, names)
    if strcmp(ctx.format, 'AVERAGED')
        step = untranslated('Baseline', params, names, 'it ran on averaged data');
        return;
    end
    window = [params.Start, params.Stop] / 1000;
    step = result('exact', sprintf('%g to %g ms', params.Start, params.Stop), ...
        preprocessing({'cfg.demean = ''yes'';', ...
            sprintf('cfg.baselinewindow = %s;', matlabLiteral(window))}, names));
end

% ======================================================================= %
function step = rejection(transformId, ctx, names)
    d = ctx.decision;
    column = sprintf('rejected_%d', names.step);
    lines = {sprintf('%% The trials %s rejected, read back.', transformId), ...
        sprintf('rejected = %s.trial(%s.%s == 1);', names.trials, names.trials, column), ...
        'cfg = [];', ...
        sprintf('cfg.trials = find(~ismember(%s.trialinfo(:, end), rejected));', names.in), ...
        sprintf('%s = ft_selectdata(cfg, %s);', names.out, names.in)};
    status = 'decision';
    summary = 'the rejected trials, read from the trial table';
    detail = sprintf('%d trials rejected', numel(d.rejected));
    if d.partial
        status = 'approximate';
        summary = [summary, '; it also changed channels within trials, which is not carried'];
    end
    step = result(status, summary, lines, detail);
end

% ======================================================================= %
function step = average(ctx, names)
    bins = ctx.decision.bins;
    ordinary = [bins(arrayfun(@(b) isempty(b.combines), bins)).index];
    if isempty(names.binColumns) || ~all(ismember(ordinary, names.binColumns))
        step = untranslated('Average', struct(), names, ['its bins'' trials were not cut by a ' ...
            'DefineBins step this script carries']);
        return;
    end
    lines = {sprintf('binLabels = %s;', matlabLiteral({bins.label})), ...
        sprintf('%s = cell(1, %d);', names.out, numel(bins))};
    for k = 1:numel(bins)
        if isempty(bins(k).combines)
            column = find(names.binColumns == bins(k).index, 1);
            lines = [lines, {'cfg = [];', ...
                sprintf('cfg.trials = find(%s.trialinfo(:, %d));', names.in, column), ...
                sprintf('%s{%d} = ft_timelockanalysis(cfg, %s);', names.out, k, names.in)}]; %#ok<AGROW>
        else
            positions = arrayfun(@(b) find([bins.index] == b, 1), bins(k).combines);
            inputs = strjoin(arrayfun(@(p) sprintf('%s{%d}', names.out, p), positions, ...
                'UniformOutput', false), ', ');
            lines = [lines, {'cfg = [];', 'cfg.parameter = ''avg'';', ...
                sprintf('cfg.operation = %s;', matlabLiteral(operation(bins(k).coeff))), ...
                sprintf('%s{%d} = ft_math(cfg, %s);', names.out, k, inputs)}]; %#ok<AGROW>
        end
    end
    step = result('exact', sprintf('%d bins, %d of them combinations', numel(bins), ...
        nnz(~arrayfun(@(b) isempty(b.combines), bins))), lines);
end

function text = operation(coeff)
%OPERATION  ft_math's expression for a weighted sum of its inputs x1, x2...
    text = '';
    for i = 1:numel(coeff)
        c = coeff(i);
        if i == 1
            sign = '';
            if c < 0, sign = '-'; end
        elseif c < 0
            sign = ' - ';
        else
            sign = ' + ';
        end
        magnitude = abs(c);
        if magnitude == 1
            term = sprintf('x%d', i);
        else
            term = sprintf('%.10g*x%d', magnitude, i);
        end
        text = [text, sign, term]; %#ok<AGROW>
    end
end

% ======================================================================= %
function step = icaStep(transformId, ctx, names)
%ICASTEP  The decomposition the step used and the components it removed, as
%   FieldTrip's ft_componentanalysis with that unmixing matrix and
%   ft_rejectcomponent. ICLabel's classification is not redone: which
%   components went is the decision read back. In a re-run, FieldTrip
%   decomposes the data itself instead (icaRerun).
    d = ctx.decision;
    if strcmp(TransTools.FieldOr(names, 'mode', 'reproduce'), 'rerun')
        step = icaRerun(transformId, d, names);
        return;
    end
    summary = sprintf('the decomposition and the components removed (%s), read back', d.why);
    detail = sprintf('%d of %d components removed', numel(d.removed), size(d.unmixing, 1));
    code = TransTools.FieldOr(names, 'icaCode', '');
    if isempty(code)
        code = matlabLiteral(names.icaFile);
    end
    lines = {sprintf('%% The ICA decomposition %s used and the components it removed (%s).', ...
        transformId, d.why), ...
        sprintf('ica = load(fullfile(here, %s));', code)};
    if isempty(d.removed)
        lines{end + 1} = sprintf('%s = %s;   %% nothing was removed', names.out, names.in);
    else
        lines = [lines, {sprintf('channelOrder = %s.label;', names.in), ...
            'cfg = [];', 'cfg.unmixing = ica.unmixing;', 'cfg.topolabel = ica.topolabel;', ...
            'cfg.demean = ''no'';', sprintf('comp = ft_componentanalysis(cfg, %s);', names.in), ...
            'cfg = [];', 'cfg.component = ica.removed;', ...
            '% ft_rejectcomponent demeans each trial unless told not to; pop_subcomp does not.', ...
            'cfg.demean = ''no'';', ...
            sprintf('%s = ft_rejectcomponent(cfg, comp, %s);', names.out, names.in), ...
            '% ft_rejectcomponent puts the channels it did not decompose last; back in order.', ...
            sprintf('%s = restoreChannelOrder(%s, channelOrder);', names.out, names.out)}];
    end
    status = 'decision';
    if ~d.exact
        status = 'approximate';
        summary = [summary, '; subtracting them does not give Alakazam''s data here, since the ' ...
            'decomposition does not span the data and EEGLAB rebuilt it from the components it kept'];
    end
    step = result(status, summary, lines, detail, struct('unmixing', d.unmixing, ...
        'topolabel', {d.topolabel}, 'removed', d.removed));
end

function step = icaRerun(transformId, d, names)
%ICARERUN  FieldTrip's own ICA, set as Alakazam's was: the same algorithm
%   (FastICA is the same package in both; for extended Infomax, EEGLAB's
%   learning rate, 0.00065/log(channels), where FieldTrip would use 0.001),
%   the same channels and as many components. ICLabel has no counterpart in
%   FieldTrip, so the components removed are those whose topographies match
%   the ones Alakazam removed (matchComponents, carried in the script). ICA
%   is not seeded, so the decomposition is FieldTrip's, not Alakazam's.
    n = size(d.unmixing, 1);
    code = TransTools.FieldOr(names, 'icaCode', '');
    if isempty(code)
        code = matlabLiteral(names.icaFile);
    end
    lines = {sprintf(['%% FieldTrip''s own ICA, with %s''s settings, then the components whose ' ...
        'topographies match'], transformId), ...
        sprintf('%% those Alakazam removed (%s).', d.why), ...
        sprintf('ica = load(fullfile(here, %s));', code), ...
        sprintf('channelOrder = %s.label;', names.in), ...
        'cfg = [];', sprintf('cfg.method = ''%s'';', d.method), 'cfg.channel = ica.topolabel;', ...
        sprintf('cfg.numcomponent = %d;', n)};
    if strcmp(d.method, 'fastica')
        lines = [lines, {sprintf('cfg.fastica.lastEig = %d;', n)}];
        algorithm = 'FastICA';
    else
        lines = [lines, {'cfg.runica.extended = 1;', ...
            'cfg.runica.lrate = 0.00065 / log(numel(ica.topolabel));   % EEGLAB''s own default'}];
        algorithm = 'extended Infomax';
    end
    lines = [lines, {sprintf('comp = ft_componentanalysis(cfg, %s);', names.in), ...
        'remove = matchComponents(comp, ica.templates, ica.topolabel, 0.9);', ...
        'cfg = [];', 'cfg.component = remove;', 'cfg.demean = ''no'';', ...
        sprintf('%s = ft_rejectcomponent(cfg, comp, %s);', names.out, names.in), ...
        sprintf('%s = restoreChannelOrder(%s, channelOrder);', names.out, names.out)}];
    summary = sprintf(['FieldTrip''s own %s (%d components), removing those that match the ' ...
        'removed ones by topography, |r| >= 0.9'], algorithm, n);
    detail = sprintf('Alakazam removed %d (%s)', numel(d.removed), d.why);
    step = result('approximate', summary, lines, detail, struct('topolabel', {d.topolabel}, ...
        'templates', d.templates, 'removed', d.removed));
end

% ======================================================================= %
function step = untranslated(transformId, params, names, why)
%UNTRANSLATED  A step FieldTrip cannot do: marked, its options recorded, and
%   the script carried on without it, with a warning when it runs.
    reason = sprintf('FieldTrip has no counterpart for %s', transformId);
    if ~isempty(why)
        reason = sprintf('not translated: %s', why);
    end
    options = strsplit(matlabLiteral(params), newline);
    lines = [{sprintf('%% NOT TRANSLATED. %s.', capitalise(reason)), ...
        '% Alakazam ran it with these options:'}, strcat({'%   '}, options), ...
        {'% This script carries on without it, so its results differ from Alakazam''s from here on.', ...
        sprintf('warning(''Alakazam:fieldtripExport'', ''Skipped %s (%s): the results differ from Alakazam''''s from here on.'');', ...
            transformId, strrep(reason, '''', ''''''))}];
    if ~strcmp(names.in, names.out)
        lines{end + 1} = sprintf('%s = %s;', names.out, names.in);
    end
    step = result('none', reason, lines);
end

function list = asRow(list)
%ASROW  Labels as a row cellstr, whatever shape jsondecode left them in.
    list = reshape(cellstr(string(list)), 1, []);
    if isequal(list, {''})
        list = {};
    end
end

function text = capitalise(text)
    if ~isempty(text)
        text(1) = upper(text(1));
    end
end
