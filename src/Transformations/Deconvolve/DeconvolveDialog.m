function options = DeconvolveDialog(EEG, stored)
%DECONVOLVEDIALOG  Modal editor for Deconvolve's settings.
%   OPTIONS = DeconvolveDialog(EEG, STORED) shows the bins to fit, each
%   bin's formula, the response window, the artefact threshold, which event
%   codes outside every bin are modelled, and what comes out, seeded from
%   STORED (a previous run's options, or [] on first use), and returns the
%   options Deconvolve takes, or [] on Cancel.
%
%   THE BINS ARE A SETTING HERE, not a property of the dataset. Deconvolve
%   runs on the continuous recording (see Deconvolve for why it cannot be
%   otherwise), and a continuous recording does not normally carry bins, so
%   "Define bins..." opens DefineBins' own editor, in DefineBins' own
%   language, with its epoch fields hidden because nothing is being cut here.
%   A dataset that does already carry tags is used as it stands until a script
%   is given.
%
%   EACH BIN HAS A FORMULA, typed in Unfold's own notation in the table, one
%   row per bin: 'y ~ 1' by default, or with linear terms, factors (cat),
%   splines (spl, circspl) and interactions. The bins say which events are
%   fitted together; the formula says what explains their response. Beside
%   it is what a formula can use: this recording's event fields, by kind and
%   unit, and the notation itself. Options stored before formulas existed
%   carry a list of covariates instead; those are shown here as the formulas
%   they always meant, and OK stores the formulas.
%
%   IT SHOWS THE MODEL IT WOULD FIT, not just the numbers. The list names
%   every bin with its event count, the columns the toolbox builds for each
%   formula (Unfold.designMatrix on the events alone, so the preview is the
%   same call the fit makes), the nuisance event types, and anything
%   Unfold.binModel has to say about the design (a bin with no events, a
%   field a formula names that a bin's events lack). That is the one thing
%   a user cannot work out from the dialog's fields, and the one thing that
%   decides whether the answer will mean anything. It refreshes when the
%   bins, a formula or the chosen event codes change, because all three
%   change the model.
%
%   OK checks the settings the way Deconvolve will apply them, so a design
%   the fit would refuse is reported here rather than after the dialog closes.
%
%   See also DECONVOLVE, DEFINEBINSDIALOG, UNFOLD.BINMODEL, UNFOLD.FITBINS,
%   UNFOLD.DESIGNMATRIX.
    options = [];

    seed = defaults();
    if isstruct(stored)
        for name = fieldnames(seed)'
            if isfield(stored, name{1}) && ~isempty(stored.(name{1}))
                seed.(name{1}) = stored.(name{1});
            end
        end
    end

    % Which unbinned codes to model, kept out of the generic seeding loop for
    % the same reason as the baseline: an empty list is an answer ("none"),
    % and the loop would read it as absent and restore the default. 'all' is
    % stored as the word, not as today's list of codes, so a replay on another
    % recording still means every code that recording has.
    otherSelection = Unfold.otherEventsChoice(stored);

    % The baseline is stored as the window itself, with [] meaning "leave the
    % betas as the solver returned them", so the checkbox and the two fields
    % are read back out of that one value.
    baselineOn = true;
    baseline = [seed.windowMs(1) 0];
    if isstruct(stored) && isfield(stored, 'baselineMs')
        if isempty(stored.baselineMs)
            baselineOn = false;
        else
            baseline = reshape(double(stored.baselineMs), 1, 2);
        end
    end
    if baseline(1) >= baseline(2)
        baseline = [seed.windowMs(1) seed.windowMs(1) + 100];
        baselineOn = false;     % a window starting at the event has no baseline
    end

    hasTags = datasetCarriesBins(EEG);
    binScript = strtrim(char(string(seed.binScript)));
    if isempty(binScript) && ~hasTags
        % Nothing stored and nothing on the dataset, so the bins have to come
        % from somewhere: the script last run in this workspace is almost
        % certainly the one meant here, since the usual way into this dialog
        % is having already binned and averaged the same recording.
        binScript = lastDefineBinsScript();
    end

    % Every formula typed in this session, by bin label, including those of
    % bins the script no longer has: rewriting the bins and then writing them
    % back should not cost the formulas that went with them.
    remembered = storedFormulas(seed.formulas);
    % The older covariates are turned into formulas once, the first time
    % there are bins to turn them into (see seedFormulaTable).
    legacyCovariates = cellstr(string(seed.covariates));
    if ~isempty(remembered)
        legacyCovariates = {};   % the formulas already say what they meant
    end
    selectedRow = 1;

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Deconvolve', 'Position', fitOnScreen([80 60 1200 900]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Deconvolve: overlapping responses separated', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 44});

    uilabel(outer, 'WordWrap', 'on', 'Text', [ ...
        'Fits every bin at once against the whole continuous recording, so where two events are ' ...
        'close enough for their responses to overlap, each bin keeps its own and gives up the ' ...
        'other''s. The result is one waveform per bin, in the shape Average produces, one ' ...
        'overlap-corrected trial per event, in the shape DefineBins cuts, or one waveform per ' ...
        'term of the model, so the rest of Alakazam reads any of them unchanged.']);

    binsRow = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 130}, 'Padding', [0 4 0 4]);
    binsLabel = uilabel(binsRow, 'WordWrap', 'on', 'Text', '');
    uibutton(binsRow, 'Text', 'Define bins...', 'ButtonPushedFcn', @(~, ~) onDefineBins(), ...
        'Tooltip', 'Write the bins to fit, in DefineBins'' language');

    settings = uigridlayout(outer, [6 4], 'ColumnWidth', {190, 90, 210, 90}, ...
        'RowHeight', repmat({'fit'}, 1, 6), 'Padding', [0 0 0 0], 'RowSpacing', 4);
    uilabel(settings, 'Text', 'Window start (ms):');
    startField = uieditfield(settings, 'numeric', 'Value', seed.windowMs(1));
    uilabel(settings, 'Text', 'Artefact threshold (uV, 0 = off):');
    thresholdField = uieditfield(settings, 'numeric', 'Value', seed.artifactThresholdUv, ...
        'Limits', [0 Inf]);
    uilabel(settings, 'Text', 'Window stop (ms):');
    stopField = uieditfield(settings, 'numeric', 'Value', seed.windowMs(2));
    uilabel(settings, 'Text', 'Measured in a window of (ms):');
    artWindowField = uieditfield(settings, 'numeric', 'Value', seed.artifactWindowMs, ...
        'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
    uilabel(settings, 'Text', 'Baseline start (ms):');
    baseStartField = uieditfield(settings, 'numeric', 'Value', baseline(1));
    uilabel(settings, 'Text', 'Stepped by (ms):');
    artStepField = uieditfield(settings, 'numeric', 'Value', seed.artifactStepMs, ...
        'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
    uilabel(settings, 'Text', 'Baseline stop (ms):');
    baseStopField = uieditfield(settings, 'numeric', 'Value', baseline(2));

    % A beta's zero is wherever the model put it, so a fitted waveform has to
    % be baseline-corrected before it can be read beside an average that
    % Baseline has already corrected. On by default, and the pre-event part of
    % the response window is the default window, as Baseline's own is.
    baselineBox = uicheckbox(settings, 'Text', 'Baseline-correct the result', ...
        'Value', baselineOn, 'ValueChangedFcn', @(~, ~) onBaselineToggled());
    baselineBox.Layout.Row = 4;
    baselineBox.Layout.Column = [3 4];
    onBaselineToggled();

    % What comes out. The waveforms are the same either way (Average of the
    % trials gives them back); the trials are for looking at them one by one
    % and for the noise figures only trials can give; the terms are the
    % model's own view, one waveform per factor level and per value of a
    % continuous term.
    outputLabel = uilabel(settings, 'Text', 'Result:');
    outputLabel.Layout.Row = 5;
    outputLabel.Layout.Column = 1;
    outputDropdown = uidropdown(settings, 'Tag', 'output', ...
        'Items', {'One waveform per bin (as Average gives)', ...
                  'Overlap-corrected trials (as DefineBins cuts)', ...
                  'One waveform per model term'}, ...
        'ItemsData', {'average', 'trials', 'terms'}, 'Value', outputSeed(seed.output), ...
        'ValueChangedFcn', @(~, ~) onOutputChanged(), ...
        'Tooltip', ['Trials hold each event''s recording with every other event''s fitted ' ...
         'response subtracted: run Average on them for the waveforms, and EpochView shows ' ...
         'them as an ERP image without the overlap. Model terms are every factor level and ' ...
         'every continuous or spline term at chosen values, each a whole waveform with the ' ...
         'other terms at their means.']);
    outputDropdown.Layout.Row = 5;
    outputDropdown.Layout.Column = [2 4];
    evaluateLabel = uilabel(settings, 'Text', 'Terms evaluated at:');
    evaluateLabel.Layout.Row = 6;
    evaluateLabel.Layout.Column = 1;
    evaluateField = uieditfield(settings, 'text', 'Tag', 'evaluateAt', ...
        'Value', char(string(seed.evaluateAt)), ...
        'Placeholder', 'e.g. sac_amplitude = 0.5 1 2 4; rt = 300 500', ...
        'Tooltip', ['Where each continuous or spline term is drawn, as "name = values", ' ...
         'separated by semicolons. A term not named here is drawn at five quantiles ' ...
         'of its own values.']);
    evaluateField.Layout.Row = 6;
    evaluateField.Layout.Column = [2 4];
    onOutputChanged();

    % The formulas, the model they make, and what a formula can use share
    % the stretchy row: a formula is only readable next to the columns it
    % turns into and the fields it can name. The right-hand column shares
    % the width rather than taking a fixed strip: its lines (a field with
    % its unit and count, an example formula, an event code with its count)
    % wrapped at every word in a narrow one, and it grows with the window.
    middle = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 10);
    left = uigridlayout(middle, [4 1], 'RowHeight', {'fit', '1x', 'fit', '1.5x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 4);
    formulaHead = uigridlayout(left, [1 2], 'ColumnWidth', {'1x', 130}, 'Padding', [0 0 0 0]);
    uilabel(formulaHead, 'WordWrap', 'on', 'Text', ...
        'What explains each bin''s response, in Unfold''s notation (double-click to edit):');
    uibutton(formulaHead, 'Text', 'Copy to every bin', 'ButtonPushedFcn', @(~, ~) onCopyFormula(), ...
        'Tooltip', 'Give every bin the formula of the row last clicked');
    formulaTable = uitable(left, 'Tag', 'formulas', 'ColumnName', {'Bin', 'Formula'}, ...
        'RowName', {}, 'ColumnEditable', [false true], 'ColumnWidth', {150, 'auto'}, ...
        'Data', cell(0, 2), ...
        'CellEditCallback', @(~, event) onFormulaEdited(event), ...
        'CellSelectionCallback', @(~, event) onFormulaSelected(event));
    uilabel(left, 'Text', 'The model:');
    modelList = uitextarea(left, 'Editable', 'off', 'Value', {''});

    right = uigridlayout(middle, [4 1], 'RowHeight', {'fit', '2x', 'fit', '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 4);
    uilabel(right, 'WordWrap', 'on', 'Text', 'What a formula can use:');
    uitextarea(right, 'Editable', 'off', 'Tag', 'fields', 'Value', fieldReference(EEG));
    uilabel(right, 'WordWrap', 'on', 'Text', 'Events in no bin, modelled and dropped:');
    % A checkbox tree, not a multi-select list box. A list box deselects only
    % with Ctrl+click, and a plain click on the one selected item leaves it
    % selected, so going back to "none" was out of reach in practice. A tick
    % box toggles on a plain click, which is what an optional choice needs.
    otherTree = uitree(right, 'checkbox', 'CheckedNodesChangedFcn', @(~, ~) onOtherEventsChanged(), ...
        'Tooltip', ['Each ticked code gets its own full response, fitted and then dropped, so ' ...
         'its overlap is taken out of the bins. A code with only a handful of events adds a ' ...
         'whole window of parameters for very little.']);

    uilabel(outer, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], 'Text', [ ...
        'The window should cover the whole response, including anything that precedes the event ' ...
        'itself. Bad stretches are left out by ignoring them in the model rather than by dropping ' ...
        'epochs, so an event beside one keeps the rest of its data; the defaults (150 uV in a ' ...
        '2000 ms window, stepped 100 ms) are the toolbox''s own. Events in no bin are worth ' ...
        'modelling: overlap is only removed where it is accounted for, so a response or a ' ...
        'following stimulus left out still overlaps, it just stops being separated out. ' ...
        'The threshold is peak-to-peak within the moving window, and a window that exceeds it ' ...
        'is left out whole, so in reading or free viewing, where eye movements are the task, ' ...
        'it is usually better off (0) with the saccades and blinks modelled instead. A term in ' ...
        'a formula is fitted and held at the same values for every bin that uses it, so a ' ...
        'difference between bins is not one in that term.']);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    cancelButton = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelButton.Layout.Column = 2;
    okButton = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okButton.Layout.Column = 3;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    showModel();
    uiwait(fig);

    function onOutputChanged()
    %ONOUTPUTCHANGED  The values to evaluate at only mean something for the
    %   terms, so the field is only open for them.
        evaluateField.Enable = matlab.lang.OnOffSwitchState(strcmp(outputDropdown.Value, 'terms'));
    end

    % ---- the formulas ------------------------------------------------- %
    function formulas = tableFormulas()
    %TABLEFORMULAS  The formulas as the table shows them, one per bin, read
    %   from the table itself so OK returns what is on screen however it got
    %   there.
        data = formulaTable.Data;
        formulas = struct('bin', {}, 'formula', {});
        for k = 1:size(data, 1)
            formulas(end + 1) = struct('bin', data{k, 1}, 'formula', normalFormula(data{k, 2})); %#ok<AGROW>
        end
    end

    function seedFormulaTable(tagged)
    %SEEDFORMULATABLE  One row per bin that gets fitted, with the formula
    %   typed for it before, if any. Rebuilt only when the bins themselves
    %   change, so an edit does not reset the table under the pointer.
        labels = ordinaryBinLabels(tagged);
        data = formulaTable.Data;
        if ~isempty(data) && isequal(reshape(data(:, 1), 1, []), labels)
            return;
        end
        remember(tableFormulas());
        legacy = legacyFormulas(tagged);
        data = [reshape(labels, [], 1), repmat({'y ~ 1'}, numel(labels), 1)];
        for k = 1:numel(labels)
            hit = find(strcmp({remembered.bin}, labels{k}), 1);
            if ~isempty(hit)
                data{k, 2} = remembered(hit).formula;
            elseif isKey(legacy, labels{k})
                data{k, 2} = legacy(labels{k});
            end
        end
        formulaTable.Data = data;
        onOff = {'off', 'on'};       % a table takes the words, not an OnOffSwitchState
        formulaTable.Enable = onOff{1 + ~isempty(labels)};
        selectedRow = 1;
    end

    function legacy = legacyFormulas(tagged)
    %LEGACYFORMULAS  The formulas stored covariates always meant, by bin:
    %   what Unfold.binModel makes of them, which adds each one only to the
    %   bins whose events carry it and vary in it. Done once, since from
    %   then on the table holds them.
        legacy = containers.Map('KeyType', 'char', 'ValueType', 'char');
        if isempty(legacyCovariates)
            return;
        end
        try
            plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                'Covariates', legacyCovariates);
            for k = 1:numel(plan.typeLabels)
                legacy(plan.typeLabels{k}) = plan.formulas{k};
            end
        catch
            % The bins cannot be fitted as they stand; the model list says why.
        end
        legacyCovariates = {};
    end

    function remember(formulas)
    %REMEMBER  Keep FORMULAS by bin label, replacing any older ones.
        for k = 1:numel(formulas)
            hit = strcmp({remembered.bin}, formulas(k).bin);
            remembered(hit) = [];
            remembered(end + 1) = formulas(k); %#ok<AGROW>
        end
    end

    function onFormulaEdited(event)
    %ONFORMULAEDITED  A formula tidied the way the fit will read it (an
    %   empty one is 'y ~ 1', a missing 'y ~' is added), then the preview.
        row = event.Indices(1);
        formulaTable.Data{row, 2} = normalFormula(event.NewData);
        remember(tableFormulas());
        showModel();
    end

    function onFormulaSelected(event)
        if ~isempty(event.Indices)
            selectedRow = event.Indices(1, 1);
        end
    end

    function onCopyFormula()
    %ONCOPYFORMULA  The formula of the row last clicked, in every row.
        data = formulaTable.Data;
        if isempty(data)
            return;
        end
        row = min(max(selectedRow, 1), size(data, 1));
        data(:, 2) = data(row, 2);
        formulaTable.Data = data;
        remember(tableFormulas());
        showModel();
    end

    % ---- the events in no bin ---------------------------------------- %
    function onOtherEventsChanged()
    %ONOTHEREVENTSCHANGED  The ticks become the choice, then the preview.
        otherSelection = otherTreeSelection();
        showModel();
    end

    function selection = otherTreeSelection()
    %OTHERTREESELECTION  The choice as the ticks show it. Every code ticked is
    %   kept as 'all' rather than as today's list, so a replay on a recording
    %   that has a code this one lacks still models it; anything less is kept
    %   as the codes themselves. Read from the tree, not from a copy, so OK
    %   returns what is on screen whatever route the ticks took to get there.
        selection = otherSelection;
        if strcmpi(otherTree.Enable, 'off')
            return;          % nothing to choose from: the choice stands
        end
        checked = otherTree.CheckedNodes;
        if isempty(checked)
            selection = {};
        elseif numel(checked) == numel(otherTree.Children)
            selection = 'all';
        else
            selection = reshape({checked.NodeData}, 1, []);
        end
    end

    function refreshOtherTree(unbinned)
    %REFRESHOTHERTREE  One tick box per code in no bin, with its count, ticked
    %   when it is modelled. The count is the point: it is what shows that a
    %   code with one event is not worth a whole window of parameters. Rebuilt
    %   only when the codes themselves change, so ticking one does not reset
    %   the list under the pointer.
        if isempty(unbinned)
            delete(otherTree.Children);
            uitreenode(otherTree, 'Text', '(none: every event is in a bin)');
            otherTree.Enable = 'off';
            return;
        end
        labels = arrayfun(@(u) sprintf('%s  (%d event(s))', u.code, u.n), ...
            unbinned, 'UniformOutput', false);
        current = otherTree.Children;
        if strcmpi(otherTree.Enable, 'off') || numel(current) ~= numel(labels) ...
                || ~isequal({current.Text}, reshape(labels, 1, []))
            delete(current);
            for k = 1:numel(unbinned)
                uitreenode(otherTree, 'Text', labels{k}, 'NodeData', unbinned(k).code);
            end
        end
        otherTree.Enable = 'on';
        nodes = otherTree.Children;
        setChecked(otherTree, nodes([unbinned.modelled]));
    end

    % ---- the rest ------------------------------------------------------ %
    function onBaselineToggled()
    %ONBASELINETOGGLED  The two fields follow the checkbox, so an unticked box
    %   cannot leave a window behind that looks as if it were being used.
        state = matlab.lang.OnOffSwitchState(baselineBox.Value);
        baseStartField.Enable = state;
        baseStopField.Enable = state;
    end

    function onDefineBins()
    %ONDEFINEBINS  DefineBins' editor, without its epoching half.
        note = ['These bins are fitted against the continuous recording, so there is no epoch ' ...
                'window to set here: the response window in the Deconvolve dialog behind this ' ...
                'one plays that part. Everything else in the language works as it does in ' ...
                'DefineBins, combination bins ("bin 3 = bin 1 - bin 2") included. A combination ' ...
                'bin is not fitted, since it has no events of its own; this step works it out ' ...
                'afterwards by subtracting the bins it refers to, so it arrives with the rest.'];
        result = DefineBinsDialog(binScript, {'', ''}, ...
            struct('showEpoch', false, 'name', 'Deconvolve: define bins', 'note', note));
        if isempty(result); return; end
        binScript = strtrim(result.script);
        showModel();
    end

    function [tagged, why] = binnedDataset()
    %BINNEDDATASET  The recording with its bins on it, or why there are none.
    %   This is the same call Deconvolve makes, so what the preview lists is
    %   what would be fitted rather than an approximation of it.
        why = '';
        if isempty(binScript)
            tagged = EEG;
            if ~hasTags
                tagged = [];
                why = ['No bins yet. Would you press "Define bins..." and say which events ' ...
                       'each bin holds? This recording carries no bin tags of its own, so ' ...
                       'there is nothing to fit until it does.'];
            end
            return;
        end
        try
            tagged = DefineBins(EEG, struct('script', binScript));
        catch err
            tagged = [];
            why = err.message;
        end
    end

    function showModel()
    %SHOWMODEL  The model as it stands, or why there is not one.
        [tagged, why] = binnedDataset();
        binsLabel.Text = binSourceText();
        if isempty(tagged)
            formulaTable.Data = cell(0, 2);
            formulaTable.Enable = 'off';
            modelList.Value = [{'No model yet:'}, {''}, {why}];
            refreshOtherTree([]);
            return;
        end
        seedFormulaTable(tagged);
        try
            plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                'Formulas', tableFormulas());
            % A code chosen earlier can stop being "in no bin" when the bins
            % change, and would then only produce a note saying it is absent.
            % The list is the user's view of the choice, so the choice follows
            % it: forget codes that are no longer on offer and ask again.
            if iscell(otherSelection)
                available = {plan.unbinnedCodes.code};
                if ~all(ismember(otherSelection, available))
                    otherSelection = intersect(otherSelection, available, 'stable');
                    plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                        'Formulas', tableFormulas());
                end
            end
            refreshOtherTree(plan.unbinnedCodes);
            design = designLines(tagged, plan);
        catch err
            modelList.Value = [{'This design cannot be fitted:'}, {''}, {err.message}];
            return;
        end
        lines = {sprintf('%d bin(s) will be fitted:', numel(plan.binLabels))};
        for k = 1:numel(plan.binLabels)
            lines{end + 1} = sprintf('   %-30s %5d event(s)', plan.binLabels{k}, plan.binCounts(k)); %#ok<AGROW>
        end
        if ~isempty(plan.comboBins)
            lines{end + 1} = '';
            lines{end + 1} = sprintf(['%d difference bin(s) come out of this step too, worked ' ...
                'out here once the fit is done by subtracting the fitted waveforms. Nothing ' ...
                'else has to be run for them.'], numel(plan.comboBins));
        end
        lines = [lines, design];
        if isempty(plan.nuisanceTypes)
            lines{end + 1} = '';
            lines{end + 1} = ['No nuisance events are modelled, so any overlap from events ' ...
                'outside these bins stays in the result.'];
        else
            lines{end + 1} = '';
            lines{end + 1} = sprintf('Nuisance event type(s), fitted and then dropped: %s', ...
                strjoin(strrep(plan.nuisanceTypes, 'evt_', ''), ', '));
        end
        for k = 1:numel(plan.notes)
            lines{end + 1} = ''; %#ok<AGROW>
            lines{end + 1} = ['Note: ' plan.notes{k}]; %#ok<AGROW>
        end
        modelList.Value = lines;
    end

    function text = binSourceText()
    %BINSOURCETEXT  Which of the two possible sources of bins is in use, said
    %   plainly, because the difference decides what the fit means.
        if ~isempty(binScript)
            text = sprintf('Bins: defined here, %d line(s). "Define bins..." to edit them.', ...
                numel(strsplit(binScript, newline)));
        elseif hasTags
            text = sprintf(['Bins: the %d already tagged on this dataset. "Define bins..." ' ...
                'to fit different ones instead.'], numel(EEG.bindesc));
        else
            text = 'Bins: none yet. "Define bins..." to say which events each bin holds.';
        end
    end

    function onOK()
        otherSelection = otherTreeSelection();
        candidate = struct('binScript', binScript, ...
            'formulas', {tableFormulas()}, ...
            'evaluateAt', strtrim(evaluateField.Value), ...
            'windowMs', [startField.Value stopField.Value], ...
            'baselineMs', [], ...
            'otherEvents', {otherSelection}, ...
            'artifactThresholdUv', thresholdField.Value, ...
            'artifactWindowMs', artWindowField.Value, ...
            'artifactStepMs', artStepField.Value, ...
            'output', outputDropdown.Value);
        if candidate.windowMs(1) >= candidate.windowMs(2)
            uialert(fig, 'Would the window start come before its stop?', 'Check the window');
            return;
        end
        if baselineBox.Value
            candidate.baselineMs = [baseStartField.Value baseStopField.Value];
            if candidate.baselineMs(1) >= candidate.baselineMs(2)
                uialert(fig, 'Would the baseline start come before its stop?', ...
                    'Check the baseline');
                return;
            end
            if candidate.baselineMs(1) < candidate.windowMs(1) || ...
                    candidate.baselineMs(2) > candidate.windowMs(2)
                uialert(fig, sprintf(['The baseline window has to sit inside the response ' ...
                    'window (%g to %g ms), since that is the only part that gets fitted.'], ...
                    candidate.windowMs(1), candidate.windowMs(2)), 'Check the baseline');
                return;
            end
        end
        [tagged, why] = binnedDataset();
        if isempty(tagged)
            uialert(fig, why, 'Check the bins');
            return;
        end
        try
            plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                'Formulas', candidate.formulas);
            designLines(tagged, plan);
        catch err
            uialert(fig, err.message, 'Check the design');
            return;
        end
        % The values to evaluate the terms at, read the way the fit reads
        % them and against the same design, so what is refused here is what
        % the fit would refuse. Without the toolbox the fit checks them.
        if strcmp(candidate.output, 'terms') && ~isempty(candidate.evaluateAt) && Unfold.isAvailable()
            try
                designed = quietDesign(tagged, plan);
                Unfold.predictionValues(candidate.evaluateAt, designed.unfold);
            catch err
                uialert(fig, err.message, 'Check the values to evaluate at');
                return;
            end
        end
        options = candidate;
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

