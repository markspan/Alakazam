function [traceFile, mapFile, chosen] = exportCoherenceCSVs(entries, stem, opts)
%EXPORTCOHERENCECSVS  The CoherenceMap result, as data rather than a picture.
%   [TRACEFILE, MAPFILE, CHOSEN] = exportCoherenceCSVs(ENTRIES, STEM, OPTS)
%   writes two long-format CSVs beside each other and returns their paths
%   plus the channel labels the map was written for.
%
%   WHY TWO FILES AND NOT ONE. A coherence map is nChan x nFreq x nTime x
%   nBin, and at the settings of Dimigen et al. (2025) (STFT 510 ms, pad 4,
%   52 to 68 Hz, a 13 s epoch at 1000 Hz) that is 33 frequencies by 98
%   frames. Written whole for 64 channels and 3 bins it is 620,928 rows,
%   about 37 MB PER SUBJECT, so a twenty-subject study would put three
%   quarters of a gigabyte beside the report. The two files split that
%   along the axis that matters:
%
%     TRACE  coherence against time at the tagged frequency alone, for
%            EVERY channel. 18,816 rows, about 1 MB, and it is the plot
%            that shows fade-in, steady state and fade-out, which is where
%            the steady-state measurement window comes from.
%     MAP    the full time x frequency plane, for a FEW channels. The
%            figure a tagging paper prints, at about 5 MB for eight
%            channels rather than 37 for all of them.
%
%   THE TAGGED FREQUENCY IS FOUND IN THE DATA, per bin, as the frequency
%   whose coherence is greatest averaged over channels and time. In a
%   tagging design that IS the tag, it needs nothing the map does not
%   already carry, and it cannot drift out of step with a number typed
%   somewhere else. A design where that is not the tag is one where this
%   whole read-out does not apply.
%
%   THE MAP'S CHANNELS ARE CHOSEN BY RESPONSE, AND THAT IS A DISPLAY
%   DECISION, NOT AN ANALYSIS ONE. They are the OPTS.MaxChannels (default
%   8) with the highest coherence at the tagged frequency. Choosing what to
%   plot after seeing the data is how every figure in every tagging paper
%   is made, and it is only dangerous when a test follows; nothing here is
%   tested, and the report says which channels were picked and why.
%
%   OPTS fields, all optional:
%     MaxChannels   how many channels the map is written for   (default 8)
%     Channels      explicit labels for the map instead        (default [])
%
%   See also COHERENCEMAP, EXPORTSPECTRACSV, GENERATEQUARTOREPORT.
    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    maxChannels = TransTools.FieldOr(opts, 'MaxChannels', 8);
    wanted = TransTools.FieldOr(opts, 'Channels', {});

    traceFile = [stem '_coherence_trace.csv'];
    mapFile   = [stem '_coherence_map.csv'];
    chosen = {};

    traceFid = openFile(traceFile);
    closeTrace = onCleanup(@() fclose(traceFid));
    fprintf(traceFid, ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
        'time_ms,tag_hz,coherence\n']);

    mapFid = openFile(mapFile);
    closeMap = onCleanup(@() fclose(mapFid));
    fprintf(mapFid, ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
        'time_ms,frequency_hz,coherence\n']);

    for i = 1:numel(entries)
        picked = writeEntry(traceFid, mapFid, entries(i), maxChannels, wanted);
        chosen = unique([chosen, picked], 'stable');
    end
end

% ======================================================================= %
function fid = openFile(path)
    fid = fopen(path, 'w');
    if fid < 0
        throw(MException('Alakazam:exportCoherenceCSVs', '%s', sprintf( ...
            'I''m afraid I wasn''t able to open "%s" for writing.', path)));
    end
end

function chosen = writeEntry(traceFid, mapFid, entry, maxChannels, wanted)
%WRITEENTRY  One dataset's trace and map rows.
    chosen = {};
    EEG = entry.EEG;
    if ~isfield(EEG, 'coherence') || isempty(EEG.coherence) || ...
            ~isfield(EEG, 'cohFreqs') || ~isfield(EEG, 'cohTimes')
        return;
    end

    coh   = double(EEG.coherence);         % nChan x nFreq x nTime x nBin
    freqs = reshape(double(EEG.cohFreqs), 1, []);
    times = reshape(double(EEG.cohTimes), 1, []);
    [nChan, nFreq, nTime, nBin] = size(coh);
    if nFreq ~= numel(freqs) || nTime ~= numel(times)
        return;    % a shape nothing here can interpret; skip rather than guess
    end

    labels = channelLabels(EEG, nChan);
    fields = {csvField(entry.subject), csvField(entry.datasetType), ...
        csvField(entry.group), csvField(entry.person), csvField(entry.session)};
    prefix = [strjoin(fields, ','), ','];

    for b = 1:nBin
        binField = csvField(csvBinLabel(EEG, b));
        slab = coh(:, :, :, b);                        % nChan x nFreq x nTime

        % The tag: strongest coherence averaged over channels and time.
        perFreq = mean(mean(slab, 3, 'omitnan'), 1, 'omitnan');
        [~, fTag] = max(perFreq);
        tagHz = freqs(fTag);

        % Every channel's trace at that frequency.
        trace = reshape(slab(:, fTag, :), nChan, nTime);
        for c = 1:nChan
            chField = csvField(labels{c});
            for t = 1:nTime
                fprintf(traceFid, '%s%s,%s,%s,%s,%s\n', prefix, binField, chField, ...
                    numField(times(t)), numField(tagHz), numField(trace(c, t)));
            end
        end

        % And the full plane, for the few channels worth printing.
        picked = pickChannels(trace, labels, maxChannels, wanted);
        chosen = unique([chosen, labels(picked)], 'stable');
        for c = picked
            chField = csvField(labels{c});
            for f = 1:nFreq
                fHz = numField(freqs(f));
                for t = 1:nTime
                    fprintf(mapFid, '%s%s,%s,%s,%s,%s\n', prefix, binField, chField, ...
                        numField(times(t)), fHz, numField(slab(c, f, t)));
                end
            end
        end
    end
end

function idx = pickChannels(trace, labels, maxChannels, wanted)
%PICKCHANNELS  Which channels the full map is written for.
%   An explicit list wins, so an analyst who knows their montage is never
%   overruled by the data. Otherwise the strongest responders, which is
%   what a figure shows.
    if ~isempty(wanted)
        idx = [];
        for k = 1:numel(wanted)
            hit = find(strcmpi(labels, char(string(wanted{k}))), 1);
            if ~isempty(hit)
                idx(end + 1) = hit; %#ok<AGROW>
            end
        end
        if ~isempty(idx)
            return;
        end
    end
    peak = max(trace, [], 2, 'omitnan');
    peak(~isfinite(peak)) = -Inf;
    [~, order] = sort(peak, 'descend');
    idx = sort(order(1:min(maxChannels, numel(order))))';
end

function labels = channelLabels(EEG, nChan)
    labels = arrayfun(@(k) sprintf('ch%d', k), 1:nChan, 'UniformOutput', false);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) >= nChan
        for c = 1:nChan
            name = EEG.chanlocs(c).labels;
            if ~isempty(name)
                labels{c} = char(string(name));
            end
        end
    end
end
