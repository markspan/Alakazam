function block = lmmSection(windowLabel, measureType, binLabels, plan)
%LMMSECTION  The linear mixed model section, for every design that gets one.
%   Replaces anovaSection, mixedSection and sessionSection, which were three
%   copies of one section: 75 identical contiguous lines between the last
%   two, 48 and 46 between the other pairs. Everything that actually varied
%   is derived from PLAN (see reportDesignPlan) in presentation() below.
%
%   The four designs it covers, by what PLAN says the factors are:
%
%     bin                      the within-subjects LMM ("anova-" chunks)
%     bin x group              the mixed design    ("mixed-" chunks)
%     bin x session            repeated sessions   ("session-" chunks)
%     bin x session x group    both, two-way only  ("session-" chunks)
%
%   WHY AN LMM AND NOT A REPEATED-MEASURES ANOVA. RM-ANOVA requires every
%   subject to have every bin and drops anyone missing even one; an LMM
%   fits on every non-missing (subject, bin) observation, so a subject
%   missing one bin still contributes their other bins rather than being
%   excluded from the channel entirely. The maximal random structure a
%   design justifies is fitted first (random intercept AND slope for bin,
%   Barr et al., 2013), falling back to intercept-only if that does not
%   converge to a non-singular fit, and the report says which was used.
%
%   GROUPED BY PERSON, NOT BY RECORDING. The random effect is on person_id.
%   Where nobody has set a person, WorkSpace.personFor returns the
%   recording's own name and the two are identical; where sessions exist,
%   grouping by recording would treat one person's two visits as
%   independent subjects and understate every standard error.
%
%   NO THREE-WAY INTERACTION. With all three factors the formula is
%   (bin + session + group)^2: every main effect and every two-way
%   interaction, and nothing beyond. reportDesignPlan builds it that way and
%   this section simply prints what it was given.
%
%   POST-HOC POLICY VARIES BY DESIGN, deliberately, and is named rather
%   than implied -- see postHocLines(). The session designs are strict (at
%   most one family, and only following a significant term); the older two
%   keep the unconditional contrasts they have always run, so that merging
%   these three files changed no existing report's statistics.
%
%   CLUSTERED ACROSS CHANNELS -- see pairedSection's own header comment for
%   why. The per-effect "the model revealed a significant effect of X,
%   F(...)..." sentence is gone: the fixed-effect table (now with a Channel
%   column, one row per channel per effect) already carries F/df/p AND the
%   partial eta-squared this used to add in a follow-up sentence, so the
%   sentence would only restate the table. Likewise the standardized
%   coefficients and post-hoc contrasts are one table each, across every
%   channel, not one set of tables per channel.
%
%   See also REPORTDESIGNPLAN, PAIREDSECTION, BETWEENSECTION.
    view = presentation(plan);

    binVectorR = strjoin(cellfun(@(b) ['"' ReportSections.rLit(b) '"'], binLabels, 'UniformOutput', false), ', ');
    binListMd = strjoin(cellfun(@(b) ReportSections.mdLit(b), binLabels, 'UniformOutput', false), ', ');

    lines = ReportDoc.lines([ ...
        ReportDoc.template('lmm-heading.qmd'), ...
        view.modelNote, ...
        ReportDoc.template('lmm-chunk-open.Rpart'), ...
        view.prepare, ...
        ReportDoc.template('lmm-descriptives.Rpart'), ...
        ReportDoc.template('lmm-fit.Rpart'), ...
        postHocLines(view.postHoc), ...
        {'  }', ''}, ...
        ReportDoc.template('lmm-omnibus.Rpart'), ...
        view.facet, ...
        ReportDoc.template('lmm-tables.qmd'), ...
        ... % standardize_parameters' CI column is the interval's LEVEL (0.95), which
        ... % in a column of numbers reads as a value; the level goes in the title, so
        ... % lmm-posthoc-tables.qmd drops it: select(-any_of("CI")).
        ReportDoc.template('lmm-posthoc-tables.qmd')]);

    text = strjoin(lines, newline);
    % The templates carry the shape; these are the values this design puts
    % in them (see ReportDoc.template, and the section's own header for
    % what the presentation struct decides).
    text = strrep(text, '__HEADING_SUFFIX__', view.headingSuffix);
    text = strrep(text, '__BIN_LIST_MD__', binListMd);
    text = strrep(text, '__INTRO_TAIL__', view.introTail);
    text = strrep(text, '__BIN_VECTOR_R__', binVectorR);
    text = strrep(text, '__SKIP_CONDITION__', view.skipCondition);
    text = strrep(text, '__SKIP_REASON__', view.skipReason);
    text = strrep(text, '__DESCR_GROUPING__', view.descrGrouping);
    text = strrep(text, '__FIXED__', plan.fixed);
    text = strrep(text, '__RANDOM_FALLBACK__', plan.randomFallback);
    text = strrep(text, '__RANDOM__', plan.random);
    text = strrep(text, '__EFFECT_VECTOR__', view.effectVector);
    text = strrep(text, '__HEADLINE_EFFECT__', view.headlineEffect);
    text = strrep(text, '__DESIGN_TAG__', view.designTag);
    text = strrep(text, '__TEST_NAME__', view.testName);
    text = strrep(text, '__ANOVA_TABLE_TITLE__', view.anovaTableTitle);
    text = strrep(text, '__BF_TABLE_TITLE__', view.bfTableTitle);
    text = strrep(text, '__CAPTION_LMM__', ReportSections.rLit(ReportSections.testCaption('lmm')));
    text = strrep(text, '__CAPTION_LMM_BF__', ReportSections.rLit(ReportSections.testCaption('lmm_bf')));
    text = strrep(text, '__CAPTION_POSTHOC__', ReportSections.rLit(ReportSections.testCaption(postHocCaption(view.postHoc))));
    text = strrep(text, '__CAPTION_EMMEANS__', ReportSections.rLit(ReportSections.testCaption('emmeans_holm')));
    text = strrep(text, '__NBINS__', num2str(numel(binLabels)));
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel(view.chunkPrefix, windowLabel, measureType));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, '', '');
end

