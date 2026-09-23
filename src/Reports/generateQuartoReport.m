function qmdText = generateQuartoReport(entries, csvFileName, sourceEstimates, grandAverageCsv, trialCsv, spectraCsv, coherenceCsvs)
%GENERATEQUARTOREPORT  A design-aware Quarto (.qmd) report for an exported
%   measurements CSV: rendering it (self-contained HTML) produces a short,
%   APA-styled results report -- APA-formatted tables (gt) with a caption
%   under each test, a reading guide and a closing summary in prose, and
%   embedded plots -- rather than a plain R console script.
%
%   This file is the orchestrator. It works out what design the export
%   actually has, picks one section builder per window/frequency x measure
%   type, and assembles the document (preamble + sections + closing
%   summary). The section builders themselves -- one Quarto/R template per
%   statistical design, plus the token-substitution and escaping helpers
%   they share (rLit, mdLit, fillToken, ...) -- live one-per-file in
%   +ReportSections alongside this file, and the scaffolding every Alakazam
%   report shares (YAML header, package bootstrap, APA helpers) lives in
%   +ReportDoc. So this file does not also have to be the place every R
%   template lives.
%
%   THE DESIGN IS DERIVED ONCE, at the top, and everything downstream reads
%   it rather than re-deciding:
%
%     designRecords     report entries -> the record shape deriveDesign reads
%     deriveDesign      the factors, their levels, and the cells they cross into
%     reportDesignPlan  which model that design supports, and what it gave up
%     classifyBins      ordinary vs combination bins, from EEG.bindesc
%
%   deriveDesign is the same function behind the Show Design panel, so the
%   panel and the report cannot disagree about the same recordings. Both
%   classifyBins and the plan are MATLAB-side decisions for the same
%   reason: EEG.bindesc(b).combo, the subject's group and the subject's
%   person/session are not recoverable from the flat CSV, so a generic R
%   script re-discovering the design at runtime could not make them.
%
%   WHAT EACH DESIGN GETS (see the section builders for the exact calls):
%     - 1 ordinary bin, no groups: descriptive statistics only -- no
%       comparison is possible.
%     - 1 ordinary bin, 2+ groups: a between-subjects test (Welch t /
%       Welch ANOVA + Games-Howell), betweenSection.
%     - 2 ordinary bins, nothing else: a paired t-test + Cohen's dz, or a
%       Wilcoxon signed-rank test + rank-biserial r when a silent Shapiro-Wilk
%       check finds the differences non-normal. Only the chosen test is shown.
%     - Any other multi-bin design: lmmSection, a linear mixed model whose
%       fixed effects come from the plan -- bin, bin * group, bin * session,
%       or (bin + session + group)^2 (every main effect and every two-way
%       interaction; the three-way is deliberately omitted). Random effect
%       (1 + bin | person_id), falling back to an intercept-only model on a
%       singular fit, and to a simpler FIXED structure, with the reason
%       printed, when the recordings cannot support session.
%     - Each COMBINATION (difference) bin, separately: a one-sample t-test
%       (or Wilcoxon, chosen the same way) against zero -- never folded into
%       the omnibus test above, since a combination bin is computed from the
%       OTHER bins' waveforms, not an independent condition, so including it
%       there would be statistically invalid.
%
%   An LMM rather than a repeated-measures ANOVA, throughout: a subject
%   missing one bin still contributes their other bins instead of being
%   dropped from the whole channel. Grouped by person rather than by
%   recording, so a person measured in two sessions counts once.
%
%   Every block's own key p-value also feeds one final cross-report summary
%   table, where the primary tests are BH/FDR-corrected together across
%   every channel x window x measure the export produced; the secondary ones
%   (combination bins, single-trial models) are listed uncorrected.
%
%   Results are tables, not narrated sentences: descriptives, then the one
%   test chosen for the comparison, with a one-sentence caption saying what
%   that test tests (testCaption).
%
%   ENTRIES is the struct array Alakazam.collectEntriesWithField produces:
%   one element per dataset, carrying .subject, .datasetType
%   ('subject'/'grand_average'), .group, .person, .session and a loaded
%   .EEG. ENTRIES(1).EEG supplies the bin structure (EEG.bindesc) plus
%   either EEG.measurements (an ERP export -- see measureRowTypes) or
%   EEG.spectralMeasures (a Spectral export -- see spectralBlocks),
%   auto-detected from whichever field is present, so onExportMeasurements
%   and onExportSpectral call this the same way. The remaining fields carry
%   the design, and reach the generated R through the CSV.
%
%   CSVFILENAME is the bare file name the report's own read_csv() call
%   references, relative to where the report itself is written.
%
%   SOURCEESTIMATES is optional: generateSourceEstimateReportAssets' own
%   return value (a struct array, possibly empty/omitted). When non-empty,
%   a "Source Estimate (Exploratory)" section is appended after the
%   statistical summary, built by ReportSections.sourceEstimateSection --
%   pure markdown (pre-rendered images, pre-computed fit percentages), so
%   accepting this argument adds no R/FieldTrip dependency to THIS
%   function; it stays exactly the text-assembly orchestrator its own
%   header already describes. Omitting the argument (every existing call
%   site does) reproduces the exact same document as before this section
%   existed -- see GenerateQuartoReportTest for the guard that pins that.
%
%   Rendering needs a working Quarto installation (https://quarto.org) and
%   R with tidyverse, rstatix, coin, ggpubr, gt, lme4, lmerTest, emmeans,
%   performance, effectsize and BayesFactor -- the setup chunk installs
%   whichever are missing on the first render.
%
%   See also DERIVEDESIGN, REPORTDESIGNPLAN, DESIGNRECORDS,
%   EXPORTMEASUREMENTSCSV, EXPORTSPECTRALCSV, MEASUREROWTYPES,
%   GENERATESOURCEESTIMATEREPORTASSETS, REPORTSECTIONS.SOURCEESTIMATESECTION.
    if nargin < 4
        grandAverageCsv = '';
    end
    if nargin < 5
        trialCsv = '';
    end
    if nargin < 6
        spectraCsv = '';
    end
    % A struct with .Trace and .Map, or '' for neither. One argument rather
    % than two because they are written together and are useless apart: a
    % map with no trace has nothing to justify its window against.
    if nargin < 7 || isempty(coherenceCsvs)
        coherenceCsvs = struct('Trace', '', 'Map', '');
    end
    if isempty(entries)
        throw(MException('Alakazam:generateQuartoReport', ...
            'I''m afraid generateQuartoReport needs at least one Measure result to build a report from.'));
    end
    EEG = entries(1).EEG;
    hasErp      = isfield(EEG, 'measurements') && ~isempty(EEG.measurements);
    hasSpectral = isfield(EEG, 'spectralMeasures') && ~isempty(EEG.spectralMeasures);
    if ~hasErp && ~hasSpectral
        throw(MException('Alakazam:generateQuartoReport', ...
            ['I''m afraid generateQuartoReport needs a dataset with at least one Measure window ' ...
             '(EEG.measurements) or Spectral Measure (EEG.spectralMeasures).']));
    end
    if hasErp
        reportTitle = 'ERP';
        groupColumn = 'window';
        blocks = erpBlocks(EEG);
    else
        reportTitle = 'Spectral';
        groupColumn = 'frequency_label';
        blocks = spectralBlocks(EEG);
    end

    [ordinaryLabels, comboBins] = classifyBins(EEG);

    % Between-subjects grouping (see WorkSpace.editSubjects/groupFor): a
    % MATLAB-side decision, not rediscovered per section in R, mirroring
    % how ordinaryLabels/comboBins above are also decided once here rather
    % than per chunk. >= 2 DISTINCT non-blank group labels across the
    % export's own subject entries is what actually activates the
    % between/mixed path below -- a workspace where nobody has been
    % assigned a group (or everybody shares one label) renders exactly as
    % it always has, no opt-in flag needed.
    % THE DESIGN IS DERIVED ONCE, here, and every later decision reads it.
    % reportDesignPlan settles which factors the recordings actually
    % support, the model formula that follows, and whether a richer model
    % had to be given up (which the preamble then prints, so an unestimable
    % interaction lmer would have silently mangled becomes a stated
    % limitation instead). Nothing below re-derives any of that: hasGroups
    % used to be worked out separately from the same entries, which is two
    % answers to one question and exactly one too many.
    design = deriveDesign(designRecords(entries));
    plan = reportDesignPlan(design);
    hasGroups = ~isempty(plan.betweenFactors);

    useSession = numel(plan.withinFactors) > 1;

    % A linear mixed model is what every multi-bin design gets EXCEPT the
    % plain two-bin within-subjects case, which stays a paired t-test: with
    % exactly two conditions and no other factor, the t-test is the same
    % comparison stated more simply, and it carries a Bayes factor and a
    % Wilcoxon check an LMM section does not.
    useLmm = hasGroups || useSession;

    sections = {};

    % A DESIGN WITH NO ORDINARY BINS USED TO FAIL SILENTLY. When every
    % bindesc entry carries a .combo, the dispatch below has nothing to
    % match and simply emits no omnibus section -- and said nothing about
    % it, so the document still had its headings, still rendered, and
    % still ended with a summary, while the comparison a reader would
    % assume was there was absent. The combination bins are analysed
    % perfectly well, so the report is worth producing; it just has to say
    % what it does not contain.
    if isempty(ordinaryLabels)
        sections{end + 1} = strjoin({ ...
            '## Condition comparison', ...
            '', ...
            ['This design has no ordinary condition bins: every bin defined for it is a ' ...
             'combination (difference) bin. There is therefore nothing to compare between ' ...
             'conditions, and no omnibus section appears below. The combination bins ' ...
             'themselves are analysed in full, each in its own section.'], ...
            '', ''}, newline);
    end

    for bl = 1:numel(blocks)
        blockLabel = blocks(bl).label;
        types = blocks(bl).measureTypes;

        % ONCE PER WINDOW, NOT PER MEASURE TYPE. The waveform belongs to the
        % window, not to whichever quantity was read off it: mean amplitude
        % and peak latency over 300-500 ms are two numbers from one wave, and
        % drawing it twice would say otherwise.
        if ~isempty(grandAverageCsv) && ~isempty(ordinaryLabels)
            sections{end + 1} = ReportSections.waveformSection(blockLabel, ordinaryLabels, grandAverageCsv); %#ok<AGROW>
        end

        % The spectral counterpart, once per frequency block. Only one of the
        % two can apply to any given export: a measurements CSV carries time
        % windows and a spectral one carries frequencies, and neither
        % accompanying file is written for the other kind.
        if ~isempty(spectraCsv) && ~isempty(ordinaryLabels)
            sections{end + 1} = ReportSections.spectrumSection(blockLabel, ordinaryLabels); %#ok<AGROW>
        end
        for ti = 1:numel(types)
            measureType = types{ti};

            if ReportSections.isCircularType(measureType)
                % CIRCULAR TYPES LEAVE THE LINEAR CHAIN BEFORE IT STARTS.
                % Every branch below is linear -- a t-test, a mixed model,
                % or a mean/SD -- and none of them mean anything on angles
                % that wrap at +/-pi. The combination-bin branch further
                % down has always refused these types a linear test, so
                % without this the same document could call such a test
                % invalid in one section and report it in the next.
                sections{end + 1} = ReportSections.circularSection(blockLabel, measureType, ordinaryLabels); %#ok<AGROW>
            elseif isscalar(ordinaryLabels)
                if hasGroups
                    sections{end + 1} = ReportSections.betweenSection(blockLabel, measureType, ordinaryLabels{1}); %#ok<AGROW>
                else
                    sections{end + 1} = ReportSections.descriptiveSection(blockLabel, measureType, ordinaryLabels{1}); %#ok<AGROW>
                end
            elseif numel(ordinaryLabels) == 2 && ~useLmm
                sections{end + 1} = ReportSections.pairedSection(blockLabel, measureType, ordinaryLabels{1}, ordinaryLabels{2}); %#ok<AGROW>
            elseif numel(ordinaryLabels) >= 2
                % One section for every design that gets a linear mixed
                % model. Which of the four it is -- bin, bin x group,
                % bin x session, or all three two-way -- is read off the
                % plan inside lmmSection, not decided again here.
                sections{end + 1} = ReportSections.lmmSection(blockLabel, measureType, ordinaryLabels, plan); %#ok<AGROW>
            end
            % BESIDE the averaged model, never instead of it: the two answer
            % the same question from different data, and a reader comparing
            % them learns something a single number cannot say.
            if ~isempty(trialCsv) && numel(ordinaryLabels) >= 2 && ...
                    ~ReportSections.isCircularType(measureType)
                sections{end + 1} = ReportSections.singleTrialSection(blockLabel, measureType, ordinaryLabels); %#ok<AGROW>
            end

            for cb = 1:numel(comboBins)
                if hasGroups
                    % includeVsZero: skip for latency/circular types, same
                    % reason as the no-groups path (isDescriptiveOnlyType).
                    % includeBetweenGroups: skip ONLY for circular types --
                    % unlike the "vs zero" test, an ordinary linear
                    % between-groups comparison (a latency IS on a linear
                    % scale) is perfectly valid for a latency combo bin,
                    % just not for a circular one (see isCircularType).
                    sections{end + 1} = ReportSections.comboSectionGrouped(blockLabel, measureType, ...
                        comboBins(cb).label, comboBins(cb).recipeText, ...
                        ~ReportSections.isDescriptiveOnlyType(measureType), ~ReportSections.isCircularType(measureType)); %#ok<AGROW>
                else
                    sections{end + 1} = ReportSections.comboSection(blockLabel, measureType, ...
                        comboBins(cb).label, comboBins(cb).recipeText); %#ok<AGROW>
                end
            end
        end
    end

    % ONCE FOR THE WHOLE DOCUMENT, not once per window. The time-resolved
    % coherence describes the recording rather than any one measurement
    % window, and every window in a tagging export reads the same map.
    coherenceParts = {};
    if hasCoherenceExport(coherenceCsvs)
        named = {};
        if isstruct(coherenceCsvs) && isfield(coherenceCsvs, 'Channels')
            named = coherenceCsvs.Channels;
        end
        coherenceParts = {ReportSections.coherenceSection(named)};
    end

    % How the coherence values were estimated, right after the orientation and
    % before any result that quotes one (see coherenceMethodText).
    methodNote = {};
    if hasSpectral
        note = ReportSections.coherenceMethodText(entries);
        if ~isempty(note)
            methodNote = {note};
        end
        % RESS components, when a Spectral Measure row reads one: how they were
        % made, and each one's null (see ressSection).
        ress = ReportSections.ressSection(entries);
        if ~isempty(ress)
            methodNote{end + 1} = ress;
        end
    end

    parts = [{preambleText(csvFileName, reportTitle, groupColumn, hasGroups, plan, ...
                          grandAverageCsv, trialCsv, spectraCsv, coherenceCsvs)}, ...
             {readersGuideText(reportTitle, usesInSections(sections, 'bf10_ttest('), ...
                               usesInSections(sections, 'bf10_effect('))}, ...
             methodNote, sections, {closingText(reportTitle)}];
    parts = uniqueChunkLabels(parts);

    % Appended LAST, after the statistical summary, not interleaved with
    % the per-window sections above: this is an exploratory, non-
    % statistical addendum (no p-value, nothing feeds the omnibus table),
    % so it reads as a supplementary appendix to the confirmatory testing
    % above rather than as part of it. nargin < 3 (every pre-existing call
    % site) and an empty/omitted SOURCEESTIMATES both leave PARTS, and so
    % QMDTEXT, byte-for-byte identical to before this argument existed.
    if nargin >= 3 && ~isempty(sourceEstimates)
        sourceText = ReportSections.sourceEstimateSection(sourceEstimates);
        if ~isempty(sourceText)
            parts = [parts, {sourceText}];
        end
    end

    % After the tested sections and before the source addendum's place: the
    % coherence figures describe the recording the tests were run on, so
    % they belong with the results rather than in an appendix, but they
    % carry no test and must not interrupt the sections that do.
    parts = [parts, coherenceParts];

    qmdText = char(strjoin(parts, [newline newline]));
end

function tf = hasCoherenceExport(coherenceCsvs)
%HASCOHERENCEEXPORT  Whether either coherence file was written.
    tf = false;
    if ~isstruct(coherenceCsvs)
        return;
    end
    for field = {'Trace', 'Map'}
        if isfield(coherenceCsvs, field{1}) && ...
                ~isempty(char(string(coherenceCsvs.(field{1}))))
            tf = true;
            return;
        end
    end
end

function blocks = erpBlocks(EEG)
%ERPBLOCKS  One block per Measure window, .label/.measureTypes (from
%   measureRowTypes) -- the ERP counterpart of spectralBlocks.
    blocks = struct('label', {}, 'measureTypes', {});
    for w = 1:numel(EEG.measurements)
        win = EEG.measurements{w};
        blocks(end + 1) = struct('label', char(string(win.label)), ...
            'measureTypes', {measureRowTypes(win)}); %#ok<AGROW>
    end
end

function blocks = spectralBlocks(EEG)
%SPECTRALBLOCKS  One block per named frequency in EEG.spectralMeasures,
%   .label/.measureTypes -- the Spectral counterpart of erpBlocks. Every
%   named frequency always carries power/amplitude/snr/itc/phase (see
%   SpectralMeasure.m); coherence/phaselag are additional, only present
%   when that frequency was measured against a reference channel --
%   exactly mirroring exportSpectralCSV.m's own writeEntry, so this can
%   never claim a measure_type the CSV does not actually have a column
%   value for.
    blocks = struct('label', {}, 'measureTypes', {});
    for w = 1:numel(EEG.spectralMeasures)
        m = EEG.spectralMeasures{w};
        types = {'power', 'amplitude', 'snr', 'itc', 'phase'};
        if ~isempty(strtrim(char(string(m.refChannel))))
            types = [types, {'coherence', 'phaselag'}]; %#ok<AGROW>
        end
        blocks(end + 1) = struct('label', char(string(m.label)), 'measureTypes', {types}); %#ok<AGROW>
    end
end

% ======================================================================= %
%  Bin classification -- done in MATLAB, not R, for the same reason the
%  design is: EEG.bindesc(b).combo is not recoverable from the flat CSV
%  at all.
% ======================================================================= %
function [ordinaryLabels, comboBins] = classifyBins(EEG)
%CLASSIFYBINS  ORDINARYLABELS (cellstr, real conditions) and COMBOBINS (a
%   struct array, .label/.recipeText, one per DefineBins/Average
%   combination bin) from EEG.bindesc. A dataset with no bindesc at all
%   (an unbinned Average) is treated as one implicit ordinary bin, "1" --
%   csvBinLabel's own fallback for exactly this case, so this matches
%   whatever bin value actually ended up in the CSV.
    comboBins = struct('label', {}, 'recipeText', {});
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        ordinaryLabels = {'1'};
        return;
    end
    bindesc = EEG.bindesc;
    isCombo = false(1, numel(bindesc));
    if isfield(bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {bindesc.combo});
    end
    ordinaryLabels = {bindesc(~isCombo).label};
    for b = find(isCombo)
        comboBins(end + 1) = struct('label', char(string(bindesc(b).label)), ...
            'recipeText', comboRecipeText(bindesc, bindesc(b))); %#ok<AGROW>
    end
end

function txt = comboRecipeText(bindesc, entry)
%COMBORECIPETEXT  A combination bin's own recipe as readable text, e.g.
%   "Rare - Frequent" or "0.5*Left + 0.5*Right" -- entry.combo's own .bin
%   values are referenced bins' .index (Average.m's own convention), not
%   array positions, so they are mapped back to a label via bindesc's own
%   .index field.
    indices = [bindesc.index];
    parts = strings(1, numel(entry.combo));
    for t = 1:numel(entry.combo)
        refLabel = bindesc(indices == entry.combo(t).bin).label;
        coeff = entry.combo(t).coeff;
        if t == 1
            if coeff < 0; sgn = "-"; else; sgn = ""; end
        else
            if coeff < 0; sgn = " - "; else; sgn = " + "; end
        end
        if abs(coeff) == 1
            magTxt = "";
        else
            magTxt = string(sprintf('%.3g*', abs(coeff)));
        end
        parts(t) = sgn + magTxt + string(refLabel);
    end
    txt = char(strjoin(parts, ""));
