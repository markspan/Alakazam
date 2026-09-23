function block = spectrumSection(windowLabel, binLabels)
%SPECTRUMSECTION  The evoked amplitude spectra the frequency measurements
%   were read from, with the tested frequencies marked.
%
%   THE SPECTRAL COUNTERPART OF WAVEFORMSECTION, and it exists for exactly
%   the same reason. Every other section reports statistics ON a number
%   read at a named frequency: power at f1, signal-to-noise against the
%   neighbouring bins, phase locking across trials. None of them shows the
%   spectrum that number came from.
%
%   What that hides is specific to tagging designs and easy to miss in a
%   table. A tag that is simply not present still yields a power value and
%   an SNR near 1. A response sitting one bin away from where it was
%   measured yields a small value that looks like a weak effect rather than
%   a misplaced window. An SNR computed against neighbouring bins that are
%   themselves contaminated, by line noise or by a harmonic of the other
%   tag, is inflated or deflated with nothing in the number to say so. All
%   three are obvious the moment the spectrum is drawn with the tested
%   frequencies marked on it.
%
%   THE MARKS ARE THE FREQUENCIES ACTUALLY TESTED, read from the export
%   rather than recomputed here, so a mark cannot drift away from the value
%   reported beside it. Where the export names a frequency the spectrum
%   does not reach, the mark is simply outside the axis, which is itself
%   worth seeing.
%
%   Requires the spectra export (exportSpectraCSV); omitted when that file
%   was not written, since a spectral measurements export can exist without
%   one.
%
%   See also EXPORTSPECTRACSV, WAVEFORMSECTION, SPECTRALMEASURE.
    binLabels = cellstr(string(binLabels));
    quoted = cellfun(@(b) ['"' ReportSections.rLit(b) '"'], binLabels, 'UniformOutput', false);

    lines = ReportDoc.lines({ ...
        '## __WINDOW_MD__: spectra' ...
        '' ...
        ['The evoked amplitude spectra from which these measurements were taken. Dashed lines ' ...
         'mark the tested frequencies, read from the export itself so that they cannot differ ' ...
         'from the values reported above.'] ...
        ReportDoc.template('spectrum-section.qmd') ...
        });

    block = strjoin(lines, newline);
    block = ReportSections.fillCommonTokens(block, windowLabel, '', '', '');
    block = strrep(block, '__BINVECTOR_R__', strjoin(quoted, ', '));
    block = strrep(block, '__CHUNKLABEL__', ...
        ReportSections.chunkLabel('spectrum', windowLabel));
end
