function options = DeconvolveDialog(EEG, stored)
%DECONVOLVEDIALOG  Modal editor for Deconvolve's settings.
%   OPTIONS = DeconvolveDialog(EEG, STORED) shows the bins to fit, the
%   response window, the artefact threshold, the covariates, and which event
%   codes outside every bin are modelled, seeded from STORED (a previous
%   run's options, or [] on first use), and returns the options Deconvolve
%   takes, or [] on Cancel.
%
%   THE BINS ARE A SETTING HERE, not a property of the dataset. Deconvolve
%   runs on the continuous recording (see Deconvolve for why it cannot be
%   otherwise), and a continuous recording does not normally carry bins, so
%   "Define bins..." opens DefineBins' own editor, in DefineBins' own
%   language, with its epoch fields hidden because nothing is being cut here.
%   A dataset that does already carry tags is used as it stands until a script
%   is given.
%
%   IT SHOWS THE MODEL IT WOULD FIT, not just the numbers. The list names
%   every bin with its event count, the nuisance event types, and anything
%   Unfold.binModel has to say about the design (a bin with no events, a pair
%   whose timing never varies so their responses cannot be told apart). That
%   is the one thing a user cannot work out from the dialog's fields, and the
%   one thing that decides whether the answer will mean anything. It refreshes
%   when the bins, the covariates or the chosen event codes change, because
%   all three change the model.
%
%   OK checks the settings the way Deconvolve will apply them, so a design
%   the fit would refuse is reported here rather than after the dialog closes.
%
%   See also DECONVOLVE, DEFINEBINSDIALOG, UNFOLD.BINMODEL, UNFOLD.FITBINS.
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
    otherSelection = storedOtherEvents(stored);

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

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Deconvolve', 'Position', fitOnScreen([120 120 660 620]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Deconvolve: overlapping responses separated', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 44});

    uilabel(outer, 'WordWrap', 'on', 'Text', [ ...
        'Fits every bin at once against the whole continuous recording, so where two events are ' ...
        'close enough for their responses to overlap, each bin keeps its own and gives up the ' ...
        'other''s. The result is either one waveform per bin, in the shape Average produces, or ' ...
        'one overlap-corrected trial per event, in the shape DefineBins cuts, so the rest of ' ...
        'Alakazam reads either unchanged.']);

    binsRow = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 130}, 'Padding', [0 4 0 4]);
    binsLabel = uilabel(binsRow, 'WordWrap', 'on', 'Text', '');
    uibutton(binsRow, 'Text', 'Define bins...', 'ButtonPushedFcn', @(~, ~) onDefineBins(), ...
        'Tooltip', 'Write the bins to fit, in DefineBins'' language');

    settings = uigridlayout(outer, [5 4], 'ColumnWidth', {190, 90, 210, 90}, ...
        'RowHeight', repmat({'fit'}, 1, 5), 'Padding', [0 0 0 0], 'RowSpacing', 4);
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
    % and for the noise figures only trials can give.
    outputLabel = uilabel(settings, 'Text', 'Result:');
    outputLabel.Layout.Row = 5;
    outputLabel.Layout.Column = 1;
    outputDropdown = uidropdown(settings, 'Tag', 'output', ...
        'Items', {'One waveform per bin (as Average gives)', ...
                  'Overlap-corrected trials (as DefineBins cuts)'}, ...
        'ItemsData', {'average', 'trials'}, 'Value', outputSeed(seed.output), ...
        'Tooltip', ['Trials hold each event''s recording with every other event''s fitted ' ...
         'response subtracted. Run Average on them for the waveforms, and EpochView shows ' ...
         'them as an ERP image without the overlap.']);
    outputDropdown.Layout.Row = 5;
    outputDropdown.Layout.Column = [2 4];

    % The model preview and the covariate picker share the stretchy row: the
    % picker is only meaningful next to the model it changes, since what a
    % covariate does here is visible only as the formula each bin is fitted
    % with, which the preview lists.
    middle = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 220}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    modelList = uitextarea(middle, 'Editable', 'off', 'Value', {''});
    picker = uigridlayout(middle, [4 1], 'RowHeight', {'fit', '1x', 'fit', '1x'}, ...
        'Padding', [0 0 0 0]);
    uilabel(picker, 'WordWrap', 'on', 'Text', 'Covariates (optional):');
    % Checkbox trees, not multi-select list boxes. A list box deselects only
    % with Ctrl+click, and a plain click on the one selected item leaves it
    % selected, so going back to "none" was out of reach in practice: the
    % reported symptom was a covariate that could not be unselected. A tick
    % box toggles on a plain click, which is what an optional choice needs.
    covariateTree = uitree(picker, 'checkbox', 'CheckedNodesChangedFcn', @(~, ~) showModel());
    uilabel(picker, 'WordWrap', 'on', 'Text', 'Events in no bin, modelled and dropped:');
    otherTree = uitree(picker, 'checkbox', 'CheckedNodesChangedFcn', @(~, ~) onOtherEventsChanged(), ...
        'Tooltip', ['Each ticked code gets its own full response, fitted and then dropped, so ' ...
         'its overlap is taken out of the bins. A code with only a handful of events adds a ' ...
         'whole window of parameters for very little.']);
    fillCovariates();

    uilabel(outer, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], 'Text', [ ...
        'The window should cover the whole response, including anything that precedes the event ' ...
        'itself. Bad stretches are left out by ignoring them in the model rather than by dropping ' ...
        'epochs, so an event beside one keeps the rest of its data; the defaults (150 uV in a ' ...
        '2000 ms window, stepped 100 ms) are the toolbox''s own. Events in no bin are worth ' ...
        'modelling: overlap is only removed where it is accounted for, so a response or a ' ...
        'following stimulus left out still overlaps, it just stops being separated out. ' ...
        'Each code is listed with its count, so a code with one or two events, which adds a ' ...
        'whole window of parameters for almost nothing, can be left unticked. ' ...
        'The threshold is peak-to-peak within the moving window, and a window that exceeds it ' ...
        'is left out whole, so in reading or free viewing, where eye movements are the task, ' ...
        'it is usually better off (0) with the saccades and blinks modelled instead.']);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    cancelButton = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelButton.Layout.Column = 2;
    okButton = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okButton.Layout.Column = 3;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    showModel();
    uiwait(fig);

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

    function fillCovariates()
    %FILLCOVARIATES  What this recording can offer, with the circular ones
    %   left out: an angle cannot be entered as a slope (359 degrees sits
    %   next to 1 and nowhere near 180), and the honest treatment is a
    %   sine/cosine pair rather than a tick box, so they are named as
    %   unavailable rather than quietly offered.
        found = Unfold.eventCovariates(EEG);
        linear = found(strcmpi({found.kind}, 'linear'));
        delete(covariateTree.Children);
        if isempty(linear)
            uitreenode(covariateTree, 'Text', '(no numeric event fields)');
            covariateTree.Enable = 'off';
            return;
        end
        stored = cellstr(string(seed.covariates));
        for k = 1:numel(linear)
            uitreenode(covariateTree, 'Text', covariateItem(linear(k)), 'NodeData', linear(k).name);
        end
        nodes = covariateTree.Children;
        setChecked(covariateTree, nodes(ismember({linear.name}, stored)));
        circular = found(~strcmpi({found.kind}, 'linear'));
        if ~isempty(circular)
            covariateTree.Tooltip = sprintf(['Not offered, being circular: %s. An angle ' ...
                'needs a sine/cosine pair, not a slope.'], strjoin({circular.name}, ', '));
        end
    end

    function text = covariateItem(candidate)
        text = candidate.name;
        if ~isempty(candidate.unit)
            text = sprintf('%s (%s)', text, candidate.unit);
        end
        text = sprintf('%s, n = %d', text, candidate.n);
    end

    function names = chosenCovariates()
    %CHOSENCOVARIATES  The ticked covariates, read from the tree itself.
        names = {};
        if strcmpi(covariateTree.Enable, 'off')
            return;
        end
        checked = covariateTree.CheckedNodes;
        if ~isempty(checked)
            names = reshape({checked.NodeData}, 1, []);
        end
    end

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
            modelList.Value = [{'No model yet:'}, {''}, {why}];
            refreshOtherTree([]);
            return;
        end
        try
            plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                'Covariates', chosenCovariates());
            % A code chosen earlier can stop being "in no bin" when the bins
            % change, and would then only produce a note saying it is absent.
            % The list is the user's view of the choice, so the choice follows
            % it: forget codes that are no longer on offer and ask again.
            if iscell(otherSelection)
                available = {plan.unbinnedCodes.code};
                if ~all(ismember(otherSelection, available))
                    otherSelection = intersect(otherSelection, available, 'stable');
                    plan = Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                        'Covariates', chosenCovariates());
                end
            end
        catch err
            modelList.Value = [{'This design cannot be fitted:'}, {''}, {err.message}];
            return;
        end
        refreshOtherTree(plan.unbinnedCodes);
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
        if ~isempty(plan.covariates)
            lines{end + 1} = '';
            for k = 1:numel(plan.covariates)
                cov = plan.covariates(k);
                lines{end + 1} = sprintf(['Covariate "%s": fitted on %d event(s) in %d type(s), ' ...
                    'centred on %.4g, then dropped.'], cov.name, cov.n, numel(cov.types), ...
                    cov.centre); %#ok<AGROW>
            end
            lines{end + 1} = sprintf('Each bin is fitted as: %s', plan.formulas{1});
        end
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
            'covariates', {chosenCovariates()}, ...
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
            Unfold.binModel(tagged, 'OtherEvents', otherSelection, ...
                'Covariates', candidate.covariates);
        catch err
            uialert(fig, err.message, 'Check the design');
            return;
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
function setChecked(tree, nodes)
%SETCHECKED  Tick exactly NODES in a checkbox tree. "Nothing ticked" has to
%   be the plain [] rather than an empty array of tree nodes: CheckBoxTree
%   rejects the latter as not being children of the tree, and indexing the
%   children with a mask that matches nothing produces exactly that, so the
%   dialog failed to open whenever no covariate was stored.
    if isempty(nodes)
        tree.CheckedNodes = [];
    else
        tree.CheckedNodes = nodes;
    end
