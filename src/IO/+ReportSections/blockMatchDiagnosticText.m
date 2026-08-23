function s = blockMatchDiagnosticText()
%BLOCKMATCHDIAGNOSTICTEXT  One line of R, spliced into every section right
%   after its own GRP is built (via the __BLOCKMATCHDIAGNOSTIC__ token),
%   reporting how many of the dataset's total subjects actually matched
%   this block's own window/bin filter, and -- crucially -- what raw bin
%   values actually exist in the data for this window. Discovered the
%   hard way: a report that renders with every per-channel section
%   silently skipped ("fewer than 2 subjects") gives no way to tell WHY
%   without this.
%
%   Separately reports how many of those MATCHED subjects have at least
%   one non-missing (non-NA) value anywhere in the block: matching on
%   window/bin alone (as the count above does) says nothing about whether
%   the VALUE itself is usable -- a subject can match every filter and
%   still contribute only NA rows if the underlying measurement itself
%   failed for them (e.g. SpectralMeasure could not compute this
%   frequency for that subject at all). This is what actually explains a
%   block reporting "N of N matched" while every single per-channel
%   section still says "only 1 of 1" -- filter matching was never the
%   problem, most subjects just have no usable value here.
%
%   Placed before this file's own token substitution loop finishes, so
%   its own __WINDOW_R__ placeholder is filled in by the SAME
%   fillCommonTokens call every other token in the section goes through.
    s = strjoin({ ...
        'cat(sprintf("\n\n*(Matched %d of %d total subject(s) for this block (window: %s), of which %d have at least one non-missing value. Distinct raw bin value(s) seen for this window: %s.)*\n\n",' ...
        '            n_distinct(grp$dataset), n_distinct(dat$dataset), "__WINDOW_R__",' ...
        '            n_distinct(grp$dataset[!is.na(grp$value)]),' ...
        '            paste(unique(dat$bin[dat$window == "__WINDOW_R__"]), collapse = "; ")))'}, newline);
end

