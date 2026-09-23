function [removed, ok] = RemoveComponentsDialog(icl, icawinv, chanlocs, icaact, srate, dipoleRv)
%REMOVECOMPONENTSDIALOG  Alakazam-styled manual ICA component selector.
%
%   Shows every independent component in a sortable table with the class
%   ICLabel assigned it, that class's probability, the full per-class
%   probabilities and a "Remove" tick-box, alongside a live scalp-topography,
%   activation time-course and power-spectrum preview of the currently
%   selected component, so the user can inspect and remove components by
%   hand (the manual counterpart of AutoEyeICA's automatic eye pruning). This
%   is the EEGLAB pop_selectcomps / pop_subcomp workflow, restyled to the
%   app -- topography alone often cannot settle a borderline muscle, heart or
%   line-noise call; the time course and spectrum are what a user
%   actually reaches for next (pop_prop's own combination), so all three are
%   shown together rather than topography on its own.
%
%   ICL is EEG.etc.ic_classification.ICLabel (fields .classes 1xC cellstr and
%   .classifications ncomp x C). ICAWINV is the component scalp-projection
%   matrix (nchan x ncomp) and CHANLOCS the channels it is indexed over
%   (EEG.chanlocs(EEG.icachansind)). ICAACT is the component activations
%   (ncomp x pnts for continuous data, ncomp x pnts x trials for epoched --
%   EEG.icaact, already guaranteed non-empty by RemoveComponents.m's own
%   ensureDecomposition), and SRATE is EEG.srate (Hz), used to build the
%   time axis and the pwelch frequency axis. Returns REMOVED, a row vector of
%   the component indices to subtract (possibly empty), and OK = true when
%   the user confirmed, or REMOVED = [] and OK = false on cancel.
    [accentColor, bgColor] = dialogChromeColors();
    removed = [];
    ok = false;

    classes = icl.classes(:)';
    probs   = icl.classifications;
    ncomp   = size(probs, 1);

    fig = uifigure('Name', 'Remove ICA components', 'Position', fitOnScreen([100 100 1040 560]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Remove ICA components', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Tick the components to subtract from the data. Select a row to preview ' ...
        'its scalp topography, activation time course and power spectrum. Label is the class ' ...
        'ICLabel assigned (its most probable one), with that probability; the per-class ' ...
        'probabilities (%) follow, because a component labelled at 40% against a close ' ...
        'runner-up is a different proposition from one labelled at 90%. Click a column ' ...
        'heading to sort, to bring all the eye or muscle components together. ' ...
        'Dipole RV is the share of a component''s scalp map that a single equivalent dipole ' ...
        'cannot explain: values above roughly 15% suggest the component is not one cortical ' ...
        'source, and "no fit" means no dipole could be fitted at all, which says so more ' ...
        'strongly still. The column is empty throughout if dipole fitting was unavailable.'], ...
        'WordWrap', 'on');

    middle = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 380}, 'Padding', [0 0 0 0], 'ColumnSpacing', 10);
    middle.Layout.Row = 2;

    % DIPOLE RESIDUAL VARIANCE SITS BESIDE THE ICLABEL PROBABILITIES, not
    % instead of them. It answers a different question -- could ONE dipole
    % have produced this map -- by a physical argument rather than a trained
    % classifier, so the informative case is the two disagreeing: a component
    % ICLabel calls brain but no dipole explains is worth a look. Blank when
    % dipfit could not fit (see ComponentDipoles); componentTableColumns pads
    % a short or absent vector itself.
    if nargin < 6
        dipoleRv = [];
    end

    [colNames, colFmt, colEdit, data] = componentTableColumns(classes, probs, dipoleRv);
    % SORTABLE, so "all the eye components" is one click on the Label heading
    % rather than a read down seven numeric columns. Safe only because
    % componentsTicked reads each row's own IC number instead of its position
    % (see there); with the position assumption a sort would have subtracted
    % the wrong components.
    tbl = uitable(middle, 'ColumnName', colNames, 'ColumnFormat', colFmt, ...
        'ColumnEditable', colEdit, 'Data', data, 'RowName', {}, ...
        'ColumnSortable', true, ...
        'CellSelectionCallback', @(~, ev) onSelect(ev));

    rightPanel = uigridlayout(middle, [3 1], 'RowHeight', {'1x', 130, 130}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 8);

    ax = uiaxes(rightPanel);
    ax.Color = bgColor; title(ax, 'Component topography');
    axis(ax, 'off');

    axTime = uiaxes(rightPanel);
    axTime.Color = bgColor;
    title(axTime, 'Activation (first 10 s)'); xlabel(axTime, 'Time (s)'); ylabel(axTime, '');

    axSpec = uiaxes(rightPanel);
    axSpec.Color = bgColor;
    title(axSpec, 'Power spectrum'); xlabel(axSpec, 'Frequency (Hz)'); ylabel(axSpec, 'Power (dB)');

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0], 'ColumnSpacing', 6);
    buttons.Layout.Row = 3;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    if ncomp >= 1
        drawComponent(1);
    end

    uiwait(fig);

    function onSelect(ev)
    %ONSELECT  Preview the component the clicked row BELONGS TO, read from
    %   the row's own IC cell rather than its position: once the table has
    %   been sorted by Label, row 3 is no longer component 3, and previewing
    %   by position would show a different component from the one ticked.
        if isempty(ev.Indices); return; end
        d = tbl.Data;
        row = ev.Indices(1, 1);
        if row < 1 || row > size(d, 1); return; end
        drawComponent(d{row, 1});
    end

    function drawComponent(ic)
        if ic < 1 || ic > ncomp; return; end
        try
            vals = icawinv(:, ic);
            lim  = max(abs(vals));
            if lim == 0 || isnan(lim); lim = 1; end
            TransTools.DrawScalpMap(ax, vals, chanlocs, lim);
            [~, top] = max(probs(ic, :));
            title(ax, sprintf('IC %d -- %s (%.0f%%)', ic, classes{top}, probs(ic, top) * 100));
        catch err
            cla(ax); axis(ax, 'off');
            title(ax, sprintf('IC %d (no topography: %s)', ic, err.message));
        end
        drawActivation(ic);
    end

    function drawActivation(ic)
    %DRAWACTIVATION  The time-course/spectrum half of the preview: a short
    %   opening snippet (readable at a glance; the whole recording's trace
    %   would be an unreadable smear at this axes size) and a Welch power
    %   spectrum computed from every available sample (epoched data
    %   concatenates its trials first -- more data, a better-resolved
    %   estimate, and a component's spectral shape does not depend on trial
    %   boundaries the way its time course does).
        act = squeeze(icaact(ic, :, :));   % pnts x trials (or a plain pnts x 1 vector when continuous)
        try
            snippet = act(:, 1);
            nShow   = min(numel(snippet), round(10 * srate));
            snippet = snippet(1:nShow);
            t = (0:nShow - 1) / srate;
            plot(axTime, t, snippet, 'Color', accentColor, 'LineWidth', 1);
            xlim(axTime, [0, max(t(end), eps)]);
            title(axTime, 'Activation (first 10 s)');
        catch err
            cla(axTime);
            title(axTime, sprintf('No time course: %s', err.message));
        end
        try
            allSamples = act(:);
            nfft = min(numel(allSamples), max(round(2 * srate), 64));
            [pxx, f] = pwelch(allSamples, hamming(nfft), [], [], srate);
            plot(axSpec, f, 10 * log10(pxx), 'Color', accentColor, 'LineWidth', 1);
            xlim(axSpec, [0, min(80, srate / 2)]);
            title(axSpec, 'Power spectrum');
        catch err
            cla(axSpec);
            title(axSpec, sprintf('No spectrum: %s', err.message));
        end
    end

    function onOK()
        removed = componentsTicked(tbl.Data);
        ok = true;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        removed = [];
        ok = false;
        uiresume(fig); delete(fig);
    end
end