% ======================================================================= %
function lines = designLines(tagged, plan)
%DESIGNLINES  The columns the toolbox builds for each bin's formula, from
%   Unfold.designMatrix on the events alone: the same call the fit makes, so
%   a formula it refuses is refused here, naming the bin, and throws. Only
%   bins whose formula is more than 'y ~ 1' are listed, since an intercept
%   is what every bin has anyway. Without the toolbox the formulas have been
%   checked against the events only, which is said.
    lines = {};
    trivial = cellfun(@(f) strcmp(strrep(f, ' ', ''), 'y~1'), plan.formulas);
    if all(trivial)
        return;
    end
    if ~Unfold.isAvailable()
        lines = {'', ['The Unfold toolbox is not installed here, so the formulas are checked ' ...
            'against the events only; the toolbox reads their notation when it fits.']};
        return;
    end
    designed = quietDesign(tagged, plan);
    unfold = designed.unfold;
    lines = {'', 'Each formula, as the toolbox builds it:'};
    nbins = numel(plan.eventTypes) - numel(plan.nuisanceTypes);
    for t = find(~trivial(1:nbins))
        cols = find(unfold.cols2eventtypes == t);
        variableOf = unfold.cols2variablenames(cols);
        parts = {};
        for v = reshape(unique(variableOf, 'stable'), 1, [])
            name = regexprep(unfold.variablenames{v}, '^\d+_', '');
            at = cols(variableOf == v);
            switch unfold.variabletypes{v}
                case 'intercept'
                    parts{end + 1} = 'intercept'; %#ok<AGROW>
                case 'spline'
                    parts{end + 1} = sprintf('%s as a spline (%d columns)', name, numel(at)); %#ok<AGROW>
                case 'categorical'
                    parts{end + 1} = sprintf('%s as a factor (%s)', name, ...
                        strjoin(regexprep(unfold.colnames(at), '^\d+_', ''), ', ')); %#ok<AGROW>
                otherwise
                    parts{end + 1} = sprintf('%s (%s)', name, unfold.variabletypes{v}); %#ok<AGROW>
            end
        end
        lines{end + 1} = sprintf('   %s: %s', plan.typeLabels{t}, strjoin(parts, '; ')); %#ok<AGROW>
        lines{end + 1} = sprintf('      %s', plan.formulas{t}); %#ok<AGROW>
    end
