function exportMeasurementsCSV(entries, targetFile)
%EXPORTMEASUREMENTSCSV  Write every Measure result in ENTRIES to one
%   long-format, R-compatible CSV at TARGETFILE.
%
%   ENTRIES is a struct array with .subject (the originating raw file's
%   own name for a Data & Analyses node, or the node's own name for a
%   Grand Average -- see Alakazam.onExportMeasurements, which resolves
%   this via Workspace.Tree.rootOf), .datasetType ('subject' or
%   'grand_average'), .group (the between-subjects group assigned via
%   WorkSpace.editSubjects, '' if none), .person (which real person this
%   raw file belongs to -- defaults to .subject itself unless multiple
%   raw files were explicitly linked as the same person's different
%   sessions, see WorkSpace.personFor), .session (an optional day/visit
%   label, '' if none -- see collectEntriesWithField), and .EEG (the
%   already-loaded dataset, carrying .measurements -- see Measure.m).
%
%   One row per (dataset x window x bin x channel x measure type),
%   columns dataset,dataset_type,group,person_id,session,bin,channel,
%   window,measure_type,window_start_ms,window_stop_ms,value -- the same
%   "tidy"/long shape exportGrandAveragesCSV.m uses, so both exports drop
%   into the same R workflow (read.csv() + dplyr/ggplot2, no reshape
%   needed). person_id/session are metadata only so far -- every
%   statistical test in the companion Quarto report (generateQuartoReport)
%   still keys on dataset/group, not person_id/session, since treating a
%   session as a genuine second within-subjects factor (crossed against
%   bin) is a design the report engine does not build yet; they are
%   there for a researcher's own custom analysis of the CSV in the
%   meantime. A "Peak" window contributes two rows per (bin, channel) --
%   measure_type peak_amplitude and peak_latency -- rather than two value
%   columns, so every row's own value column stays uniformly numeric
%   with no per-measure-type NA column needed.
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

    fprintf(fid, ['dataset,dataset_type,group,person_id,session,bin,channel,window,measure_type,' ...
        'window_start_ms,window_stop_ms,value\n']);

    for i = 1:numel(entries)
        writeEntry(fid, entries(i));
    end
end

function writeEntry(fid, entry)
    datasetField  = csvField(entry.subject);
    typeField     = csvField(entry.datasetType);
    groupField    = csvField(entry.group);
    personField   = csvField(entry.person);
    sessionField  = csvField(entry.session);
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
                prefix = sprintf('%s,%s,%s,%s,%s,%s,%s,%s,', datasetField, typeField, groupField, ...
                    personField, sessionField, binField, chField, windowField);
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
