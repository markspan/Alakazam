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
        measure     = lower(strtrim(char(string(win.measure))));
        nBins       = size(win.amplitude, 2);

        for b = 1:nBins
            binField = csvField(csvBinLabel(EEG, b));
            for c = 1:numel(win.channels)
                chField = csvField(win.channels{c});
                prefix = sprintf('%s,%s,%s,%s,%s,', datasetField, typeField, binField, chField, windowField);
                % One measure_type row per value a window produces, so the
                % single `value` column stays uniformly numeric: Mean
                % Amplitude -> one row; Peak -> amplitude + latency; Area ->
                % an area_<mode> row (mode = signed/rectified/positive/
                % negative), plus, when the area is a peak-locked band, the
                % located peak's own amplitude + latency; the fractional-
                % latency measures -> one latency row. start/stop stay the
                % window's own search range for every measure -- for a band
                % Area the integration span is width-ms centred on
                % peak_latency, and a fractional latency's fraction is the
                % window's own Fraction, both recoverable from the window
                % definition.
                switch measure
                    case 'peak'
                        writeRow(fid, prefix, 'peak_amplitude', startField, stopField, win.amplitude(c, b));
                        writeRow(fid, prefix, 'peak_latency',   startField, stopField, win.latency(c, b));
                    case {'area', 'integral', 'peak area'}
                        [mode, isBand] = areaModeScope(win, measure);
                        writeRow(fid, prefix, ['area_' mode], startField, stopField, win.area(c, b));
                        if isBand
                            writeRow(fid, prefix, 'peak_amplitude', startField, stopField, win.amplitude(c, b));
                            writeRow(fid, prefix, 'peak_latency',   startField, stopField, win.latency(c, b));
                        end
                    case 'fractional peak latency'
                        writeRow(fid, prefix, 'fractional_peak_latency', startField, stopField, win.latency(c, b));
                    case 'fractional area latency'
                        writeRow(fid, prefix, 'fractional_area_latency', startField, stopField, win.latency(c, b));
                    otherwise % Mean Amplitude
                        writeRow(fid, prefix, 'mean_amplitude', startField, stopField, win.amplitude(c, b));
                end
            end
        end
    end
end

function writeRow(fid, prefix, measureType, startField, stopField, value)
%WRITEROW  One long-format CSV data row: PREFIX already carries the
%   dataset/type/bin/channel/window fields (comma-terminated).
    fprintf(fid, '%s%s,%s,%s,%s\n', prefix, measureType, startField, stopField, numField(value));
end

function [mode, isBand] = areaModeScope(win, measureName)
%AREAMODESCOPE  A window's area mode ('signed'/'rectified'/'positive'/
%   'negative', default 'signed') and whether its scope is a peak-locked
%   band. Tolerates a measurement stored before the Area family was unified
%   into one measure (Peak Area -> band, Integral -> whole window), which
%   carries no areaMode/scope field.
    mode = 'signed';
    if isfield(win, 'areaMode') && ~isempty(win.areaMode)
        cand = lower(strtrim(char(string(win.areaMode))));
        if ismember(cand, {'signed', 'rectified', 'positive', 'negative'})
            mode = cand;
        end
    end
    if isfield(win, 'scope') && ~isempty(win.scope)
        isBand = strcmpi(strtrim(char(string(win.scope))), 'band');
    else
        isBand = strcmp(measureName, 'peak area');
    end
end

% csvBinLabel/csvField/numField (src/Support/) used to be duplicated locally here.
