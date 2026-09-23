function channels = spectralMeasureChannels(entries, montage)
%SPECTRALMEASURECHANNELS  The electrodes the Spectral Measure rows name.
%   CHANNELS = spectralMeasureChannels(ENTRIES) is the union, in the order
%   first met, of the channel labels behind every row that measures coherence
%   (a row with a reference channel) in ENTRIES' EEG.spectralMeasures. It is
%   how the report's two coherence sections follow the user's own choice
%   of electrodes instead of drawing all of them.
%
%   A pool "{Pz POz CPz}" is stored under the one label "{Pz+POz+CPz}"; the
%   coherence map itself is per electrode and has no pool to draw, so the
%   pool contributes its members.
%
%   CHANNELS = spectralMeasureChannels(ENTRIES, MONTAGE) also asks whether the
%   names narrow anything. MONTAGE are the entries holding the coherence
%   maps (EEG.chanlocs). A row left on "all channels" stores every electrode,
%   and naming the whole montage selects nothing, so when no map has a proper
%   subset of its channels named the result is {}: drawing the general figure
%   is right, and drawing every channel as if it had been picked one by one
%   is not. Names that no map has at all give {} for the same reason.
%
%   Returns {} when there is nothing to follow, which the exporter reads as
%   "leave the channels alone".
%
%   See also EXPORTCOHERENCECSVS, SPECTRALMEASURE, MEASURECHANNELSPECS.
    channels = {};
    for i = 1:numel(entries)
        EEG = entries(i).EEG;
        if ~isfield(EEG, 'spectralMeasures') || isempty(EEG.spectralMeasures)
            continue;
        end
        rows = EEG.spectralMeasures;
        for r = 1:numel(rows)
            row = rows{r};
            if ~isstruct(row) || ~isfield(row, 'channels') || ...
                    ~isfield(row, 'refChannel') || isempty(row.refChannel)
                continue;
            end
            labels = row.channels;
            if ischar(labels) || isstring(labels)
                labels = cellstr(labels);
            end
            for k = 1:numel(labels)
                channels = [channels, poolMembers(char(string(labels{k})))]; %#ok<AGROW>
            end
        end
    end
    channels = unique(channels, 'stable');

    if nargin >= 2 && ~isempty(channels) && ~narrowsAny(channels, montage)
        channels = {};
    end
end

function members = poolMembers(label)
%POOLMEMBERS  "{A+B+C}" as {'A','B','C'}; any other label as itself.
    if numel(label) > 2 && label(1) == '{' && label(end) == '}'
        members = cellstr(strsplit(label(2:end - 1), '+'));
        members = members(~cellfun(@isempty, members));
    else
        members = {label};
    end
end

function tf = narrowsAny(channels, montage)
%NARROWSANY  Whether CHANNELS name a proper, non-empty subset of at least one
%   map's electrodes (matched without regard to case, as the rows are).
    tf = false;
    for i = 1:numel(montage)
        EEG = montage(i).EEG;
        if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs)
            continue;
        end
        labels = arrayfun(@(c) char(string(c.labels)), EEG.chanlocs, 'UniformOutput', false);
        hit = ismember(lower(labels), lower(channels));
        if any(hit) && ~all(hit)
            tf = true;
            return;
        end
    end
end