end

function designed = quietDesign(tagged, plan) %#ok<INUSD>  plan is read inside evalc
%QUIETDESIGN  Unfold.designMatrix on the events alone, without the progress
%   lines uf_designmat prints on every call: the preview reruns it on every
%   edit, and the command window is for the fit's own narration.
    stub = struct('event', tagged.event, 'srate', tagged.srate, 'pnts', tagged.pnts); %#ok<NASGU>
    designed = [];
    evalc('designed = Unfold.designMatrix(stub, plan);');
end

function formula = normalFormula(formula)
%NORMALFORMULA  A formula as the fit reads it: an empty one is 'y ~ 1', and
%   one without its left-hand side gets 'y ~ ' (Unfold.binModel does the
%   same, so this only makes the table show what will be fitted).
    formula = strtrim(char(string(formula)));
    if isempty(formula)
        formula = 'y ~ 1';
    elseif ~contains(formula, '~')
        formula = ['y ~ ' formula];
    end
end

function formulas = storedFormulas(stored)
%STOREDFORMULAS  Stored formulas as a struct array of .bin and .formula,
%   whatever shape a template gave them.
    formulas = struct('bin', {}, 'formula', {});
    if ~isstruct(stored) || ~all(isfield(stored, {'bin', 'formula'}))
        return;
    end
    for k = 1:numel(stored)
        formulas(end + 1) = struct('bin', char(string(stored(k).bin)), ...
            'formula', normalFormula(stored(k).formula)); %#ok<AGROW>
    end
