function entries = collectMeasurementEntries(this)
%COLLECTMEASUREMENTENTRIES  Every dataset in either tree carrying a
%   Measure result, as a struct array with .subject, .datasetType
%   ('subject'/'grand_average'), and .EEG (already loaded) -- see
%   Alakazam.onExportMeasurements/exportMeasurementsCSV. See
%   collectEntriesWithField for the actual walk, shared with
%   collectSpectralEntries (EEG.spectralMeasures there, EEG.measurements
%   here).
    entries = this.collectEntriesWithField("measurements");
end