end

function parts = uniqueChunkLabels(parts)
%UNIQUECHUNKLABELS  Make every '#| label:' in the document distinct.
%
%   ReportSections.labelPiece is lossy on purpose -- it lowercases and
%   collapses every run of non-alphanumerics to a single hyphen -- so two
%   different window or measure labels can sanitise to the same chunk
%   label. 'N400 (a)' and 'N400 [a]' both become 'n400-a'. knitr then
%   refuses the document outright at render time, and R's own parse()
%   cannot warn about it, because parse() never looks at '#|' option
%   lines: the failure arrives only once someone tries to render.
%
%   Resolved at assembly rather than in labelPiece, because uniqueness is
%   a property of the whole document and no single section can know what
%   the others chose. A repeat gets '-2', '-3' and so on appended, which
%   keeps the readable stem that makes these labels worth having.
    seen = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:numel(parts)
        lines = strsplit(parts{i}, newline);
        changed = false;
        for k = 1:numel(lines)
            token = regexp(lines{k}, '^#\|\s*label:\s*(\S+)\s*$', 'tokens', 'once');
            if isempty(token)
                continue;
            end
            label = token{1};
            if isKey(seen, label)
                seen(label) = seen(label) + 1;
                lines{k} = sprintf('#| label: %s-%d', label, seen(label));
                changed = true;
            else
                seen(label) = 1;
            end
        end
        if changed
            parts{i} = strjoin(lines, newline);
        end
    end
