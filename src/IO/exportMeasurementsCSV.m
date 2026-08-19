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
        nBins       = size(win.amplitude, 2);

        types = measureRowTypes(win); % one measure_type row per value a window produces (see its own header
                                       % comment), shared with generateQuartoReport.m so the two can never drift
        for b = 1:nBins
            binField = csvField(csvBinLabel(EEG, b));
            for c = 1:numel(win.channels)
                chField = csvField(win.channels{c});
                prefix = sprintf('%s,%s,%s,%s,%s,', datasetField, typeField, binField, chField, windowField);
                % start/stop stay the window's own search range for every
                % measure -- for a band Area the integration span is
                % width-ms centred on peak_latency, and a fractional
                % latency's fraction is the window's own Fraction, both
                % recoverable from the window definition.
                for ti = 1:numel(types)
                    writeRow(fid, prefix, types{ti}, startField, stopField, measureRowValue(win, types{ti}, c, b));
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

% csvBinLabel/csvField/numField/measureRowTypes/measureRowValue/areaModeScope
% all live in src/Support/, shared with generateQuartoReport.m -- measureRowTypes
% and areaModeScope used to be duplicated/inlined locally here.
