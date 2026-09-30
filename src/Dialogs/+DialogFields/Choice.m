classdef Choice < DialogFields.Field
%CHOICE  A drop-down of choices.
%
%   DialogFields.Choice(ITEMS, SELECTED, Name, Value) shows ITEMS (a cellstr)
%   with SELECTED chosen, or the first when SELECTED is not among them.
%
%   'Values'  what each item stands for in the options, when that differs
%             from what the user reads (a method named 'Spherical spline'
%             stored as 'spherical'). Defaults to the items themselves.
%             SELECTED may be given as either.
%
%   Value: the chosen item's value, as char.
%
%   A cellstr default passed to TransformOptionsDialog becomes a Choice of
%   those items with the first chosen, which is how every generated dialog
%   has always read one.
%
%   See also DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Items      % cellstr, what is shown
        Values     % cellstr, what is returned
        Selected   % char, the value chosen at first
    end

    properties (Access = private)
        Dropdown
    end

    methods
        function this = Choice(items, selected, varargin)
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('Values', {});
            p.parse(rest{:});

            this.Items = reshape(cellstr(string(items)), 1, []);
            if isempty(this.Items)
                throw(MException('Alakazam:DialogFields', 'A choice needs at least one item.'));
            end
            if isempty(p.Results.Values)
                this.Values = this.Items;
            else
                this.Values = reshape(cellstr(string(p.Results.Values)), 1, []);
            end
            if numel(this.Values) ~= numel(this.Items)
                throw(MException('Alakazam:DialogFields', ...
                    'A choice needs one value per item: %d items, %d values.', ...
                    numel(this.Items), numel(this.Values)));
            end

            this.Selected = this.Values{1};
            if nargin >= 2 && ~isempty(selected)
                pick = char(string(selected));
                if any(strcmp(this.Values, pick))
                    this.Selected = pick;
                elseif any(strcmp(this.Items, pick))
                    this.Selected = this.Values{find(strcmp(this.Items, pick), 1)};
                end
            end
        end

        function build(this, parent, onChange)
            this.Dropdown = this.registerControl(uidropdown(parent, 'Items', this.Items, ...
                'ItemsData', this.Values, 'Value', this.Selected, ...
                'ValueChangedFcn', @(~, ~) onChange()));
        end

        function v = value(this)
            v = char(string(this.Dropdown.Value));
        end
    end
end