end

function lines = coherenceReadLines(coherenceCsvs)
%COHERENCEREADLINES  Read the trace, map and reference exports, or set them to NULL.
%   The reference file has no channel column, so the text columns are
%   converted only where they exist.
    lines = {};
    for spec = {{'Trace', 'cohtrace'}, {'Map', 'cohmap'}, {'Reference', 'cohref'}}
        field = spec{1}{1};
        name = spec{1}{2};
        file = '';
        if isstruct(coherenceCsvs) && isfield(coherenceCsvs, field)
            file = char(string(coherenceCsvs.(field)));
        end
        if isempty(file)
            lines = [lines, {sprintf('%s <- NULL', name)}]; %#ok<AGROW>
            continue;
        end
        lines = [lines, { ...
            sprintf('%s_file <- "%s"', name, ReportSections.rLit(file)) ...
            sprintf(['%s <- if (file.exists(%s_file)) read_csv(%s_file, ' ...
                     'show_col_types = FALSE) else NULL'], name, name, name) ...
            sprintf(['if (!is.null(%s)) %s <- %s %%>%% ' ...
                     'mutate(across(any_of(c("bin", "channel")), as.character))'], ...
                name, name, name)}]; %#ok<AGROW>
    end
end

function text = readersGuideText(reportTitle, hasTTestBayes, hasModelBayes)
%READERSGUIDETEXT  A short orientation, placed before the results.
%
%   The document now distinguishes primary from secondary tests, reports
%   estimates before verdicts, and carries Bayes factors beside p-values.
%   Each of those is a deliberate choice, and a reader who does not know
%   which choice was made can misread the numbers in a specific and
%   predictable way: treating a secondary row as an independent finding,
%   or reading a large p as evidence of no effect. Saying so once, at the
%   top, costs a paragraph and prevents both.
%
%   EVERY SENTENCE HERE MUST DESCRIBE THE DOCUMENT AS IT IS. The guide said
%   for a long time that each result was "stated as an estimate first: which
%   condition was larger, by how much", after the narrated sentences that did
%   so had been replaced by tables, and that the raw difference was reported
%   beside every standardised effect, which it never was. REPORTTITLE sets the
%   word for a block: frequencies in a spectral report, time windows otherwise.
%
%   HASTTESTBAYES and HASMODELBAYES say which sections of THIS report carry a
%   Bayes factor (beside a t-test, and for a mixed model's effect), and the
%   Bayes-factor paragraph says exactly that. It used to promise them "beside
%   the t-tests" in a report of four-condition mixed models, which has no
%   t-test at all, and is left out when the report has neither.
    if strcmpi(reportTitle, 'Spectral')
        units = 'frequencies';
    else
        units = 'time windows';
    end
    bayes = bayesParagraph(hasTTestBayes, hasModelBayes);
    lines = [{ ...
        '## How to read this report' ...
        '' ...
        ['Each section below gives the **descriptive statistics** of its conditions first, ' ...
         'then the **test** that answers that section''s question, chosen for its design: a ' ...
         'paired test for two conditions; a mixed model for three or more conditions, or for ' ...
         'conditions crossed with groups or sessions; a test between groups for a single ' ...
         'condition measured in several groups; and a test against zero for a combination bin ' ...
         'such as a difference wave. Where the values depart from normality, a rank-based test ' ...
         'replaces the *t*-test, and the table names the test that was run. A caption under ' ...
         'each result says what that test tests. Phases and phase lags, which are angles, and ' ...
         'the latencies of combination bins are described but not tested, and their sections ' ...
         'say why.'] ...
        '' ...
        ['**Primary and secondary tests.** The main test of each section is a primary test, and ' ...
         'the primary tests are corrected together for multiple comparisons (Benjamini-Hochberg, ' ...
         'controlling the false discovery rate). Tests of a combination bin and single-trial ' ...
         'models are reported as *secondary*: they are computed from the same recordings, and a ' ...
         'difference bin asks again about conditions the primary test has already compared. ' ...
         'They carry an uncorrected *p* and no adjusted value. The summary at the end of the ' ...
         'report explains the correction and lists these tests in one table.'] ...
        ''}, ...
        bayes, ...
        {['**Effect sizes** are standardised: Cohen''s *d* (*d*~z~ for a paired test) beside a ' ...
         '*t*-test, the rank-biserial *r* beside a rank-based test, and partial eta-squared for ' ...
         'a mixed model, each with a confidence interval where one could be computed. The ' ...
         'interval shows the range of effect sizes compatible with the data, which a *p*-value ' ...
         'alone does not. A standardised effect is comparable across studies; the size of an ' ...
         'effect in the measure''s own units is read from the condition means in the same ' ...
         'section''s descriptive table, and, after a mixed model, from the estimates in its ' ...
         'pairwise comparisons.'] ...
        '' ...
        ['**What is not claimed.** These tests were run on the ' units ', channels and ' ...
         'conditions chosen during analysis. Where those choices were made after ' ...
         'inspecting the data, the *p*-values below are optimistic in a way no correction ' ...
         'applied here can repair, and the effect sizes are biased away from zero for the ' ...
         'same reason, so the intervals will cover the true value less often than their ' ...
         'stated level. Pre-specification of the ' units ' and channels, or replication in ' ...
         'an independent sample, are the remedies; nothing computed within this document ' ...
         'is one.'] ...
        '' ''}];
    text = strjoin(lines, newline);
end

function lines = bayesParagraph(hasTTestBayes, hasModelBayes)
%BAYESPARAGRAPH  The reading guide's Bayes-factor paragraph (and the blank
%   line after it), naming only the kinds this report has; {} for neither.
    if ~hasTTestBayes && ~hasModelBayes
        lines = {};
        return;
    end
    if hasTTestBayes && hasModelBayes
        where = 'beside the *t*-tests and in each mixed-model section';
    elseif hasTTestBayes
        where = 'beside the *t*-tests';
    else
        where = 'in each mixed-model section';
    end
    text = ['**Bayes factors** appear ' where ', because a non-significant *p* does not ' ...
        'distinguish evidence for no effect from no evidence either way. BF~10~ above 1 favours ' ...
        'an effect, below 1 favours its absence, and the accompanying word gives the ' ...
        'conventional reading of its size (Jeffreys, 1961, in the wording of Lee and ' ...
        'Wagenmakers, 2013).'];
    if hasTTestBayes
        text = [text ' Beside a *t*-test they use the default JZS prior, a Cauchy distribution ' ...
            'on the effect size with scale sqrt(2)/2, as in JASP. Where the data departed from ' ...
            'normality and a rank-based test was reported instead, no Bayes factor is given, and ' ...
            'beside a Welch *t*-test the Bayes factor assumes equal variances, since no Welch form ' ...
            'of it is available.'];
    end
    if hasModelBayes
        text = [text ' For a mixed model the Bayes factor is for the effect the section tests ' ...
            '(the condition effect, or the interaction in a group or session design): the model ' ...
            'with that effect against the same model without it, each with a random intercept ' ...
            'per person and the default priors of Rouder et al. (2012). Where the mixed model also ' ...
            'let the effect vary between people, the Bayes factor does not.'];
    end
    lines = {text, ''};
