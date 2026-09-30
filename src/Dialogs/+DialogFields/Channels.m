classdef Channels < DialogFields.LabelList
%CHANNELS  A channel picker: the dataset's channels by label, with one-click
%   All, None and Scalp EEG.
%
%   DialogFields.Channels(SOURCE, SELECTED, Name, Value)
%     SOURCE    the dataset (an EEG struct), its chanlocs, or a cellstr of
%               labels
%     SELECTED  the labels chosen at first, usually a stored run's; one that
%               is not in this dataset is dropped
%   takes the options of LabelList ('Multiple', 'Required'), and adds a
%   "Scalp EEG" button that selects every channel that is not a known
%   peripheral (EOG, ECG, EMG, a trigger), judged by type and, where that is
%   blank, by label (eegChannelMask). Value: the chosen labels, a row cellstr
%   (or char with 'Multiple' false).
%
%       TransformOptionsDialog(..., ...
%           {'Channels'; 'Channels'}, DialogFields.Channels(input, stored.Channels), ...);
%
%   See also DIALOGFIELDS.BINS, DIALOGFIELDS.LABELLIST, EEGCHANNELMASK.
    methods
        function this = Channels(source, selected, varargin)
            if nargin < 2
                selected = {};
            end
            chanlocs = DialogFields.Channels.chanlocsOf(source);
            labels = arrayfun(@(c) char(string(c.labels)), chanlocs, 'UniformOutput', false);
            scalp = reshape(logical(eegChannelMask(chanlocs)), 1, []);
            extra = {};
            if ~any(strcmpi(varargin(1:2:end), 'QuickSelect'))
                extra = {'QuickSelect', {'Scalp EEG', scalp}};
            end
            this@DialogFields.LabelList(labels, selected, 'Noun', 'channel', extra{:}, varargin{:});
        end
    end

    methods (Static, Access = private)
        function chanlocs = chanlocsOf(source)
        %CHANLOCSOF  The channel list from whatever the caller had to hand.
            if isstruct(source) && isfield(source, 'chanlocs') && ~isempty(source.chanlocs) ...
                    && isfield(source.chanlocs, 'labels')
                chanlocs = source.chanlocs;
            elseif isstruct(source) && isfield(source, 'data')
                % A dataset with no channel list: its channels by number,
                % so the dialog still offers them.
                chanlocs = struct('labels', arrayfun(@(i) sprintf('ch%d', i), ...
                    1:size(source.data, 1), 'UniformOutput', false));
            elseif isstruct(source) && isfield(source, 'labels')
                chanlocs = source;
            else
                chanlocs = struct('labels', reshape(cellstr(string(source)), 1, []));
            end
            if isempty(chanlocs)
                chanlocs = struct('labels', {});
            end
        end
    end
end
