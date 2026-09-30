classdef LabelList < DialogFields.Field
%LABELLIST  A list of labels to choose from, with one-click selections.
%
%   The common part of the channel and bin pickers, and of a plain
%   multi-select: a list box (or, with 'Multiple' false, a drop-down), and a
%   row of buttons that each select a named subset ("All", "None", "Scalp
%   EEG"). Choices are made, stored and returned BY LABEL, never by index,
%   which is the transformation contract's rule: a stored choice replays on
%   another subject whose montage or bin order differs. A stored label that
%   is not in this dataset is dropped rather than refused, for the same
%   reason.
%
%   DialogFields.LabelList(LABELS, SELECTED, Name, Value) with
%     'Multiple'     true (default): choose any number; false: exactly one
%     'Required'     true: OK is refused while nothing is chosen
%     'QuickSelect'  N x 2 cell of {button text, logical mask over LABELS};
%                    'All' and 'None' are added in front when 'Multiple'
%     'Noun'         what a label is, for the Required message ('channel')
%   Value: a row cellstr when 'Multiple', else char.
%
%   See also DIALOGFIELDS.CHANNELS, DIALOGFIELDS.BINS,
%   DIALOGFIELDS.MULTISELECT.

    properties (SetAccess = protected)
        Labels = {}
        Selected = {}
        Multiple logical = true
        Required logical = false
        QuickSelect = cell(0, 2)
        Noun = 'item'
    end

    properties (Access = protected)
        List
    end

    methods
        function this = LabelList(labels, selected, varargin)
            if nargin < 2
                selected = {};
            end
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('Multiple', true);
            p.addParameter('Required', false);
            p.addParameter('QuickSelect', cell(0, 2));
            p.addParameter('Noun', 'item');
            p.parse(rest{:});

            this.Labels = reshape(cellstr(string(labels)), 1, []);
            this.Multiple = logical(p.Results.Multiple);
            this.Required = logical(p.Results.Required);
            this.Noun = char(p.Results.Noun);
            this.Selected = this.known(selected);
            if ~this.Multiple && isempty(this.Selected) && ~isempty(this.Labels)
                this.Selected = this.Labels(1);
            end

            quick = p.Results.QuickSelect;
            if this.Multiple
                quick = [{'All', true(1, numel(this.Labels)); 'None', false(1, numel(this.Labels))}; quick];
            end
            this.QuickSelect = quick;
        end

        function h = height(this)
            if ~this.Multiple
                h = 28;
                return;
            end
            h = min(160, max(72, 18 * numel(this.Labels) + 8)) + 28;
        end

        function build(this, parent, onChange)
            if ~this.Multiple
                items = this.Labels;
                if isempty(items)
                    items = {''};
                end
                this.List = this.registerControl(uidropdown(parent, 'Items', items, ...
                    'Value', firstOr(this.Selected, items{1}), 'ValueChangedFcn', @(~, ~) onChange()));
                return;
            end

            nButtons = size(this.QuickSelect, 1);
            grid = uigridlayout(parent, [2, max(nButtons, 1)], 'RowHeight', {'1x', 22}, ...
                'ColumnWidth', repmat({'1x'}, 1, max(nButtons, 1)), ...
                'Padding', [0 0 0 0], 'RowSpacing', 4, 'ColumnSpacing', 4);
            this.List = this.registerControl(uilistbox(grid, 'Items', this.Labels, ...
                'Multiselect', 'on', 'Value', this.Selected, 'ValueChangedFcn', @(~, ~) onChange()));
            this.List.Layout.Row = 1;
            this.List.Layout.Column = [1, max(nButtons, 1)];
            for b = 1:nButtons
                mask = logical(this.QuickSelect{b, 2});
                button = this.registerControl(uibutton(grid, 'Text', this.QuickSelect{b, 1}, ...
                    'FontSize', 11, 'ButtonPushedFcn', @(~, ~) this.select(mask, onChange)));
                button.Layout.Row = 2;
                button.Layout.Column = b;
            end
        end

        function v = value(this)
            if this.Multiple
                v = reshape(cellstr(this.List.Value), 1, []);
                if isempty(this.List.Value)
                    v = {};
                end
            else
                v = char(this.List.Value);
            end
        end

        function problem = validate(this)
            problem = '';
            if this.Required && isempty(this.value())
                problem = sprintf('Would you choose at least one %s?', this.Noun);
            end
        end
    end

    methods (Access = protected)
        function chosen = known(this, selected)
        %KNOWN  The stored labels that are in this list, in the list's order.
            if isempty(selected)
                chosen = {};
                return;
            end
            wanted = cellstr(string(selected));
            chosen = this.Labels(ismember(lower(this.Labels), lower(wanted)));
        end

        function select(this, mask, onChange)
        %SELECT  Replace the selection with the labels under MASK.
            this.List.Value = this.Labels(mask);
            onChange();
        end
    end
end

% ======================================================================= %
function v = firstOr(list, fallback)
    if isempty(list)
        v = fallback;
    else
        v = list{1};
    end
end