% ======================================================================= %
function view = presentation(plan)
%PRESENTATION  Everything that differs between the four designs, in one
%   place, derived from the plan rather than from a flag the caller passes.
%
%   This function IS the merge: the three former section files differed in
%   exactly these fields and in nothing else. Reading it top to bottom is
%   the quickest way to see what a design change actually changes.
    hasSession = numel(plan.withinFactors) > 1;
    hasGroup = ~isempty(plan.betweenFactors);

    % ---- chunk label prefix. Stable, because reports and tests both name
    % sections by it; the design's identity is public API here.
    if hasSession
        view.chunkPrefix = 'session';
    elseif hasGroup
        view.chunkPrefix = 'mixed';
    else
        view.chunkPrefix = 'anova';
    end

    % ---- heading, intro and the effects the narrative walks through
    if hasSession && hasGroup
        view.headingSuffix = ' (Session x Group)';
        view.introTail = ' -- within subjects, crossed with session and with the between-subjects group.';
        view.descrGrouping = 'group, session, bin';
        view.effectVector = '"bin", "session", "group", "bin:session", "bin:group", "session:group"';
        view.facet = {'    facet_wrap(~channel + group + session),'};
    elseif hasSession
        view.headingSuffix = ' (Session)';
        view.introTail = ' -- within subjects, crossed with session.';
        view.descrGrouping = 'session, bin';
        view.effectVector = '"bin", "session", "bin:session"';
        view.facet = {'    facet_wrap(~channel + session),'};
    elseif hasGroup
        view.headingSuffix = ' (Mixed Design)';
        view.introTail = ' -- within subjects, crossed with the between-subjects group.';
        view.descrGrouping = 'group, bin';
        view.effectVector = '"group", "bin", "bin:group"';
        view.facet = {'    facet_wrap(~channel + group),'};
    else
        view.headingSuffix = '';
        view.introTail = '.';
        view.descrGrouping = 'bin';
        view.effectVector = '"bin"';
        view.facet = {'    facet_wrap(~channel),'};
    end

    % ---- the row this section contributes to the cross-report summary.
    % The headline is the interaction the design exists to test, or the
    % main effect of bin when there is no interaction to have.
    % postHoc is named here rather than inferred at the call site: it is a
    % statistical policy, and it should be visible next to the design it
    % belongs to. See postHocLines for what each name means and why the two
    % older designs are not strict.
    if hasSession
        view.designTag = 'lmm_session';
        view.headlineEffect = 'bin:session';
        view.testName = 'bin_x_session';
        view.postHoc = 'strict';
        view.bfTableTitle = 'Bayes Factor for the Condition by Session Interaction, by Channel';
    elseif hasGroup
        view.designTag = 'lmm_mixed';
        view.headlineEffect = 'bin:group';
        view.testName = 'group_x_bin_interaction';
        view.postHoc = 'both';
        view.bfTableTitle = 'Bayes Factor for the Condition by Group Interaction, by Channel';
    else
        view.designTag = 'lmm_within';
        view.headlineEffect = 'bin';
        view.testName = 'omnibus';
        view.postHoc = 'bin';
        view.bfTableTitle = 'Bayes Factor for the Condition Effect, by Channel';
    end

    if numel(strsplit(view.effectVector, ',')) > 1
        view.anovaTableTitle = 'Linear Mixed Model: Fixed-Effect Tests (Satterthwaite df), by Channel';
    else
        view.anovaTableTitle = 'Linear Mixed Model: Fixed-Effect Test (Satterthwaite df), by Channel';
    end

    % ---- the skip guard. Counted in PEOPLE: a between- or within-subjects
    % term's own n is the number of people, not the number of files.
    conditions = {'n_distinct(d$person_id) < 2'};
    reasons = {'fewer than two subjects'};
    if hasGroup
        conditions{end + 1} = 'n_distinct(d$group) < 2';
        reasons{end + 1} = 'fewer than two groups';
    end
    if hasSession
        conditions{end + 1} = 'n_distinct(d$session) < 2';
        reasons{end + 1} = 'fewer than two sessions';
    end
    view.skipCondition = strjoin(conditions, ' || ');
    view.skipReason = [strjoin(reasons, ', or ') ', have a usable value for this channel'];

    % ---- session needs its factor built before the loop; nothing else does
    if hasSession
        view.prepare = {'grp <- grp %>% mutate(session = factor(session))'};
    else
        view.prepare = {};
    end

    % ---- the design note under the heading, for designs worth spelling out
    if hasSession
        view.modelNote = {['Fixed effects: `' plan.fixed '`. Random effects: `' plan.random '`.'], ''};
    else
        view.modelNote = {};
    end