end

function tf = usesInSections(sections, marker)
%USESINSECTIONS  Whether any of the report's sections contains MARKER.
    tf = any(cellfun(@(s) contains(s, marker), sections));
end

function text = preambleText(csvFileName, reportTitle, groupColumn, hasGroups, plan, grandAverageCsv, trialCsv, spectraCsv, coherenceCsvs)
%PREAMBLETEXT  The YAML header + setup chunk shared by every report kind.
%   REPORTTITLE ("ERP" or "Spectral") names the report in its own title
%   and intro comment. GROUPCOLUMN is the CSV column that plays "window"'s
%   role for this report kind (literally "window" for an ERP export,
%   "frequency_label" for a Spectral one -- see exportMeasurementsCSV.m/
%   exportSpectralCSV.m's own column lists). Every +ReportSections
%   section-builder function (descriptiveSection, pairedSection, ...)
%   hardcodes `window ==` in its own R filter -- rather than threading GROUPCOLUMN
%   through every one of them, the read chunk here renames GROUPCOLUMN to
%   "window" ONCE, right after read_csv, so the rest of the generated R
%   code (and every section-builder function that emits it) does not need
%   to know or care which report kind it is building for.
%
%   HASGROUPS (from the plan's own betweenFactors) does the
%   same thing for the CSV's "group" column: when true, every subject
%   with no group assigned is dropped from `dat` HERE, once, with a
%   printed diagnostic -- so betweenSection and lmmSection can both just
%   assume every remaining row already has a usable group, the same way
%   every section already assumes dataset_type == "subject" was already
%   filtered for it.
    readLines = {'dat <- read_csv(csv_file, show_col_types = FALSE) %>%'};
    if ~strcmp(groupColumn, 'window')
        readLines{end + 1} = sprintf('  rename(window = %s) %%>%%', groupColumn);
    end
    readLines = [readLines, { ...
        '  filter(dataset_type == "subject") %>%' ...
        '  mutate(dataset = factor(dataset), bin = factor(bin))' ...
        '' ...
        }];

    % THE GRAND AVERAGES, WHEN THERE ARE ANY. Read here, once, into `ga`,
    % so waveformSection can simply use it. Guarded on the file existing
    % rather than on it having been named: a report can be rendered from a
    % directory the export was moved out of, and losing the waveforms is a
    % far better outcome than an unrenderable document. Sections that use
    % `ga` all check nrow() first for the same reason.
    if isempty(grandAverageCsv)
        readLines = [readLines, {'ga <- NULL'}];
    else
        readLines = [readLines, { ...
            sprintf('ga_file <- "%s"', ReportSections.rLit(grandAverageCsv)) ...
            'ga <- if (file.exists(ga_file)) read_csv(ga_file, show_col_types = FALSE) else NULL' ...
            'if (!is.null(ga)) ga <- ga %>% mutate(bin = as.character(bin), channel = as.character(channel))' ...
            }];
    end

    % THE TRIALS, when a per-trial export accompanied this one. Same
    % best-effort guard as the grand averages: a missing file costs the
    % single-trial sections, never the document.
    if isempty(trialCsv)
        readLines = [readLines, {'tdat <- NULL'}];
    else
        readLines = [readLines, { ...
            sprintf('trial_file <- "%s"', ReportSections.rLit(trialCsv)) ...
            'tdat <- if (file.exists(trial_file)) read_csv(trial_file, show_col_types = FALSE) else NULL' ...
            'if (!is.null(tdat)) tdat <- tdat %>% filter(dataset_type == "subject") %>%' ...
            '  mutate(person_id = as.character(person_id), bin = factor(bin),' ...
            '         channel = as.character(channel))' ...
            }];
    end

    % The spectra, when a spectral export wrote them. Same best-effort guard
    % as the grand averages and the trials: a missing file costs the figure,
    % never the document.
    if isempty(spectraCsv)
        readLines = [readLines, {'spec <- NULL'}];
    else
        readLines = [readLines, { ...
            sprintf('spec_file <- "%s"', ReportSections.rLit(spectraCsv)) ...
            'spec <- if (file.exists(spec_file)) read_csv(spec_file, show_col_types = FALSE) else NULL' ...
            'if (!is.null(spec)) spec <- spec %>% filter(dataset_type == "subject") %>%' ...
            '  mutate(bin = as.character(bin), channel = as.character(channel))' ...
            }];
    end

    % The time-resolved coherence, when a CoherenceMap result was exported
    % alongside. Same best-effort guard as the others: a missing file costs
    % the figures and nothing else.
    readLines = [readLines, coherenceReadLines(coherenceCsvs)];

    readLines = [readLines, { ...
        ReportDoc.template('preamble-open.qmd') ...
        '         session = ifelse(is.na(session), "", session))'}];

    lines = ReportDoc.lines([ReportDoc.yamlHeader(['Alakazam ' reportTitle ' Statistical Report']), { ...
        '' ...
        '<!--' ...
        ['Alakazam: statistical report for exported ' reportTitle ' measurements.'] ...
        ReportDoc.template('preamble-intro.qmd') ...
        }, ReportDoc.packageBootstrap({'tidyverse', 'rstatix', 'coin', 'ggpubr', 'gt', ...
            'lme4', 'lmerTest', 'emmeans', 'performance', 'effectsize', 'BayesFactor'}), { ...
        '' ...
        'csv_file <- "__CSVFILE_R__"' ...
        ... % What one block of the report is, in words, for the block-match diagnostic.
        sprintf('block_unit <- "%s"', blockUnitWord(groupColumn))}, ...
        readLines, ...
        { ...
        '' ...
        'if (n_distinct(dat$dataset) < 2) {' ...
        '  stop("Need at least two subjects (dataset_type == subject) for statistics.")' ...
        '}' ...
        ''}, ...
        groupFilterLines(hasGroups), ...
        { ...
        ReportDoc.template('omnibus-table-init.R') ...
        }, ReportDoc.apaHelpers(), { ...
        ReportDoc.template('violin-layers.R') ...
        '```' ...
        }, ...
        groupsSummaryChunk(hasGroups), ...
        designNoteLines(plan)]);
    text = strrep(strjoin(lines, newline), '__CSVFILE_R__', ReportSections.rLit(csvFileName));
end

function lines = groupFilterLines(hasGroups)
%GROUPFILTERLINES  R lines (still inside the invisible setup chunk) that
%   drop every subject with no group assigned from `dat`, once, when
%   HASGROUPS -- see preambleText's own comment. {} (a no-op splice) when
%   HASGROUPS is false, so a report with no between-subjects grouping
%   generates byte-identical R to before this feature existed.
    if ~hasGroups
        lines = {};
        return;
    end
    lines = ReportDoc.template('preamble-omnibus-tail.Rpart');
end

function lines = designNoteLines(plan)
%DESIGNNOTELINES  A short, visible statement of the model the report is
%   about to fit, and of anything it had to give up to fit it.
%
%   Two separate jobs. The first is ordinary courtesy: a reader should not
%   have to reverse-engineer the design from the F-tests, so when session
%   is in play the formula is printed once, near the top.
%
%   The second matters more. When session was recorded but could not be
%   used -- an empty group x session cell, a cell holding one subject, or
%   nobody actually measured twice -- reportDesignPlan drops it and this
%   prints WHY. Without that the report would quietly present a simpler
%   model as though it were the intended one, which is the failure mode
%   worth spending a paragraph to avoid: lmer does not refuse an
%   unestimable interaction so much as return something that looks fine.
%
%   Plain markdown rather than a chunk: there is nothing to compute.
    lines = {};
    if ~isempty(plan.fallbackReason)
        lines = { ...
            '' ...
            '::: {.callout-note}' ...
            '## A simpler model than the data seemed to offer' ...
            '' ...
            plan.fallbackReason ...
            ':::'};
        return;
    end
    if numel(plan.withinFactors) < 2
        return;   % no session: the sections speak for themselves
    end
    % Only a design with all three factors HAS a three-way interaction to
    % omit; saying so for a two-factor model would describe a decision that
    % was never available.
    if isempty(plan.betweenFactors)
        omissionNote = '';
    else
        omissionNote = ['The three-way interaction is deliberately omitted: `^2` fits every ' ...
            'main effect and every two-way interaction and nothing beyond. '];
    end

    lines = { ...
        '' ...
        '::: {.callout-note}' ...
        '## Design' ...
        '' ...
        ['Session is treated as a within-subjects factor. Fixed effects: `' plan.fixed ...
         '`; random effects: `' plan.random '`.'] ...
        '' ...
        [omissionNote 'Post-hoc contrasts are kept to at most one family, and only where ' ...
         'the term they follow is significant; `emmeans` is loaded and the fitted model is ' ...
         'in scope if you want to add more.'] ...
        ':::'};
end

function chunk = groupsSummaryChunk(hasGroups)
%GROUPSSUMMARYCHUNK  A short, visible chunk (unlike the invisible setup
%   chunk groupFilterLines' own logic lives in) reporting which subjects
%   were excluded for having no group, and the resulting group sizes --
%   printed once, near the top of the report, rather than leaving the
%   reader to infer it from the per-channel counts scattered through every
%   section below. {} (no chunk at all) when HASGROUPS is false.
    if ~hasGroups
        chunk = {};
        return;
    end
    chunk = ReportDoc.template('preamble-design-note.qmd');
end


function word = blockUnitWord(groupColumn)
%BLOCKUNITWORD  "time window" for an ERP export, "frequency" for a spectral one.
    if strcmp(groupColumn, 'window')
        word = 'time window';
    else
        word = 'frequency';
    end
end

function text = closingText(reportTitle)
%CLOSINGTEXT  The summary that closes the report: every test above in one
%   table, the primary family corrected, and a forest plot of the effects.
%
%   IT RUNS NO NEW TEST, and the prose now says so before anything else. It
%   used to open straight on "the primary family is 4 planned condition
%   comparisons", which assumed the reader already knew what the section
%   was for, what a family is and why only some rows were in it, and the
%   table beneath gave its columns as the R variable names (window,
%   design, p_bh) with codes such as lmm_within in them. The explanation
%   is static prose, so it is there whether or not any test ran, and the
%   table now uses the same words the prose does.
%
%   REPORTTITLE is "ERP" or "Spectral", so that a spectral report talks
%   about frequencies rather than time windows. The column holding them is
%   called window in both, which is exactly why the heading is set here
%   rather than left to the variable name.
    if strcmpi(reportTitle, 'Spectral')
        unit = 'frequency';
        units = 'frequencies';
        unitHeading = 'Frequency';
    else
        unit = 'time window';
        units = 'time windows';
        unitHeading = 'Time window';
    end

    lines = ReportDoc.lines({ ...
        '## Summary Across All Tests' ...
        '' ...
        ... % Not "every test reported above": the pairwise comparisons after a mixed
        ... % model and the per-group tests of a combination bin are not in the table.
        ['This section runs no new test on the data. It gathers the main test of every ' ...
         'section above into one table, so that the report can be judged as a whole rather ' ...
         'than one section at a time, and it adds the one thing no single section can: a ' ...
         'correction for having run many tests. The pairwise comparisons that follow a mixed ' ...
         'model, and the tests of a combination bin against zero within each group, are not ' ...
         'repeated here.'] ...
        '' ...
        ['Each section above tests one ' unit ', measure and channel, and reports its own ' ...
         '*p*. Read one at a time, each *p* keeps its stated error rate. Read together they ' ...
         'do not: across twenty independent tests at *p* < .05, about one would be ' ...
         'significant by chance even if there were no effect anywhere. The more ' units ...
         ', measures and channels a report covers, the more of its significant results are ' ...
         'expected to be false positives, and that is what the correction addresses.'] ...
        '' ...
        ['**Primary tests** are the main test of each section: for each ' unit ', measure ' ...
         'and channel, the test of whether the conditions differ, or, where there are groups ' ...
         'or sessions, whether the groups differ or whether the difference between conditions ' ...
         'itself differs between groups or sessions. These are the questions the analysis was ' ...
         'set up to answer.'] ...
        '' ...
        ['A **family** is a set of tests corrected for multiple comparisons as one group: ' ...
         'the correction takes into account how many tests are in the set, and nothing ' ...
         'outside it. The **primary family** is the set of all primary tests in this report, ' ...
         'one per ' unit ', measure and channel. It is corrected with the Benjamini-Hochberg ' ...
         'procedure, which controls the false discovery rate: among the primary results that ' ...
         'remain significant after correction, the expected proportion of false positives is ' ...
         'at most 5%. Because the correction depends on how many tests are in the family, ' ...
         'adding ' units ', measures or channels to an analysis generally makes it harder for ' ...
         'each primary result to survive, unless the tests added are themselves clearly ' ...
         'significant.'] ...
        '' ...
        ... % Not "restates a two-condition comparison": exact for a mean amplitude, but
        ... % a peak measured on a difference wave is not the difference of the peaks.
        ['**Secondary tests** are the tests of a combination bin (such as a difference wave), ' ...
         'against zero or between groups, and the single-trial models. They are computed ' ...
         'from the same recordings as the primary tests, and a difference bin asks again ' ...
         'about conditions the primary test has already compared. They are left out of the ' ...
         'family, so that the correction of the primary tests does not depend on how many ' ...
         'derived tests the export happened to include, and their *p* is shown uncorrected.'] ...
        '' ...
        ['Each row of the table gives the ' unit ' and measure, the channel, the comparison ' ...
         'made ("all conditions" for a test of all of them at once), the design and test ' ...
         'used, the uncorrected *p*, whether the test is primary or secondary, and, for ' ...
         'primary tests, the corrected *p*. The plot beneath the table shows each test''s ' ...
         'effect size with its 95% confidence interval where the test provides one, in ' ...
         'separate panels for each kind of effect size (Cohen''s *d*, the rank-biserial *r*, ' ...
         'partial eta-squared, and the raw difference a single-trial model estimates for two ' ...
         'conditions), because they are on different scales and cannot be compared directly.'] ...
        '' ...
        '```{r}' ...
        '#| label: summary-all-tests' ...
        '#| results: asis' ...
        '#| fig-height: 7' ...
        ... % Rows without a p (a channel whose test could not run) are dropped
        ... % before anything is counted, so a report where no test ran says so
        ... % instead of "holds 0 test(s)" over an empty table.
        ReportDoc.template('summary-correction.Rpart') ...
        ... % By the TEST first: a paired, one-sample or two-group design whose data
        ... % were not normal reports a rank-based test with a rank-biserial r, and
        ... % was labelled Cohen's d here because only the design was looked at.
        '        effect_type = case_when(' ...
        '          test %in% c("wilcoxon_signed_rank_test", "mann_whitney_u") ~ "Rank-biserial r",' ...
        '          test %in% c("paired_t_test", "one_sample_t_test", "welch_t_test") ~ "Cohen''s d / dz",' ...
        '          design == "single_trial_lmm" ~ "Raw difference (single-trial model)",' ...
        ... % Matched by PREFIX, not by an explicit list: lmm_session was added
        ... % as a design and this list was not updated with it, so a session
        ... % report's partial eta-squared was labelled "effect size" and
        ... % faceted away from the other LMM effects it belongs beside.
        ReportDoc.template('summary-effect-labels.Rpart') ...
        });
    text = strjoin(lines, newline);
    text = strrep(text, '__UNITHEADING__', unitHeading);
end
