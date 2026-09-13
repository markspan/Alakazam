function [opts, ok] = CollapseHemispheresDialog(binLabels, chanlocs, stored)
%COLLAPSEHEMISPHERESDIALOG  Ask which bins are left-side and which are
%   right-side, and show which electrode pairs were found.
%
%   BINLABELS is the dataset's bin labels in order, CHANLOCS its channel
%   list (used only to report the pairing, never changed), and STORED the
%   previously used options or [] on a first run. Returns OPTS as
%   CollapseHemispheres documents it, and OK = false on cancel.
%
%   THE SIDE ASSIGNMENT IS THE ONE THING ONLY THE ANALYST KNOWS. Which bin
%   holds left-side stimuli, or a left-hand response, is a fact about the
%   experiment and about the event codes; nothing in the data says it, and
%   guessing it from a bin label would invert contra and ipsi whenever the
%   guess was wrong -- an error that produces a plausible-looking waveform
%   of the opposite sign, which is the worst kind.
%
%   THE PAIRING IS SHOWN, NOT ASKED. It is derived (TransTools.LateralPairs)
%   and the analyst cannot usefully choose the pairs themselves, but they do
%   need to see how many were found and which electrodes were left out
%   before trusting the result: an equidistant montage with no locations
%   filled in can silently yield nothing to collapse.
%
%   See also COLLAPSEHEMISPHERES, TRANSTOOLS.LATERALPAIRS.
    [accentColor, bgColor] = dialogChromeColors();
    opts = [];
    ok = false;

    binLabels = cellstr(string(binLabels(:)'));
    if nargin < 3 || isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    sideOf = storedSides(stored, binLabels);

    fig = uifigure('Name', 'Collapse hemispheres', ...
        'Position', fitOnScreen([100 100 720 520]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Collapse hemispheres', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], ...
        'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], ...
        'RowHeight', {'fit', '1x', 'fit', 'fit', 'fit', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Mark each bin by the side its stimulus appeared on, or the ' ...
        'hand that responded. Contralateral then means the opposite hemisphere to that ' ...
        'side, collapsed over both: contra = (left-side bins at right electrodes + ' ...
        'right-side bins at left electrodes) / 2, and ipsilateral the converse. Bins ' ...
        'left as "ignore" take no part. Each side is averaged before the two are, so ' ...
        'the sides weigh equally however many bins each has.'], 'WordWrap', 'on');

    tbl = uitable(outer, 'ColumnName', {'Bin', 'Side'}, ...
        'ColumnFormat', {'char', {'ignore', 'Left', 'Right'}}, ...
        'ColumnEditable', [false true], 'RowName', {}, ...
        'Data', [binLabels(:), sideOf(:)]);

    pairRow = uigridlayout(outer, [1 2], 'ColumnWidth', {160, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uilabel(pairRow, 'Text', 'Pair electrodes by', 'VerticalAlignment', 'center');
    pairing = uidropdown(pairRow, 'Items', {'auto', 'geometry', 'labels'}, ...
        'Value', storedChoice(stored, 'pairing', 'auto', {'auto', 'geometry', 'labels'}), ...
        'ValueChangedFcn', @(~, ~) refreshPairs());

    report = uilabel(outer, 'Text', '', 'WordWrap', 'on');

    nameRow = uigridlayout(outer, [1 4], 'ColumnWidth', {160, '1x', 120, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uilabel(nameRow, 'Text', 'Name the new bins', 'VerticalAlignment', 'center');
    contraField = uieditfield(nameRow, 'Value', ...
        storedText(stored, 'contraLabel', 'Contra'));
    uilabel(nameRow, 'Text', 'and', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'center');
    ipsiField = uieditfield(nameRow, 'Value', storedText(stored, 'ipsiLabel', 'Ipsi'));

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [0 4 0 0], 'ColumnSpacing', 6);
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshPairs();
    uiwait(fig);

    function refreshPairs()
        try
            p = TransTools.LateralPairs(chanlocs, pairing.Value);
        catch err
            report.Text = sprintf('Could not pair electrodes: %s', err.message);
            return;
        end
        if isempty(p.pairs)
            report.Text = ['No left electrode could be matched to a right one, so there ' ...
                'is nothing to collapse. Fill in the channel locations (Channel ' ...
                'editor), or check that the labels follow the 10-20 odd/even ' ...
                'convention or an L/R naming.'];
            return;
        end
        shown = min(numel(p.pairs), 8);
        names = strjoin(arrayfun(@(q) q.label, p.pairs(1:shown), ...
            'UniformOutput', false), ', ');
        if shown < numel(p.pairs)
            names = sprintf('%s and %d more', names, numel(p.pairs) - shown);
        end
        report.Text = sprintf(['%d pair(s) by %s: %s. %d midline and %d unpaired ' ...
            'channel(s) have no laterality to collapse and will carry the plain ' ...
            'mean of the two sides.'], numel(p.pairs), p.method, names, ...
            numel(p.midline), numel(p.unpaired));
    end

    function onOK()
        d = tbl.Data;
        sides = d(:, 2);
        left  = binLabels(strcmp(sides, 'Left'));
        right = binLabels(strcmp(sides, 'Right'));
        % Refused here rather than thrown from the transform, so the analyst
        % can fix it in the dialog they are already looking at.
        if isempty(left) || isempty(right)
            uialert(fig, ['Mark at least one bin as Left and one as Right: telling ' ...
                'contralateral from ipsilateral needs both sides.'], ...
                'Both sides are needed');
            return;
        end
        if strcmp(strtrim(contraField.Value), strtrim(ipsiField.Value))
            uialert(fig, 'The two bins need different names, or one would overwrite the other.', ...
                'Same name twice');
            return;
        end
        opts = struct( ...
            'leftBins',    {left(:)'}, ...
            'rightBins',   {right(:)'}, ...
            'pairing',     pairing.Value, ...
            'contraLabel', strtrim(contraField.Value), ...
            'ipsiLabel',   strtrim(ipsiField.Value));
        ok = true;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        opts = [];
        ok = false;
        uiresume(fig); delete(fig);
    end
end

% ======================================================================= %
function sides = storedSides(stored, binLabels)
%STOREDSIDES  Re-seed each bin's side from the last run, matched BY LABEL.
%   Stored options name bins rather than numbering them, so a remembered
%   assignment still lands on the right bin after one is added or reordered
%   -- and a bin the stored options do not mention starts at "ignore"
%   rather than inheriting whatever sat in that position before.
    sides = repmat({'ignore'}, 1, numel(binLabels));
    sides(ismember(binLabels, namedBins(stored, 'leftBins')))  = {'Left'};
    sides(ismember(binLabels, namedBins(stored, 'rightBins'))) = {'Right'};
end

function names = namedBins(stored, field)
    names = {};
    if isfield(stored, field) && ~isempty(stored.(field))
        names = cellstr(string(stored.(field)));
    end
end

function v = storedChoice(stored, field, default, allowed)
    v = default;
    if isfield(stored, field) && ~isempty(stored.(field))
        candidate = char(string(stored.(field)));
        if any(strcmp(candidate, allowed))
            v = candidate;
        end
    end
end

function v = storedText(stored, field, default)
    v = default;
    if isfield(stored, field) && ~isempty(stored.(field))
        v = char(string(stored.(field)));
    end
end
