function block = singleTrialSection(windowLabel, measureType, binLabels)
%SINGLETRIALSECTION  A mixed model fitted to the TRIALS, not to per-subject
%   averages.
%
%   WHAT THIS BUYS OVER THE AVERAGED MODEL. Averaging first throws away
%   everything inside a subject: a subject contributing 12 usable trials
%   and one contributing 90 arrive as one number each and are weighted
%   identically, though the first estimate is far noisier. Fitting the
%   trials instead lets the model see that, weight subjects by the
%   evidence they actually carry, and estimate within-subject variance
%   rather than discarding it. This is the current standard for ERP
%   inference (Frömer et al. 2018; Volpert-Esmond & Bartholow 2021).
%
%   THE RANDOM STRUCTURE IS MAXIMAL, THEN REDUCED IF IT HAS TO BE. The
%   model tried first is value ~ bin + (1 + bin | person_id), the maximal
%   structure the design justifies (Barr et al. 2013): condition varies
%   within person, so its slope is allowed to as well. Random slopes very
%   often fail to converge or fit singularly with ERP trial counts, so a
%   singular or failed fit falls back to random intercepts, recorded in
%   the Model column of the clustered table rather than narrated per
%   channel -- a reader cannot otherwise tell which was fitted.
%
%   IT DOES NOT REPLACE THE AVERAGED TEST, it sits beside it, and the two
%   are expected to agree in the ordinary case. Where they disagree the
%   difference is informative rather than a fault: it usually means trial
%   counts are badly unequal, or a few subjects carry the averaged effect
%   with very noisy means.
%
%   Requires the per-trial export (exportTrialMeasurementsCSV), produced by
%   running Measure on EPOCHED data. The section is omitted when that file
%   is absent, which is the ordinary case for an averaged-only workspace.
%
%   CLUSTERED ACROSS CHANNELS -- see pairedSection's own header comment.
%
%   See also EXPORTTRIALMEASUREMENTSCSV, MEASURE, LMMSECTION.
    binLabels = cellstr(string(binLabels));
    quoted = cellfun(@(b) ['"' ReportSections.rLit(b) '"'], binLabels, 'UniformOutput', false);

    lines = ReportDoc.lines([{ ...
        '## __WINDOW_MD__ -- __MEASURETYPE_MD__: single-trial model' ...
        '' ...
        ['Fitted to the individual trials rather than to per-subject averages, so that ' ...
         'subjects contributing few trials are weighted as the noisier estimates they are, ' ...
         'and the within-subject variance is estimated rather than averaged away.'] ...
        ReportDoc.template('single-trial-models.qmd') ...
        }, { ...
        ['    cat(sprintf("\n*%s*\n\n", "' ReportSections.rLit(ReportSections.testCaption('lmm')) '"))'] ...
        }, { ...
        ReportDoc.template('single-trial-results.qmd') ...
        }]);

    block = strjoin(lines, newline);
    block = ReportSections.fillCommonTokens(block, windowLabel, measureType, '', '');
    block = ReportSections.fillToken(block, 'YAXIS', ReportSections.yAxisLabel(measureType));
    block = strrep(block, '__BINVECTOR_R__', strjoin(quoted, ', '));
    block = strrep(block, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    block = strrep(block, '__CHUNKLABEL__', ...
        ReportSections.chunkLabel('singletrial', windowLabel, measureType));
end