end

% ======================================================================= %
function selection = storedOtherEvents(stored)
%STOREDOTHEREVENTS  The stored choice of unbinned codes: 'all', or a cellstr
%   (empty meaning none). Options saved before the choice was per code carry
%   only modelOtherEvents, and false there still means none.
    selection = 'all';
    if ~isstruct(stored)
        return;
    end
    if isfield(stored, 'otherEvents')
        value = stored.otherEvents;
        if isempty(value)
            selection = {};
        elseif ischar(value) && strcmpi(value, 'all')
            selection = 'all';
        else
            selection = reshape(cellstr(string(value)), 1, []);
        end
    elseif isfield(stored, 'modelOtherEvents') && ~isempty(stored.modelOtherEvents) ...
            && ~logical(stored.modelOtherEvents)
        selection = {};
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
    seed = struct('binScript', '', 'covariates', {{}}, 'windowMs', [-200 800], ...
        'artifactThresholdUv', 150, ...
        'artifactWindowMs', 2000, 'artifactStepMs', 100, 'output', 'average');
end

function value = outputSeed(stored)
%OUTPUTSEED  A stored output choice the dropdown can show: anything but
%   'trials' (a hand-edited template, say) falls back to the waveforms, which
%   is what Deconvolve itself does with it.
    value = 'average';
    if strcmpi(char(string(stored)), 'trials')
        value = 'trials';
    end
end