end

function labels = ordinaryBinLabels(EEG)
%ORDINARYBINLABELS  The bins that are fitted, in order: every bin but the
%   combination ones, which are worked out from the others after the fit.
    labels = {};
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    combo = false(1, numel(EEG.bindesc));
    if isfield(EEG.bindesc, 'combo')
        combo = arrayfun(@(b) ~isempty(b.combo), EEG.bindesc);
    end
    labels = reshape(cellstr(string({EEG.bindesc(~combo).label})), 1, []);
end

function lines = fieldReference(EEG)
%FIELDREFERENCE  The event fields a formula can name, by what they can be,
%   and the notation, so a formula can be written without leaving the
%   dialog. Numbers come from Unfold.eventCovariates, which knows EYE-EEG's
%   units and which of them are angles; text fields with a handful of
%   values are the factors.
    lines = {};
    found = Unfold.eventCovariates(EEG);
    linear = found(strcmpi({found.kind}, 'linear'));
    circular = found(~strcmpi({found.kind}, 'linear'));
    if ~isempty(linear)
        lines = [lines, {'Numbers (a term, or spl):'}, ...
            arrayfun(@fieldItem, linear, 'UniformOutput', false)];
    end
    if ~isempty(circular)
        lines = [lines, {'', 'Angles (circspl):'}, ...
            arrayfun(@fieldItem, circular, 'UniformOutput', false)];
    end
    factors = textFields(EEG);
    if ~isempty(factors)
        lines = [lines, {'', 'Text (cat):'}, ...
            arrayfun(@(f) sprintf('   %s, %d levels', f.name, f.levels), factors, ...
            'UniformOutput', false)];
    end
    if isempty(lines)
        lines = {'(no event field a formula could use)'};
    end
    lines = [lines, {'', 'The notation:', ...
        '   y ~ 1   the bin''s own waveform', ...
        '   y ~ 1 + rt   plus a straight line in rt', ...
        '   y ~ 1 + spl(rt, 5)   a smooth curve, 5 splines', ...
        '   y ~ 1 + cat(side)   a factor, its first level the reference', ...
        '   y ~ 1 + cat(side) * rt   a factor, rt, and their interaction', ...
        '   circspl(angle, 5, 0, 360)   a curve round a circle', ...
        '', 'A bin''s events must all carry every field its formula names.'}];
