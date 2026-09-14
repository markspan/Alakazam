function plan = reportDesignPlan(design)
%REPORTDESIGNPLAN  Which model the statistical report should fit, and why.
%
%   PLAN = REPORTDESIGNPLAN(DESIGN) reads a design derived by deriveDesign
%   and decides the fixed-effect structure, the random effect, and whether
%   a richer model had to be given up. Deciding this in MATLAB rather than
%   in the generated R is what makes it testable: the report engine has a
%   standing register of defects (QuartoReportKnownGapTest) precisely
%   because behaviour expressed only as emitted R is hard to check.
%
%   IT DERIVES NOTHING ITSELF. Every fact it needs -- the levels of each
%   factor, which people were measured more than once, how many people fall
%   in each cell of the crossing -- deriveDesign has already worked out, and
%   the Design panel is looking at the same object. An earlier version
%   re-derived all of it from the report's own entries, with its own rules
%   for blank labels and its own cell counting, which meant the panel could
%   state one design while the report fitted another. This function is now
%   policy only: given a design, which model.
%
%   PLAN fields:
%     .withinFactors   {'bin'} or {'bin', 'session'}
%     .betweenFactors  {} or {'group'}
%     .fixed           the fixed-effect formula, e.g. '(bin + session + group)^2'
%     .random          the random-effect term, e.g. '(1 + bin | person_id)'
%     .randomFallback  the simpler random term to retry with on non-convergence
%     .sessionLevels / .groupLevels
%     .usedFallback    true when a richer model was available but not fitted
%     .fallbackReason  why, in a sentence the report prints verbatim
%
%   THREE DECISIONS ARE FIXED HERE, DELIBERATELY.
%
%   No three-way interaction. With bin, session and group all present the
%   model is (bin + session + group)^2: every main effect and every two-way
%   interaction, and nothing else. A bin x session x group term is rarely
%   supportable by the number of subjects an ERP study actually has, and
%   the formula says so explicitly rather than leaving its absence to be
%   inferred.
%
%   The random effect is on PERSON, not on the recording. This is the one
%   change that is not optional. Until session existed a recording was a
%   subject -- personFor falls back to the recording's own name -- so
%   (1 | dataset) was correct by accident. The moment one person
%   contributes two sessions, grouping by dataset treats them as two
%   independent subjects, inflating the degrees of freedom and understating
%   every standard error: a model that looks entirely healthy and is wrong.
%   For a single-session study person_id and dataset are still identical,
%   so no existing result moves.
%
%   Falling back is preferred to refusing. An empty or near-empty cell
%   makes an interaction unestimable, and lmer's own response would be to
%   fail or silently drop terms. Instead the richer factor is dropped, the
%   simpler model is fitted, and the reason is printed with the result --
%   an answer with a stated limitation beats no answer with a stack trace.
%
%   See also DERIVEDESIGN, DESIGNRECORDS, GENERATEQUARTOREPORT.
    plan = struct( ...
        'withinFactors', {{'bin'}}, 'betweenFactors', {{}}, ...
        'fixed', 'bin', 'random', '(1 + bin | person_id)', ...
        'randomFallback', '(1 | person_id)', ...
        'sessionLevels', {{}}, 'groupLevels', {{}}, ...
        'usedFallback', false, 'fallbackReason', '');

    if isempty(design.persons)
        return;
    end

    groupLevels = levelsOf(design, 'group');
    sessionLevels = levelsOf(design, 'session');

    if numel(groupLevels) >= 2
        plan.groupLevels = groupLevels;
        plan.betweenFactors = {'group'};
    end

    % Session becomes a factor on its own, whenever the recordings support
    % one: an analyst who has labelled two sessions has described a design,
    % and asking them to declare it a second time would only let the two
    % disagree.
    [useSession, reason] = sessionIsUsable(design, sessionLevels);
    if useSession
        plan.sessionLevels = sessionLevels;
        plan.withinFactors = {'bin', 'session'};
    elseif numel(sessionLevels) >= 2
        plan.usedFallback = true;
        plan.fallbackReason = reason;
    end

    plan.fixed = fixedFormula(plan);
end

% ======================================================================= %
function [tf, reason] = sessionIsUsable(design, sessionLevels)
%SESSIONISUSABLE  Whether the recordings can carry session as a factor.
%
%   Three ways they cannot, each checked because lmer's own failure mode is
%   worse than a stated limitation: fewer than two session levels; too few
%   people measured under more than one of them (session is then confounded
%   with person and the model cannot separate them); or a cell of the
%   crossing too small to estimate the interaction involving it.
    tf = false;
    reason = '';

    if numel(sessionLevels) < 2
        return;   % not a factor; nothing to explain
    end

    repeated = sum(arrayfun(@(p) numel(p.sessions) >= 2, design.persons));
    if repeated < 2
        reason = sprintf(['Session was recorded but not used as a factor: only %d subject(s) ' ...
            'appear in more than one session, so session cannot be compared within subjects. ' ...
            'The simpler model below was fitted instead.'], repeated);
        return;
    end

    % design.cells is the group x session crossing, already counted in
    % PEOPLE (a between- or within-subjects term's own n is the number of
    % people, not the number of files). Where there is no group it holds one
    % placeholder row per session, so the same loop serves both.
    counts = [design.cells.nPersons];
    if isempty(counts)
        return;
    end
    empty = find(counts == 0, 1);
    if ~isempty(empty)
        reason = sprintf(['Session was recorded but not used as a factor: no subject falls in ' ...
            '%s, so the interaction involving session cannot be estimated. The simpler model ' ...
            'below was fitted instead.'], cellName(design.cells(empty)));
        return;
    end
    if min(counts) < 2
        reason = ['Session was recorded but not used as a factor: at least one combination of ' ...
            'group and session has only one subject, which is too few to estimate an ' ...
            'interaction. The simpler model below was fitted instead.'];
        return;
    end

    tf = true;
end

function name = cellName(cell)
%CELLNAME  A cell named the way the analyst labelled it, with deriveDesign's
%   own placeholders dropped: "young / post" where both factors are real,
%   'session "post"' where only session is.
    if isempty(cell.group) || strcmp(cell.group, '(no group)')
        name = sprintf('session "%s"', cell.session);
    else
        name = sprintf('%s / %s', cell.group, cell.session);
    end
end

% ======================================================================= %
function levels = levelsOf(design, factorName)
%LEVELSOF  The levels deriveDesign recorded for one factor, or {}.
    levels = {};
    if isempty(design.factors)
        return;
    end
    match = design.factors(strcmp({design.factors.name}, factorName));
    if ~isempty(match)
        levels = match(1).levels;
    end
end

function text = fixedFormula(plan)
%FIXEDFORMULA  The fixed-effect side, in R.
%
%   With all three factors this is (bin + session + group)^2 rather than
%   bin * session * group: "^2" is R for every main effect and every
%   two-way interaction, which states the omission of the three-way as a
%   choice rather than leaving it to be noticed.
    factors = [plan.withinFactors, plan.betweenFactors];
    switch numel(factors)
        case 1
            text = factors{1};
        case 2
            text = strjoin(factors, ' * ');
        otherwise
            text = sprintf('(%s)^2', strjoin(factors, ' + '));
    end
end
