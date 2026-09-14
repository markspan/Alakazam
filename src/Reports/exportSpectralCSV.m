function exportSpectralCSV(entries, targetFile)
%EXPORTSPECTRALCSV  Write every SpectralMeasure result in ENTRIES to one
%   long-format, R-compatible CSV at TARGETFILE. The frequency-domain sibling
%   of exportMeasurementsCSV.
%
%   ENTRIES is a struct array with .subject, .datasetType ('subject' or
%   'grand_average'), .group (the between-subjects group assigned via
%   WorkSpace.editSubjects, '' if none), .person (which real person this
%   raw file belongs to, defaults to .subject itself -- see
%   WorkSpace.personFor), .session (an optional day/visit label, '' if
%   none) and .EEG (already loaded, carrying .spectralMeasures -- see
%   SpectralMeasure.m and Alakazam.collectSpectralEntries).
%
%   One row per (dataset x frequency x bin x channel x measure type), columns
%   dataset,dataset_type,group,person_id,session,bin,channel,frequency_label,
%   frequency_hz,reference,measure_type,value. measure_type is power /
%   amplitude / snr / itc / phase (always) and coherence / phaselag (only
%   when the frequency was measured against a reference channel), so every
%   row's value column stays uniformly numeric with no per-type NA columns.
%   person_id/session are both consumed by the report -- see
%   exportMeasurementsCSV's own header comment. Same tidy/long shape
%   and quoting as exportMeasurementsCSV, so both drop into the same R
%   workflow.
    fid = fopen(targetFile, 'w');
    if fid < 0
        throw(MException('Alakazam:exportSpectralCSV', ...
            'Unfortunately, I could not open "%s" for writing.', targetFile));
    end
    closeFile = onCleanup(@() fclose(fid));

    fprintf(fid, ['dataset,dataset_type,group,person_id,session,bin,channel,frequency_label,' ...
        'frequency_hz,reference,measure_type,value\n']);

    for i = 1:numel(entries)
        writeEntry(fid, entries(i));
    end
end

function writeEntry(fid, entry)
    datasetField = csvField(entry.subject);
    typeField    = csvField(entry.datasetType);
    groupField   = csvField(entry.group);
    personField  = csvField(entry.person);
    sessionField = csvField(entry.session);
    EEG = entry.EEG;

    for w = 1:numel(EEG.spectralMeasures)
        m = EEG.spectralMeasures{w};
        labelField = csvField(m.label);
        freqField  = sprintf('%.6g', m.freq);
        refField   = csvField(m.refChannel);
        hasRef     = ~isempty(strtrim(char(string(m.refChannel))));
        nBins      = size(m.power, 2);

        for b = 1:nBins
            binField = csvField(csvBinLabel(EEG, b));
            for c = 1:numel(m.channels)
                chField = csvField(m.channels{c});
                prefix = sprintf('%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,', datasetField, typeField, groupField, ...
                    personField, sessionField, binField, chField, labelField, freqField, refField);
                writeRow(fid, prefix, 'power',     m.power(c, b));
                writeRow(fid, prefix, 'amplitude', m.amplitude(c, b));
                writeRow(fid, prefix, 'snr',       m.snr(c, b));
                writeRow(fid, prefix, 'itc',       m.itc(c, b));
                writeRow(fid, prefix, 'phase',     m.phase(c, b));
                if hasRef
                    writeRow(fid, prefix, 'coherence', m.coherence(c, b));
                    writeRow(fid, prefix, 'phaselag',  m.phaselag(c, b));
                end
            end
        end
    end
end

function writeRow(fid, prefix, measureType, value)
    fprintf(fid, '%s%s,%s\n', prefix, measureType, numField(value));
end

% csvBinLabel/csvField/numField (src/Support/) used to be duplicated locally here.
