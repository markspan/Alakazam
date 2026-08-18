function entries = collectSpectralEntries(this)
%COLLECTSPECTRALENTRIES  Every dataset in either tree carrying a
%   SpectralMeasure result, as a struct array with .subject, .datasetType
%   ('subject'/'grand_average') and .EEG (already loaded) -- the
%   frequency-domain sibling of collectMeasurementEntries. See
%   collectEntriesWithField for the actual walk. See onExportSpectral/
%   exportSpectralCSV.
    entries = this.collectEntriesWithField("spectralMeasures");
end
