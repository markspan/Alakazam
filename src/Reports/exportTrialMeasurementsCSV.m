function exportTrialMeasurementsCSV(entries, targetFile)
%EXPORTTRIALMEASUREMENTSCSV  Write every per-trial measurement in ENTRIES
%   to one long-format, R-compatible CSV at TARGETFILE.
%
%   ENTRIES is exportMeasurementsCSV's own ENTRIES argument, reused
%   unchanged, except that each .EEG carries .trialMeasurements (Measure
%   run on EPOCHED data) rather than .measurements.
%
%   One row per (dataset x window x trial x channel x measure type),
%   columns dataset,dataset_type,group,person_id,session,trial,bin,channel,
%   window,measure_type,window_start_ms,window_stop_ms,value -- the same
%   tidy shape exportMeasurementsCSV writes, with 'trial' inserted and
%   'bin' now meaning the condition THAT trial belongs to.
%
%   WHY THE TRIAL-LEVEL FILE EXISTS AT ALL. The averaged export gives one
%   number per subject and condition, so a group model can only see
%   between-subject variance and treats a subject with 12 usable trials as
%   equal to one with 90. A single-trial mixed model uses the trials
%   themselves: unequal trial counts weight themselves correctly, the
%   within-subject variance becomes estimable rather than discarded, and
%   trial-varying covariates become expressible. That is the current
%   standard for ERP inference (Frömer et al. 2018; Volpert-Esmond et al.
%   2021), and the averaged export cannot support it no matter how it is
%   modelled downstream.
%
%   A TRIAL IN TWO BINS IS WRITTEN TWICE, once per bin, because that is
%   what it is: a combination bin overlapping a base one genuinely
%   contains the same trial, and a long-format file says so by repeating
%   the row rather than by silently picking one. A trial in NO bin is
%   written with an empty bin field rather than dropped, so the file still
%   accounts for every trial that was measured.
%
%   Shares csvField/numField/measureRowTypes/measureRowValue with
%   exportMeasurementsCSV, so the two files cannot disagree about which
%   measure types a window produces or how a value is spelled.
%
%   See also EXPORTMEASUREMENTSCSV, MEASURE, TRIALBINS.
    fid = fopen(targetFile, 'w');
    if fid < 0
        throw(MException('Alakazam:exportTrialMeasurementsCSV', '%s', sprintf( ...
            'I''m afraid I wasn''t able to open "%s" for writing.', targetFile)));
    end
    closeFile = onCleanup(@() fclose(fid));

    fprintf(fid, ['dataset,dataset_type,group,person_id,session,trial,bin,channel,window,' ...
        'measure_type,window_start_ms,window_stop_ms,value\n']);

    for i = 1:numel(entries)
        writeEntry(fid, entries(i));
    end
end

function writeEntry(fid, entry)
    EEG = entry.EEG;
    if ~isfield(EEG, 'trialMeasurements') || isempty(EEG.trialMeasurements)
        return;   % an averaged entry among epoched ones: nothing per-trial to write
    end

    datasetField = csvField(entry.subject);
    typeField    = csvField(entry.datasetType);
    groupField   = csvField(entry.group);
    personField  = csvField(entry.person);
    sessionField = csvField(entry.session);

    for w = 1:numel(EEG.trialMeasurements)
        win = EEG.trialMeasurements{w};
        windowField = csvField(win.label);
        startField  = sprintf('%.6g', win.start);
        stopField   = sprintf('%.6g', win.stop);
        nTrials     = size(win.amplitude, 2);
        types       = measureRowTypes(win);

        for t = 1:nTrials
            binFields = trialBinFields(EEG, t);
            for c = 1:numel(win.channels)
                chField = csvField(win.channels{c});
                for bi = 1:numel(binFields)
                    prefix = sprintf('%s,%s,%s,%s,%s,%d,%s,%s,%s,', ...
                        datasetField, typeField, groupField, personField, sessionField, ...
                        t, binFields{bi}, chField, windowField);
                    for ti = 1:numel(types)
                        fprintf(fid, '%s%s,%s,%s,%s\n', prefix, types{ti}, ...
                            startField, stopField, numField(measureRowValue(win, types{ti}, c, t)));
                    end
                end
            end
        end
    end
end

function fields = trialBinFields(EEG, t)
%TRIALBINFIELDS  The CSV bin field(s) trial T belongs to.
%   Always at least one entry, so every measured trial reaches the file:
%   a trial in no bin gets a single empty field rather than no row.
    idx = [];
    if isfield(EEG, 'trialBinIndex') && numel(EEG.trialBinIndex) >= t
        idx = EEG.trialBinIndex{t};
    end
    if isempty(idx)
        fields = {csvField('')};
        return;
    end
    fields = arrayfun(@(b) csvField(csvBinLabel(EEG, b)), idx, 'UniformOutput', false);
end
