classdef Bins < DialogFields.LabelList
%BINS  A bin picker: the dataset's bins by label, with All, None and, where
%   there are any, Difference bins.
%
%   DialogFields.Bins(SOURCE, SELECTED, Name, Value)
%     SOURCE    the dataset (an EEG struct with bindesc), its bindesc, or a
%               cellstr of labels
%     SELECTED  the labels chosen at first; one not in this dataset is
%               dropped
%   takes the options of LabelList ('Multiple', 'Required'), plus
%     'Differences'  false to leave the difference (combination) bins out
%                    of the list, for a step that needs trials behind every
%                    bin (default true)
%   Value: the chosen labels, a row cellstr (or char with 'Multiple' false).
%
%   See also DIALOGFIELDS.CHANNELS, DIALOGFIELDS.LABELLIST.
    methods
        function this = Bins(source, selected, varargin)
            if nargin < 2
                selected = {};
            end
            [withDifferences, rest] = takeOption(varargin, 'Differences', true);
            [labels, isDifference] = DialogFields.Bins.binsOf(source);
            if ~withDifferences
                labels = labels(~isDifference);
                isDifference = isDifference(~isDifference);
            end
            extra = {};
            if any(isDifference) && ~any(strcmpi(rest(1:2:end), 'QuickSelect'))
                extra = {'QuickSelect', {'Differences', isDifference}};
            end
            this@DialogFields.LabelList(labels, selected, 'Noun', 'bin', extra{:}, rest{:});
        end
    end

    methods (Static, Access = private)
        function [labels, isDifference] = binsOf(source)
        %BINSOF  The bin labels, and which are difference bins (a bindesc
        %   entry with a .combo), from whatever the caller had to hand.
            if isstruct(source) && isfield(source, 'bindesc')
                source = source.bindesc;
            end
            if isstruct(source) && isfield(source, 'label')
                labels = arrayfun(@(b) char(string(b.label)), source, 'UniformOutput', false);
                if isfield(source, 'combo')
                    isDifference = arrayfun(@(b) ~isempty(b.combo), source);
                else
                    isDifference = false(size(labels));
                end
            elseif isempty(source)
                labels = {};
                isDifference = false(1, 0);
            else
                labels = cellstr(string(source));
                isDifference = false(size(labels));
            end
            labels = reshape(labels, 1, []);
            isDifference = reshape(logical(isDifference), 1, []);
        end
    end
end

% ======================================================================= %
function [value, rest] = takeOption(args, name, default)
%TAKEOPTION  One name-value option out of ARGS, the rest passed on.
    value = default;
    rest = {};
    for k = 1:2:numel(args)
        if strcmpi(char(string(args{k})), name)
            value = logical(args{k + 1});
        else
            rest(end + 1:end + 2) = args(k:k + 1); %#ok<AGROW>
        end
    end
end
