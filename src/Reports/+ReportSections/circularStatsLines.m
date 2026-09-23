function lines = circularStatsLines()
%CIRCULARSTATSLINES  The R that summarises a circular measure in GRP: per
%   channel and bin, the mean angle, the resultant length R_bar, a percentile
%   bootstrap interval on the mean direction, and a Note when there are too few
%   observations or the angles are close to uniform. Prints one table for the
%   whole block, with its caption.
%
%   Shared by circularSection (the ordinary bins) and comboSectionDescriptiveOnly
%   (a combination bin of a circular measure). The combination bin used to get a
%   linear mean and SD instead, directly under a sentence saying linear
%   statistics are not valid for an angle. See circularSection for the
%   statistics themselves and why they are computed this way.
%
%   See also CIRCULARSECTION, COMBOSECTIONDESCRIPTIVEONLY.
    lines = ReportDoc.lines({ ...
        ReportDoc.template('circular-stats.Rpart') ...
        ['  cat(sprintf("\n*%s*\n\n", "' ReportSections.rLit(ReportSections.testCaption('circular_bootstrap_ci')) '"))'] ...
        '}' ...
        });
end
