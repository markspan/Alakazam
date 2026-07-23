function exportGrandAveragesCSV(nodes, targetFile)
%EXPORTGRANDAVERAGESCSV  Write every Grand Average in NODES to one
%   long-format, R-compatible CSV at TARGETFILE.
%
%   NODES is a struct array in WorkSpaceTree.allNodes's shape (.Name the
%   grand average's label, .UserData its saved .mat file, holding an EEG
%   struct produced by GrandAverage.m/Alakazam.saveGrandAverage).
%
%   One row per (grand average x bin x channel x time point), columns
%   grand_average, bin, channel, time_ms, amplitude, sem, n_subjects --
%   this "tidy"/long shape, not a wide channel/time matrix, is what R's
%   read.csv() + ggplot2/dplyr expect directly, with no reshape needed on
%   the R side (e.g. ggplot(df, aes(time_ms, amplitude, colour = bin)) +
%   geom_line() + facet_wrap(~channel)). n_subjects (constant per grand
%   average, not part of the vectorized per-timepoint write below) is
%   written as NA, R's own standard missing-value token, when unknown; an
%   individual NaN amplitude/sem sample (part of the fast vectorized
%   numeric write) is instead left as literal "NaN" text -- R's own
%   as.numeric()/read.csv() parse that correctly into R's NaN too
%   (is.na(NaN) is TRUE in R), so both spellings resolve to "missing" on
%   the R side; forcing "NaN" to "NA" specifically would cost the
%   vectorization for a case (NaN inside a data array, not just the
%   scalar metadata fields) that is the exception, not the rule.
    fid = fopen(targetFile, 'w');
    if fid < 0
        throw(MException('Alakazam:exportGrandAveragesCSV', ...
            'Could not open "%s" for writing.', targetFile));
    end
    closeFile = onCleanup(@() fclose(fid));

    fprintf(fid, 'grand_average,bin,channel,time_ms,amplitude,sem,n_subjects\n');

    for i = 1:numel(nodes)
        loaded = load(nodes(i).UserData, 'EEG');
        writeGrandAverage(fid, csvField(nodes(i).Name), loaded.EEG);
    end
end

function writeGrandAverage(fid, gaField, EEG)
    % This CSV is an ERP-waveform export (amplitude per bin/channel/time). A
    % time-frequency or coherence grand average has no ERP waveform (its .data
    % is stale epoched data, and its real content is the .ersp / .coherence
    % map), so it is skipped here rather than written as garbage.
    if (isfield(EEG, 'ersp') && ~isempty(EEG.ersp)) || ...
       (isfield(EEG, 'coherence') && ~isempty(EEG.coherence))
        return;
    end
    nSubjects = NaN;
    if isfield(EEG, 'etc') && isfield(EEG.etc, 'GrandAverage') && isfield(EEG.etc.GrandAverage, 'nSubjects')
        nSubjects = EEG.etc.GrandAverage.nSubjects;
    end
    nSubjectsField = numField(nSubjects);

    nBins = size(EEG.data, 3);
    nChan = size(EEG.data, 1);
    nT    = numel(EEG.times);
    hasSem = isfield(EEG, 'stErr') && ~isempty(EEG.stErr);

    for b = 1:nBins
        if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
            binField = csvField(EEG.bindesc(b).label);
        else
            binField = csvField(num2str(b));
        end
        for ch = 1:nChan
            chField = csvField(EEG.chanlocs(ch).labels);
            amp = reshape(EEG.data(ch, :, b), 1, nT);
            if hasSem
                sem = reshape(EEG.stErr(ch, :, b), 1, nT);
            else
                sem = nan(1, nT);
            end
            % One fprintf call per (bin, channel) writes the whole time
            % series at once: the row-constant fields (grand average, bin,
            % channel, n_subjects) are baked into the format string as
            % literal text (escaped %% around the four numeric
            % placeholders that DO cycle per row), rather than looping
            % fprintf once per time point -- keeps this fast even for a
            % large channel count/epoch length (a 64-channel, 2000-sample,
            % 4-bin export is 256 fprintf calls, not half a million).
            fmt = sprintf('%s,%s,%s,%%.6g,%%.6g,%%.6g,%s\n', gaField, binField, chField, nSubjectsField);
            fprintf(fid, fmt, [reshape(EEG.times, 1, nT); amp; sem]);
        end
    end
end

function field = csvField(value)
%CSVFIELD  A CSV-quoted field if VALUE needs it (contains a comma, quote,
%   or newline), otherwise VALUE unchanged. Values are inserted as %s
%   arguments into sprintf/fprintf format strings elsewhere in this file,
%   never as literal format text, so a stray '%' in VALUE (e.g. a
%   percent-labelled bin name) needs no escaping here.
    field = char(string(value));
    if any(field == ',' | field == '"' | field == newline)
        field = ['"' strrep(field, '"', '""') '"'];
    end
end

function field = numField(value)
%NUMFIELD  A numeric value formatted for CSV, NA (R's own missing-value
%   token) if it is NaN.
    if isnan(value)
        field = 'NA';
    else
        field = sprintf('%.6g', value);
    end
end
