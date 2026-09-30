classdef MultiSelect < DialogFields.LabelList
%MULTISELECT  A list to choose any number of items from, with All and None.
%
%   DialogFields.MultiSelect(ITEMS, SELECTED, Name, Value) takes the options
%   of LabelList. Value: a row cellstr, {} when nothing is chosen. The
%   multiSelectField(...) default that TransformOptionsDialog always
%   accepted becomes one.
%
%   See also DIALOGFIELDS.LABELLIST, MULTISELECTFIELD.
    methods
        function this = MultiSelect(items, selected, varargin)
            if nargin < 2
                selected = {};
            end
            this@DialogFields.LabelList(items, selected, varargin{:});
        end
    end
end
