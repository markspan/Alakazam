function exportSpectraCSV(entries, targetFile)
%EXPORTSPECTRACSV  Write every stored evoked amplitude spectrum in ENTRIES
%   to one long-format, R-compatible CSV at TARGETFILE.
%
%   ENTRIES is exportSpectralCSV's own ENTRIES argument, reused unchanged.
%   Each .EEG carries .spectrum (channels x frequencies x bins) and
%   .specFreqs, both written by SpectralMeasure for display.
%
%   One row per (dataset x bin x channel x frequency), columns
%   dataset,dataset_type,group,person_id,session,bin,channel,freq_hz,
%   amplitude. The same tidy shape exportGrandAveragesCSV writes, so it
%   drops into the same ggplot workflow with no reshaping.
%
%   WHY IT EXISTS. A frequency-tagging report states power, SNR, phase
%   locking and coherence at named frequencies, and until now showed none
%   of the spectrum those numbers were read from. That is the same gap the
%   ERP report had: a tag that is simply absent, a peak sitting one bin
%   away from where it was measured, an SNR computed against a neighbour
%   band that is itself contaminated, and a harmonic that is really line
%   noise all produce numbers that test perfectly well. Every one of them
%   is obvious on the spectrum and invisible in a table.
%
%   THINNED ABOVE 100 Hz, and this is the one liberty it takes: a
%   1000 Hz recording gives thousands of frequency bins per channel per
%   bin, almost all of them far above anything a tagging design cares
%   about, and writing them all makes a file that is mostly noise floor
%   and slow to read. Everything up to 100 Hz is written in full.
%
%   See also EXPORTSPECTRALCSV, SPECTRALMEASURE, EXPORTGRANDAVERAGESCSV.
    fid = fopen(targetFile, 'w');
    if fid < 0
        throw(MException('Alakazam:exportSpectraCSV', '%s', sprintf( ...
            'I''m afraid I wasn''t able to open "%s" for writing.', targetFile)));
    end
    closeFile = onCleanup(@() fclose(fid));

    fprintf(fid, ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
        'frequency_hz,amplitude\n']);

    for i = 1:numel(entries)
        writeEntry(fid, entries(i));
    end
end

function writeEntry(fid, entry)
    EEG = entry.EEG;
    if ~isfield(EEG, 'spectrum') || isempty(EEG.spectrum) || ...
            ~isfield(EEG, 'specFreqs') || isempty(EEG.specFreqs)
        return;
    end

    freqs = reshape(double(EEG.specFreqs), 1, []);
    keep = find(freqs <= 100);
    if isempty(keep)
        keep = 1:numel(freqs);   % an unusual recording; write what there is
    end

    datasetField = csvField(entry.subject);
    typeField    = csvField(entry.datasetType);
    groupField   = csvField(entry.group);
    personField  = csvField(entry.person);
    sessionField = csvField(entry.session);

    labels = {EEG.chanlocs.labels};
    [nChan, ~, nBins] = size(EEG.spectrum);

    for b = 1:nBins
        binField = csvField(csvBinLabel(EEG, b));
        for c = 1:min(nChan, numel(labels))
            chField = csvField(labels{c});
            prefix = sprintf('%s,%s,%s,%s,%s,%s,%s,', datasetField, typeField, ...
                groupField, personField, sessionField, binField, chField);
            values = double(EEG.spectrum(c, keep, b));
            % One call for the channel rather than one per frequency: these
            % are hundreds of rows each and per-row fprintf dominates.
            %
            % The prefix is CONCATENATED, never placed in the format string.
            % It carries a channel label and a bin label, and a bin label is
            % free to contain a per-cent sign; inside a format that would be
            % read as a conversion and the write would fail at run time on
            % nothing worse than a condition called "50% load".
            rows = string(prefix) + compose('%.6g,%.6g', freqs(keep)', values');
            fprintf(fid, '%s\n', rows);
        end
    end
end
