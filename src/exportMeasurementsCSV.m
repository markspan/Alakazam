function exportMeasurementsCSV(entries, targetFile)
%EXPORTMEASUREMENTSCSV  Write every Measure result in ENTRIES to one
%   long-format, R-compatible CSV at TARGETFILE.
%
%   ENTRIES is a struct array with .subject (the originating raw file's
%   own name for a Data & Analyses node, or the node's own name for a
%   Grand Average -- see Alakazam.onExportMeasurements, which resolves
%   this via Workspace.Tree.rootOf), .datasetType ('subject' or
%   'grand_average'), and .EEG (the already-loaded dataset, carrying
%   .measurements -- see Measure.m).
%
%   One row per (dataset x window x bin x channel x measure type),
%   columns dataset,dataset_type,bin,channel,window,measure_type,
%   window_start_ms,window_stop_ms,value -- the same "tidy"/long shape
%   exportGrandAveragesCSV.m uses, so both exports drop into the same R
%   workflow (read.csv() + dplyr/ggplot2, no reshape needed). A "Peak"
%   window contributes two rows per (bin, channel) -- measure_type
%   peak_amplitude and peak_latency -- rather than two value columns, so
%   every row's own value column stays uniformly numeric with no
%   per-measure-type NA column needed.
%
%   Unlike exportGrandAveragesCSV's per-(bin,channel) vectorized fprintf
%   (needed there because it writes a whole TIME SERIES per row group),
%   this writes one fprintf per output row: a realistic measurement
%   export (a handful of windows x channels x bins x subjects) is at
%   most a few thousand rows, not the hundreds of thousands of samples a
%   time-series export can be, so the extra complexity of vectorizing
%   the (bin, channel, measure_type) triple would not be a real win here.
    fid = fopen(targetFile, 'w');
    if fid < 0
        throw(MException('Alakazam:exportMeasurementsCSV', ...
            'Could not open "%s" for writing.', targetFile));
    end
    closeFile = onCleanup(@() fclose(fid));

    fprintf(fid, 'dataset,dataset_type,bin,channel,window,measure_type,window_start_ms,window_stop_ms,value\n');

    for i = 1:numel(entries)
        writeEntry(fid, entries(i));
    end
end

function writeEntry(fid, entry)
    datasetField = csvField(entry.subject);
    typeField    = csvField(entry.datasetType);
    EEG = entry.EEG;

    for w = 1:numel(EEG.measurements)
        win = EEG.measurements{w};
        windowField = csvField(win.label);
        startField  = sprintf('%.6g', win.start);
        stopField   = sprintf('%.6g', win.stop);
        isPeak      = strcmpi(win.measure, 'Peak');
        nBins       = size(win.amplitude, 2);

        for b = 1:nBins
            binField = csvField(binLabel(EEG, b));
            for c = 1:numel(win.channels)
                chField = csvField(win.channels{c});
                prefix = sprintf('%s,%s,%s,%s,%s,', datasetField, typeField, binField, chField, windowField);
                if isPeak
                    fprintf(fid, '%speak_amplitude,%s,%s,%s\n', prefix, startField, stopField, ...
                        numField(win.amplitude(c, b)));
                    fprintf(fid, '%speak_latency,%s,%s,%s\n', prefix, startField, stopField, ...
                        numField(win.latency(c, b)));
                else
                    fprintf(fid, '%smean_amplitude,%s,%s,%s\n', prefix, startField, stopField, ...
                        numField(win.amplitude(c, b)));
                end
            end
        end
    end
end

function label = binLabel(EEG, b)
%BINLABEL  EEG.bindesc(b)'s own label, or the bare bin number if this
%   dataset carries no bindesc (or a shorter one than expected) --
%   matches exportGrandAveragesCSV's own fallback exactly.
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
        label = EEG.bindesc(b).label;
    else
        label = num2str(b);
    end
end

function field = csvField(value)
%CSVFIELD  A CSV-quoted field if VALUE needs it (contains a comma, quote,
%   or newline), otherwise VALUE unchanged. Same as exportGrandAveragesCSV's
%   own helper (kept as a separate copy here rather than a shared
%   dependency, matching that file's own precedent).
    field = char(string(value));
    if any(field == ',' | field == '"' | field == newline)
        field = ['"' strrep(field, '"', '""') '"'];
    end
end

function field = numField(value)
%NUMFIELD  A numeric value formatted for CSV, NA (R's own missing-value
%   token) if it is NaN. Same as exportGrandAveragesCSV's own helper.
    if isnan(value)
        field = 'NA';
    else
        field = sprintf('%.6g', value);
    end
end