end

function text = fieldItem(candidate)
    text = ['   ' candidate.name];
    if ~isempty(candidate.unit)
        text = sprintf('%s (%s)', text, candidate.unit);
    end
    text = sprintf('%s, n = %d', text, candidate.n);
end

function fields = textFields(EEG)
%TEXTFIELDS  Event fields holding text with between 2 and 20 distinct
%   values: the ones cat() can make a factor of. More than that is a label
%   per event (a word, a file name), not a condition. The fields that place
%   and tag the events are left out, as Unfold.eventCovariates leaves them.
    fields = struct('name', {}, 'levels', {});
    if ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end
    skip = {'type', 'latency', 'duration', 'urevent', 'bini', 'epoch'};
    for name = reshape(fieldnames(EEG.event), 1, [])
        if any(strcmpi(name{1}, skip))
            continue;
        end
        values = {EEG.event.(name{1})};
        values = values(~cellfun(@isempty, values));
        if isempty(values) || ~all(cellfun(@(v) ischar(v) || (isstring(v) && isscalar(v)), values))
            continue;
        end
        levels = numel(unique(cellfun(@char, values, 'UniformOutput', false)));
        if levels >= 2 && levels <= 20
            fields(end + 1) = struct('name', name{1}, 'levels', levels); %#ok<AGROW>
        end
    end