end

% ======================================================================= %
function id = postHocCaption(policy)
%POSTHOCCAPTION  The caption under the post-hoc table, true to POLICY: only
%   'strict' runs its contrasts because the effect they follow was significant.
    if strcmp(policy, 'strict')
        id = 'emmeans_holm_gated';
    else
        id = 'emmeans_holm';
    end
end

function lines = postHocLines(policy)
%POSTHOCLINES  The follow-up contrasts, by named policy -- appends into the
%   caller's posthoc_list (or posthocWithin_list/posthocBetween_list for
%   'both') rather than printing per channel; see lmmSection's own header
%   comment for why.
%
%   'strict'  At most one family, and only when the term it follows is
%             significant: the interaction first, then the main effect of
%             bin, then nothing. A report that runs every family it can
%             think of has spent its alpha before anyone decided what the
%             question was. Further contrasts belong to the user, and
%             both emmeans and the fitted model are in scope for adding
%             them right there in the .qmd.
%
%   'bin'     One unconditional family over bins. What the within-subjects
%             design has always run.
%
%   'both'    Within-group and between-group families, both unconditional.
%             What the mixed design has always run.
%
%   The older two are not strict because making them so would have changed
%   the statistics in existing reports as a side effect of merging three
%   files into one. Switching them is a one-line change here if that is
%   wanted; it is a statistical decision, not a refactoring one.
    switch policy
        case 'strict'
            lines = { ...
                '    # ---- post-hoc, deliberately at most one family ----------------' ...
                '    posthoc <- NULL' ...
                '    posthoc_what <- ""' ...
                '    if (!is.na(p_head) && p_head < .05) {' ...
                '      posthoc <- tryCatch(emmeans::emmeans(m, pairwise ~ bin | session, adjust = "holm"), error = function(e) NULL)' ...
                '      posthoc_what <- "simple effects of bin within each session"' ...
                '    } else if (!is.na(p_bin) && p_bin < .05) {' ...
                '      posthoc <- tryCatch(emmeans::emmeans(m, pairwise ~ bin, adjust = "holm"), error = function(e) NULL)' ...
                '      posthoc_what <- "pairwise comparisons between bins"' ...
                '    }' ...
                '    if (!is.null(posthoc)) {' ...
                '      posthoc_list[[ch]] <- as.data.frame(posthoc$contrasts) %>% mutate(channel = ch, family = posthoc_what, .before = 1)' ...
                '    }'};

        case 'bin'
            lines = { ...
                '    emm <- tryCatch(emmeans::emmeans(m, pairwise ~ bin, adjust = "holm"), error = function(e) NULL)' ...
                '    if (!is.null(emm)) {' ...
                '      posthoc_list[[ch]] <- as.data.frame(emm$contrasts) %>% mutate(channel = ch, .before = 1)' ...
                '    }'};

        case 'both'
            lines = { ...
                '    emm_within <- tryCatch(emmeans::emmeans(m, pairwise ~ bin | group, adjust = "holm"), error = function(e) NULL)' ...
                '    if (!is.null(emm_within)) {' ...
                '      posthocWithin_list[[ch]] <- as.data.frame(emm_within$contrasts) %>% mutate(channel = ch, .before = 1)' ...
                '    }' ...
                '' ...
                '    emm_between <- tryCatch(emmeans::emmeans(m, pairwise ~ group | bin, adjust = "holm"), error = function(e) NULL)' ...
                '    if (!is.null(emm_between)) {' ...
                '      posthocBetween_list[[ch]] <- as.data.frame(emm_between$contrasts) %>% mutate(channel = ch, .before = 1)' ...
                '    }'};

        otherwise
            throw(MException('Alakazam:lmmSection:postHoc', ...
                'I am afraid "%s" is not a post-hoc policy I know.', policy));
    end
end
