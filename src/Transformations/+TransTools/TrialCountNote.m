function TrialCountNote(counts, labels, step)
%TRIALCOUNTNOTE  Say so when bins compared on coherence hold different numbers
%   of trials. COUNTS is the trials each bin kept (0 for a combination bin),
%   LABELS their names, STEP the transformation's name for the message.
%   Coherence and phase locking rise as the trials fall, so such bins differ for
%   that reason alone (see TRANSTOOLS.EQUALISEDDRAWS, which offers the remedy).
%   A fifth more trials in one bin than another is left unmentioned: the bias at
%   the counts these measures are used at moves far less than that does.
    used = counts > 0;
    if nnz(used) < 2 || max(counts(used)) <= 1.2 * min(counts(used))
        return;
    end
    [lo, loAt] = min(counts(used));
    [hi, hiAt] = max(counts(used));
    names = labels(used);
    fprintf(['%s: the bins hold different numbers of trials (%d in "%s", %d in "%s"). Coherence and ' ...
        'phase locking are higher with fewer trials, about 1/N by chance alone, so compare them ' ...
        'with care, or tick Equalise trials.\n'], step, lo, names{loAt}, hi, names{hiAt});
end
