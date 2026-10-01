function spec = pickDesignedFilter(srate)
%PICKDESIGNEDFILTER  Choose a filter exported from MATLAB's Filter Designer.
%   SPEC = pickDesignedFilter(SRATE) lists the digitalFilter variables in
%   the MATLAB workspace, where the Filter Designer exports a filter by
%   default (Export > Digital Filter Object), and offers to read more from a
%   MAT-file the app saved. The chosen one comes back as Filter stores it
%   (designedFilterFromObject), or [] on Cancel. One designed for another
%   sample rate than SRATE, the data's, is refused here, with the reason,
%   rather than later by the step. One designed in normalised frequency is
%   read at SRATE, and the details say where its band edges then lie.
%
%   See also DESIGNEDFILTERFROMOBJECT, FILTERDIALOG, FILTERDESIGNER.
    spec = [];
    [accentColor, bgColor] = dialogChromeColors();
    candidates = workspaceFilters();

    fig = uifigure('Name', 'Use a designed filter', 'Position', fitOnScreen([150 150 560 250]), ...
        'Color', bgColor, 'WindowStyle', 'modal');
    grid = uigridlayout(fig, [4 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit'}, 'Padding', [12 12 12 12]);
    uilabel(grid, 'WordWrap', 'on', 'Text', sprintf([ ...
        'Filters exported from the Filter Designer (Export > Digital Filter Object) to the MATLAB ' ...
        'workspace, or saved there in a MAT-file. The data are sampled at %g Hz: the filter has ' ...
        'to have been designed for that rate, or in normalised frequency, which is then read ' ...
        'at it.'], srate));
    choice = uidropdown(grid, 'Tag', 'DesignedFilterChoice');
    details = uilabel(grid, 'WordWrap', 'on', 'Text', '', 'Tag', 'DesignedFilterDetails');
    buttons = uigridlayout(grid, [1 5], 'ColumnWidth', {130, 80, '1x', 80, 80}, 'Padding', [0 0 0 0]);
    uibutton(buttons, 'Text', 'From a MAT-file...', 'ButtonPushedFcn', @(~, ~) onFromFile());
    uibutton(buttons, 'Text', 'Refresh', 'ButtonPushedFcn', @(~, ~) onRefresh());
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'Use', 'Tag', 'UseDesignedFilter', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onUse());
    fig.CloseRequestFcn = @(~, ~) onCancel();
    choice.ValueChangedFcn = @(~, ~) showDetails();
    refreshChoice();
    uiwait(fig);

    function refreshChoice()
        if isempty(candidates)
            choice.Items = {'(no digitalFilter in the workspace)'};
            choice.ItemsData = 0;
            choice.Enable = 'off';
        else
            choice.Items = cellfun(@summary, {candidates.name}, {candidates.object}, 'UniformOutput', false);
            choice.ItemsData = 1:numel(candidates);
            choice.Enable = 'on';
        end
        showDetails();
    end

    function showDetails()
        if isempty(candidates)
            details.Text = 'Design a filter in the Filter Designer and export it, then press Refresh.';
            return;
        end
        obj = candidates(choice.Value).object;
        if obj.NormalizedFrequency
            details.Text = sprintf(['Designed in normalised frequency, so it will be read at the ' ...
                'data''s %g Hz: a normalised frequency w lies at w x %g Hz. It keeps that rate ' ...
                'when it is replayed.'], srate, srate / 2);
        elseif abs(obj.SampleRate - srate) > 1e-6
            details.Text = sprintf('This one was designed for %s, not for %g Hz, and cannot be used here.', ...
                rateText(obj), srate);
        else
            details.Text = 'Designed for the data''s sample rate.';
        end
    end

    function onRefresh()
        candidates = [workspaceFilters(), fileOnly(candidates)];
        refreshChoice();
    end

    function onFromFile()
        [file, folder] = uigetfile('*.mat', 'A MAT-file with a digitalFilter in it');
        figure(fig);
        if isequal(file, 0)
            return;
        end
        loaded = load(fullfile(folder, file));
        names = fieldnames(loaded);
        found = 0;
        for k = 1:numel(names)
            if isa(loaded.(names{k}), 'digitalFilter')
                candidates(end + 1) = struct('name', sprintf('%s: %s', file, names{k}), ...
                    'object', loaded.(names{k}), 'fromFile', true); %#ok<AGROW>
                found = found + 1;
            end
        end
        if found == 0
            uialert(fig, sprintf('There is no digitalFilter in %s.', file), 'Nothing to use');
            return;
        end
        refreshChoice();
        choice.Value = numel(candidates);
        showDetails();
    end

    function onUse()
        if isempty(candidates)
            return;
        end
        picked = candidates(choice.Value);
        try
            candidate = designedFilterFromObject(picked.object, picked.name, srate);
        catch err
            uialert(fig, err.message, 'Cannot use this filter');
            return;
        end
        if abs(candidate.srate - srate) > 1e-6
            uialert(fig, sprintf(['"%s" was designed for %g Hz, and the data are sampled at %g Hz, ' ...
                'so its cutoffs would land elsewhere. Would you design it again for %g Hz?'], ...
                picked.name, candidate.srate, srate, srate), 'Another sample rate');
            return;
        end
        spec = candidate;
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

% ======================================================================= %
function candidates = workspaceFilters()
%WORKSPACEFILTERS  Every digitalFilter in the MATLAB (base) workspace.
    candidates = struct('name', {}, 'object', {}, 'fromFile', {});
    vars = evalin('base', 'whos');
    for k = 1:numel(vars)
        if strcmp(vars(k).class, 'digitalFilter')
            candidates(end + 1) = struct('name', vars(k).name, ...
                'object', evalin('base', vars(k).name), 'fromFile', false); %#ok<AGROW>
        end
    end
end

function kept = fileOnly(candidates)
    kept = candidates([candidates.fromFile]);
end

function text = summary(name, obj)
    text = sprintf('%s: %s %s, order %d, %s', name, upper(char(string(obj.ImpulseResponse))), ...
        char(string(obj.FrequencyResponse)), filtord(obj), rateText(obj));
end

function text = rateText(obj)
    if obj.NormalizedFrequency
        text = 'normalised frequency';
    else
        text = sprintf('%g Hz', obj.SampleRate);
    end
end