end

% ======================================================================= %
function setChecked(tree, nodes)
%SETCHECKED  Tick exactly NODES in a checkbox tree. "Nothing ticked" has to
%   be the plain [] rather than an empty array of tree nodes: CheckBoxTree
%   rejects the latter as not being children of the tree, and indexing the
%   children with a mask that matches nothing produces exactly that, so the
%   dialog failed to open whenever nothing was stored.
    if isempty(nodes)
        tree.CheckedNodes = [];
    else
        tree.CheckedNodes = nodes;
    end
end

% ======================================================================= %
function tf = datasetCarriesBins(EEG)
%DATASETCARRIESBINS  Bins already on the recording, tags and all.
    tf = isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc) ...
        && isfield(EEG, 'event') && ~isempty(EEG.event) && isfield(EEG.event, 'bini');
end

function script = lastDefineBinsScript()
%LASTDEFINEBINSSCRIPT  The script last run through DefineBins in this
%   workspace, as a starting point. It is only a seed: it is shown in the
%   editor and can be changed or cleared there before anything is fitted.
    script = '';
    stored = TransformSettings.get('DefineBins');
    if isstruct(stored) && isfield(stored, 'script')
        script = strtrim(char(string(stored.script)));
    end
end

function seed = defaults()
%DEFAULTS  First-run settings: the paper's window and the toolbox's own
%   artefact parameters, with nuisance events modelled because leaving them
%   out quietly weakens the correction the transformation exists for.
%   covariates is only read, from options stored before formulas existed.
    seed = struct('binScript', '', 'covariates', {{}}, ...
        'formulas', {struct('bin', {}, 'formula', {})}, 'evaluateAt', '', ...
        'windowMs', [-200 800], 'artifactThresholdUv', 150, ...
        'artifactWindowMs', 2000, 'artifactStepMs', 100, 'output', 'average');
end

function value = outputSeed(stored)
%OUTPUTSEED  A stored output choice the dropdown can show: anything it does
%   not offer (a hand-edited template, say) falls back to the waveforms,
%   which is what Deconvolve itself does with it.
    value = lower(char(string(stored)));
    if ~any(strcmp(value, {'average', 'trials', 'terms'}))
        value = 'average';
    end
end
