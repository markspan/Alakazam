function block = circularSection(windowLabel, measureType, binLabels)
%CIRCULARSECTION  Ordinary bins whose measure type is CIRCULAR (see
%   isCircularType): circular descriptive statistics, and no linear test.
%
%   WHY THIS EXISTS. A Spectral export's 'phase' and 'phaselag' are angles
%   that wrap at +/-pi, and every ordinary-bin route in this report is
%   linear: pairedSection runs a t-test, lmmSection fits lmerTest::lmer,
%   descriptiveSection summarises with mean() and sd(). None of those mean
%   anything on a circle. The arithmetic mean of 179 and -179 degrees is
%   0, which is the point exactly opposite where the data actually sit,
%   and an sd computed the same way is larger the more tightly the angles
%   cluster around the wrap.
%
%   The combination-bin branch already refused these types a linear test
%   (comboSectionDescriptiveOnly), so before this existed one report could
%   state in one section that a linear test of 'phase' was invalid and in
%   the next section report exactly such a test on the same measure.
%
%   WHAT IT REPORTS INSTEAD, and why not simply nothing. The two standard
%   first-order circular statistics need no package beyond base R:
%
%     mean angle       atan2(mean(sin(t)), mean(cos(t)))
%     resultant length R = sqrt(mean(sin(t))^2 + mean(cos(t))^2), in [0,1]
%
%   R is the concentration: 1 means every subject had the same angle, 0
%   means they are spread evenly around the circle and the mean angle is
%   meaningless. Reporting the mean angle without R would be the circular
%   equivalent of a mean without an SD, so the two always appear together.
%
%   AND AN INTERVAL ON THE MEAN ANGLE, by bootstrap over subjects. A mean
%   direction with no interval invites exactly the over-reading R is there
%   to prevent, and R alone does not answer "how well is this direction
%   pinned down", because the same R at n = 5 and n = 40 supports very
%   different claims. Bootstrapping needs no distributional assumption and
%   no package, and it degrades honestly: when the angles are near uniform
%   the interval widens towards the whole circle, which says "there is no
%   direction here" more plainly than any statistic.
%
%   The resamples are taken on the DEVIATION from the observed mean,
%   wrapped into (-pi, pi], rather than on the angles themselves. Taking
%   percentiles of raw angles puts the discontinuity inside the data
%   whenever the mean sits near the wrap, and produces an interval running
%   the wrong way round the circle. The seed is fixed so that re-rendering
%   the same export twice gives the same interval.
%
%   NO TEST IS OFFERED. A Rayleigh or Watson-Williams test would be the
%   right instrument, and both are genuinely useful, but they belong in a
%   deliberate decision about which circular test this pipeline endorses
%   rather than in the fix for a routing defect. The interval covers most
%   of what a reader needs from one: an interval spanning the circle is
%   the uninformative case, stated directly rather than as a p-value.
%
%   CLUSTERED ACROSS CHANNELS -- see pairedSection's own header comment.
%   The "close to uniform" / "too few observations" caveat is a Note
%   column in the one combined table now, rather than a sentence repeated
%   per bin per channel that mostly restated the row beside it. No plot:
%   deliberately not added (a circular quantity is poorly served by a
%   linear axis, and a polar plot was considered and rejected).
%
%   See also ISCIRCULARTYPE, DESCRIPTIVEONLYREASON, DESCRIPTIVESECTION.
    binLabels = cellstr(string(binLabels));
    % Only the ordinary bins: a combination bin of the same measure has its own
    % section (comboSectionDescriptiveOnly), and filtered on measure and window
    % alone it also appeared here, in a table headed by the conditions.
    binVectorR = strjoin(cellfun(@(b) ['"' ReportSections.rLit(b) '"'], binLabels, 'UniformOutput', false), ', ');

    lines = [{ ...
        '## __WINDOW_MD__ -- __MEASURETYPE_MD__' ...
        '' ...
        ['Conditions: __BINLIST_MD__. ' ...
         'This is a circular quantity (an angle that wraps at +/-pi radians), so the linear ' ...
         'comparisons used elsewhere in this report are not valid for it: the arithmetic mean ' ...
         'of two angles on either side of the wrap falls opposite the direction of the data. ' ...
         'Circular descriptive statistics are reported instead, and no test is run.'] ...
        '' ...
        '```{r}' ...
        '#| label: __CHUNKLABEL__' ...
        '#| results: asis' ...
        'grp <- dat %>% filter(measure_type == "__MEASURETYPE_R__", window == "__WINDOW_R__",' ...
        ['                       bin %in% c(' binVectorR ')) %>% droplevels()'] ...
        '__BLOCKMATCHDIAGNOSTIC__' ...
        '' ...
        }, ReportSections.circularStatsLines(), { ...
        '```' ...
        ''}];

    block = strjoin(lines, newline);
    % Empty bin slots: this section names every ordinary bin in one list
    % (__BINLIST__) rather than filling the one/two named slots the paired
    % and single-bin sections use, so BIN1/BIN2 are passed through empty,
    % which fillToken documents as a no-op.
    %
    % The block-match diagnostic goes in BEFORE the common tokens are filled: it
    % carries a __WINDOW_R__ of its own, and filled afterwards that placeholder was
    % never replaced (the report printed "window: WINDOW_R" and searched the data
    % for a window of that name). Every other section builder already does it in
    % this order.
    block = strrep(block, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    block = ReportSections.fillCommonTokens(block, windowLabel, measureType, '', '');
    block = ReportSections.fillToken(block, 'BINLIST', strjoin(binLabels, ', '));
    block = strrep(block, '__CHUNKLABEL__', ...
        ReportSections.chunkLabel('circ', windowLabel, measureType));
end
