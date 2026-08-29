classdef ReportFixtures
%REPORTFIXTURES  The one shared fixture library behind every Quarto-report
%   test file (QuartoReportDispatchTest, QuartoReportTextContractTest,
%   QuartoReportCsvContractTest, QuartoReportRSyntaxTest,
%   QuartoReportRenderTest and QuartoReportKnownGapTest).
%
%   Deliberately NOT a matlab.unittest.TestCase subclass, and carrying no
%   Test methods at all, so runtests() walking the tests folder never
%   collects it: it is a classdef purely so a dozen helpers share one
%   namespace (ReportFixtures.chunkLabels, ReportFixtures.erpEntries, ...)
%   instead of scattering a dozen loose function files through tests/.
%
%   Three kinds of entry point:
%
%     - BUILDERS turn a design description (how many ordinary bins, how
%       many combination bins, which measure windows, which
%       between-subjects groups) into the ENTRIES struct array that
%       generateQuartoReport, exportMeasurementsCSV and exportSpectralCSV
%       ALL accept. One builder feeds all three deliberately: the fixture
%       a text assertion reads is then the very same fixture that wrote
%       the CSV, which is what lets a test tie the exporter's column
%       contract to the generated R's use of it (see the CSV contract
%       test) rather than restating either side a third time.
%
%     - PARSERS pull structure back out of a generated .qmd: its ordered
%       chunk-label census (chunkLabels), its markdown headings
%       (headings), its ```{r} chunk bodies (rChunks/rCode), and the one
%       chunk carrying a given label (chunkFor). The census is the
%       load-bearing one -- a section heading is a strict PREFIX of other
%       section headings ("## N400 -- mean\_amplitude" prefixes both the
%       "(Between Subjects)" and the "(Mixed Design)" variants), so a
%       verifySubstring on a bare heading cannot tell those designs
%       apart, whereas the chunk label (desc-/between-/paired-/mixed-/
%       anova-/combo-/combo-desc-/combo-grouped-) names the section
%       builder that actually ran.
%
%     - TOOL DISCOVERY locates Rscript and quarto without requiring
%       either on PATH -- neither is, on a stock Windows R + Quarto
%       install -- and returns '' rather than erroring, so a test can
%       assumeTrue its way to a clean skip instead of a spurious failure
%       on a machine with no R.
%
%   Every builder produces DETERMINISTIC values: no rand, no seed, no
%   tolerance-fudging. pairedGroundTruthEntries goes further and is
%   constructed so the paired t-test over it is analytically exact
%   (t = 10.000 on 24 df, Cohen's dz = 2.000), which is what lets a
%   render test assert a number rather than merely "something was
%   printed".
%
%   Not a test file: it has no Test methods and is never run on its own.

    methods (Static)

        % ================================================================ %
        %  Bin descriptors (EEG.bindesc)
        % ================================================================ %

        function bins = bindesc(labels)
        %BINDESC  Ordinary (non-combination) bins from LABELS (a cellstr),
        %   .index running 1:numel(LABELS) and .combo empty throughout --
        %   the shape EEG.bindesc has for a plain DefineBins result.
            n = numel(labels);
            bins = struct('index', num2cell(1:n), 'label', labels(:)', ...
                'combo', repmat({[]}, 1, n));
        end

        function bins = bindescIndexed(indices, labels)
        %BINDESCINDEXED  Ordinary bins whose .index values are INDICES
        %   rather than 1:n, so a test can tell a lookup that honours
        %   .index from one that silently uses the array position (see
        %   comboRecipeText's own header comment -- a combination bin's
        %   .bin values are referenced bins' .index, an Average.m
        %   convention, not positions).
            n = numel(labels);
            bins = struct('index', num2cell(reshape(double(indices), 1, n)), ...
                'label', labels(:)', 'combo', repmat({[]}, 1, n));
        end

        function bins = withCombo(bins, label, coeffs, referencedIndices)
        %WITHCOMBO  BINS with one further COMBINATION bin appended: LABEL,
        %   .index one past the highest already present, and a .combo
        %   struct array pairing COEFFS with REFERENCEDINDICES (the .index
        %   values of the bins it combines, NOT their array positions).
            terms = struct('coeff', num2cell(reshape(double(coeffs), 1, [])), ...
                'bin', num2cell(reshape(double(referencedIndices), 1, [])));
            if isempty(bins)
                nextIndex = 1;
            else
                nextIndex = max([bins.index]) + 1;
            end
            bins(end + 1) = struct('index', nextIndex, 'label', char(label), ...
                'combo', {terms});
        end

        function bins = bindesc3WithCombo()
        %BINDESC3WITHCOMBO  The workhorse design: three ordinary bins
        %   A/B/C plus one combination bin "A-B" (1*A - 1*B), i.e. the
        %   3+-ordinary-bin omnibus path AND the combination-bin path in
        %   one fixture.
            bins = ReportFixtures.bindesc({'A', 'B', 'C'});
            bins = ReportFixtures.withCombo(bins, 'A-B', [1, -1], [1, 2]);
        end

        function bins = comboOnlyBindesc()
        %COMBOONLYBINDESC  A pathological but perfectly constructible
        %   design in which EVERY bin is a combination bin, so
        %   classifyBins returns zero ordinary labels and
        %   generateQuartoReport's own 1/2/3+ if-chain has no branch to
        %   take (it has no else). Used to pin what the orchestrator does
        %   with a design whose main comparison simply does not exist.
            bins = ReportFixtures.bindesc({'A-B', 'C-D'});
            bins(1).combo = struct('coeff', {1, -1}, 'bin', {1, 2});
            bins(2).combo = struct('coeff', {1, -1}, 'bin', {2, 1});
        end

        % ================================================================ %
        %  Block specifications (one Measure window / one named frequency)
        % ================================================================ %

        function spec = windowSpec(label, measure, varargin)
        %WINDOWSPEC  One ERP Measure window, as a SPEC: everything
        %   measureRowTypes and exportMeasurementsCSV read from a window
        %   EXCEPT its .amplitude/.latency/.area matrices, whose size
        %   depends on how many bins the design has -- erpEntries
        %   materialises those. Name-value options: Channels (default
        %   {'Cz'}), Start (300), Stop (500), AreaMode (''), Scope (''),
        %   Width (NaN).
        %
        %   MEASURE is the Measure dialog's own measure name ('Mean
        %   Amplitude', 'Peak', 'Peak Area', 'Integral', 'Fractional Peak
        %   Latency', 'Fractional Area Latency'), which is what decides
        %   how many measure_type rows this one window expands into --
        %   'Peak Area' with a band scope expands into three, and is
        %   therefore the window to reach for when a test wants the
        %   blocks x types x combos product exercised as a genuine
        %   product rather than a coincidence of twos.
            p = inputParser();
            p.addParameter('Channels', {'Cz'});
            p.addParameter('Start', 300);
            p.addParameter('Stop', 500);
            p.addParameter('AreaMode', '');
            p.addParameter('Scope', '');
            p.addParameter('Width', NaN);
            p.parse(varargin{:});
            o = p.Results;

            spec = struct('kind', 'erp', 'label', char(label), ...
                'measure', char(measure), 'start', o.Start, 'stop', o.Stop, ...
                'channels', {o.Channels}, 'areaMode', o.AreaMode, ...
                'scope', o.Scope, 'width', o.Width, 'freq', NaN, 'refChannel', '');
        end

        function spec = frequencySpec(label, varargin)
        %FREQUENCYSPEC  One Spectral Measure frequency, as a SPEC (the
        %   frequency-domain sibling of windowSpec). Name-value options:
        %   Channels (default {'Pz'}), Freq (10), RefChannel ('').
        %
        %   REFCHANNEL is the branch that matters: a named frequency
        %   always carries power/amplitude/snr/itc/phase, and additionally
        %   coherence/phaselag ONLY when it was measured against a
        %   reference channel -- in both spectralBlocks (which decides
        %   what the report analyses) and exportSpectralCSV's own
        %   writeEntry (which decides what the CSV actually contains).
            p = inputParser();
            p.addParameter('Channels', {'Pz'});
            p.addParameter('Freq', 10);
            p.addParameter('RefChannel', '');
            p.parse(varargin{:});
            o = p.Results;

            spec = struct('kind', 'spectral', 'label', char(label), ...
                'measure', '', 'start', NaN, 'stop', NaN, ...
                'channels', {o.Channels}, 'areaMode', '', 'scope', '', ...
                'width', NaN, 'freq', o.Freq, 'refChannel', char(o.RefChannel));
        end

        % ================================================================ %
        %  Entry builders (the ENTRIES struct array every consumer takes)
        % ================================================================ %

        function entries = erpEntries(varargin)
        %ERPENTRIES  An ERP export's ENTRIES: .subject/.datasetType/
        %   .group/.person/.session/.EEG, with EEG.bindesc and
        %   EEG.measurements populated. Accepted by generateQuartoReport
        %   AND exportMeasurementsCSV unchanged.
        %
        %   Name-value options:
        %     Bindesc      bins (default one ordinary bin, 'A')
        %     Windows      cell of windowSpec results (default one 'N400'
        %                  Mean Amplitude window on Cz)
        %     Groups       cellstr, ONE ENTRY PER ELEMENT -- so this also
        %                  sets how many subjects there are (default
        %                  {'', ''}, two ungrouped subjects, which is the
        %                  minimum the generated R itself insists on)
        %     DatasetTypes cellstr, 'subject' or 'grand_average'
        %                  (default all 'subject')
        %     Subjects     cellstr of dataset names (default s1, s2, ...)
        %     Persons      cellstr (default: each subject is its own
        %                  person, matching WorkSpace.personFor)
        %     Sessions     cellstr (default all '')
        %     Values       cell, numel(Groups) x numel(Windows), each a
        %                  nChannels x nBins AMPLITUDE matrix; [] (the
        %                  default) fills every matrix deterministically
        %                  instead. Latency/area always stay deterministic
        %                  -- a fixture that needs an exact answer uses a
        %                  Mean Amplitude window, where amplitude is the
        %                  only matrix the CSV reads.
            o = parseEntryOptions(varargin, ReportFixtures.bindesc({'A'}), ...
                {ReportFixtures.windowSpec('N400', 'Mean Amplitude')}, 'Windows');
            entries = buildEntries(o, 'erp');
        end

        function entries = spectralEntries(varargin)
        %SPECTRALENTRIES  A Spectral export's ENTRIES, EEG.bindesc plus
        %   EEG.spectralMeasures. Same name-value options as erpEntries,
        %   except that Windows is named Measures and holds frequencySpec
        %   results (default one '10Hz' frequency on Pz, no reference
        %   channel). Accepted by generateQuartoReport AND
        %   exportSpectralCSV unchanged.
            o = parseEntryOptions(varargin, ReportFixtures.bindesc({'A'}), ...
                {ReportFixtures.frequencySpec('10Hz')}, 'Measures');
            entries = buildEntries(o, 'spectral');
        end

        function entries = erpAndSpectralEntries(varargin)
        %ERPANDSPECTRALENTRIES  ENTRIES whose EEG carries BOTH a non-empty
        %   .measurements and a non-empty .spectralMeasures -- the case
        %   generateQuartoReport resolves by preferring ERP and silently
        %   ignoring the spectral half. Same options as erpEntries, plus
        %   Measures (frequencySpec results) for the spectral half.
            p = inputParser();
            p.KeepUnmatched = true;
            p.addParameter('Windows', {ReportFixtures.windowSpec('N400', 'Mean Amplitude')});
            p.addParameter('Measures', {ReportFixtures.frequencySpec('10Hz')});
            p.parse(varargin{:});
            shared = unmatchedArgs(p);

            entries = ReportFixtures.erpEntries(shared{:}, 'Windows', p.Results.Windows);
            spectral = ReportFixtures.spectralEntries(shared{:}, 'Measures', p.Results.Measures);
            for i = 1:numel(entries)
                entries(i).EEG.spectralMeasures = spectral(i).EEG.spectralMeasures;
            end
        end

        function entries = emptyEntries()
        %EMPTYENTRIES  A 0x0 ENTRIES struct array -- generateQuartoReport's
        %   first guard ("needs at least one Measure result"), which
        %   shares its MException identifier with the second guard, so a
        %   test must discriminate the two on their MESSAGE.
            entries = struct('subject', {});
        end

        function entries = entriesMissingMeasureField()
        %ENTRIESMISSINGMEASUREFIELD  ENTRIES whose EEG has neither a
        %   .measurements nor a .spectralMeasures field at all -- the
        %   isfield half of generateQuartoReport's second guard.
            entries = ReportFixtures.erpEntries();
            for i = 1:numel(entries)
                entries(i).EEG = rmfield(entries(i).EEG, 'measurements');
            end
        end

        function entries = entriesWithEmptyMeasureField()
        %ENTRIESWITHEMPTYMEASUREFIELD  ENTRIES whose EEG.measurements is
        %   present but {} -- the ~isempty half of the same guard, and the
        %   leg that a dropped "&& ~isempty(...)" turns into a silently
        %   zero-section report rather than an error.
            entries = ReportFixtures.erpEntries();
            for i = 1:numel(entries)
                entries(i).EEG.measurements = {};
            end
        end

        function [entries, truth] = pairedGroundTruthEntries()
        %PAIREDGROUNDTRUTHENTRIES  A two-bin, one-channel, 25-subject ERP
        %   fixture whose paired t-test is ANALYTICALLY EXACT, so a render
        %   test can assert a number instead of "something was printed".
        %
        %   Construction: v = (1:25)', z = (v - mean(v)) / std(v). Because
        %   MATLAB's std and R's sd share the N-1 denominator, z has mean
        %   exactly 0 and sd exactly 1, so bin A = v and bin B = v + 2 + z
        %   give paired differences with mean 2.000000 and sd 1.000000 --
        %   hence t = 2 / (1 / sqrt(25)) = 10.000000 on 24 df, and
        %   |Cohen's dz| = 2.000000. No random seed to drift, and no
        %   tolerance-fudging beyond the CSV's own %.6g rounding (which
        %   perturbs t by < 1e-3).
        %
        %   TRUTH returns those expected values (.n, .df, .t, .dz,
        %   .meanDiff, .sdDiff) so a test states them once, here, rather
        %   than re-deriving the arithmetic in its own assertions.
        %
        %   Bin labels are 'A' and 'B', i.e. bindesc order IS alphabetical
        %   order -- the overwhelmingly common case, and the one in which
        %   pairedSection's t.test (bindesc order) and its rstatix
        %   cohens_d (alphabetical factor-level order) disagree in sign.
            n = 25;
            v = (1:n)';
            z = (v - mean(v)) / std(v);
            binA = v;
            binB = v + 2 + z;

            values = cell(n, 1);
            for i = 1:n
                values{i, 1} = [binA(i), binB(i)];
            end

            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B'}), ...
                'Windows', {ReportFixtures.windowSpec('N400', 'Mean Amplitude', ...
                    'Channels', {'Cz'})}, ...
                'Groups', repmat({''}, 1, n), ...
                'Values', values);

            truth = struct('n', n, 'df', n - 1, 't', 10, 'dz', 2, ...
                'meanDiff', 2, 'sdDiff', 1);
        end

        % ================================================================ %
        %  The named dispatch-census fixtures
        % ================================================================ %

        function ids = censusIds()
        %CENSUSIDS  The ten fixture identifiers censusEntries accepts, one
        %   per cell of generateQuartoReport's dispatch matrix that a
        %   chunk-label census can distinguish.
        %
        %   The two session cells were added when the design layer made
        %   session a real factor: without them the census could not reach
        %   the lmm_session design at all, so neither the design-vocabulary
        %   check nor the generated-R parse check covered it.
            ids = {'F-ERP1', 'F-ERP1G', 'F-ERP2', 'F-ERP2G', ...
                'F-ERP3C', 'F-ERP3CG', 'F-ERP3S', 'F-ERP3SG', ...
                'F-SPEC3C', 'F-SPEC3CR'};
        end

        function entries = censusEntries(id)
        %CENSUSENTRIES  ENTRIES for one censusIds identifier:
        %     F-ERP1     1 ordinary bin,  ungrouped, ERP  -> descriptive
        %     F-ERP1G    1 ordinary bin,  grouped,   ERP  -> between
        %     F-ERP2     2 ordinary bins, ungrouped, ERP  -> paired
        %     F-ERP2G    2 ordinary bins, grouped,   ERP  -> mixed
        %     F-ERP3C    3 + combo,       ungrouped, ERP  -> anova + combo
        %     F-ERP3CG   3 + combo,       grouped,   ERP  -> mixed + combo-grouped
        %     F-ERP3S    3 + combo,       2 sessions, ERP -> session + combo
        %     F-ERP3SG   3 + combo,       2 sessions x 2 groups -> session x group
        %     F-SPEC3C   3 + combo,       ungrouped, Spectral, no refChannel
        %     F-SPEC3CR  as F-SPEC3C but with refChannel 'Cz', which adds
        %                the coherence/phaselag measure types
        %   Every one carries two subjects, so the same fixture is usable
        %   for a CSV/render test (the generated R stops outright below
        %   two subjects) and not only for a text assertion.
            ungrouped = {'', ''};
            grouped   = {'ctrl', 'patient'};
            meanAmp   = {ReportFixtures.windowSpec('N400', 'Mean Amplitude')};
            peak      = {ReportFixtures.windowSpec('N400', 'Peak')};

            switch upper(char(id))
                case 'F-ERP1'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A'}), ...
                        'Windows', meanAmp, 'Groups', ungrouped);
                case 'F-ERP1G'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A'}), ...
                        'Windows', meanAmp, 'Groups', grouped);
                case 'F-ERP2'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A', 'B'}), ...
                        'Windows', meanAmp, 'Groups', ungrouped);
                case 'F-ERP2G'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A', 'B'}), ...
                        'Windows', meanAmp, 'Groups', grouped);
                case 'F-ERP3C'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Windows', peak, 'Groups', ungrouped);
                case 'F-ERP3CG'
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Windows', peak, 'Groups', grouped);
                case 'F-ERP3S'
                    % Two people, each measured twice. Four recordings, so
                    % this fixture still clears the two-subject floor the
                    % generated R enforces, and the crossing has no empty
                    % cell for reportDesignPlan to fall back over.
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Windows', peak, 'Groups', {'', '', '', ''}, ...
                        'Subjects', {'a_pre', 'a_post', 'b_pre', 'b_post'}, ...
                        'Persons', {'a', 'a', 'b', 'b'}, ...
                        'Sessions', {'pre', 'post', 'pre', 'post'});
                case 'F-ERP3SG'
                    % Two groups of two people, each measured twice: every
                    % cell of group x session occupied, which is what lets
                    % the (bin + session + group)^2 model be fitted.
                    entries = ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Windows', peak, ...
                        'Groups', {'ctrl', 'ctrl', 'ctrl', 'ctrl', 'patient', 'patient', 'patient', 'patient'}, ...
                        'Subjects', {'a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'd1', 'd2'}, ...
                        'Persons', {'a', 'a', 'b', 'b', 'c', 'c', 'd', 'd'}, ...
                        'Sessions', {'pre', 'post', 'pre', 'post', 'pre', 'post', 'pre', 'post'});
                case 'F-SPEC3C'
                    entries = ReportFixtures.spectralEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Measures', {ReportFixtures.frequencySpec('10Hz')}, 'Groups', ungrouped);
                case 'F-SPEC3CR'
                    entries = ReportFixtures.spectralEntries('Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                        'Measures', {ReportFixtures.frequencySpec('10Hz', 'RefChannel', 'Cz')}, ...
                        'Groups', ungrouped);
                otherwise
                    throw(MException('Alakazam:ReportFixtures:unknownFixture', ...
                        'I am afraid "%s" is not one of ReportFixtures.censusIds().', char(id)));
            end
        end

        function labels = hostileLabels()
        %HOSTILELABELS  A FIXED corpus of window/bin labels an analyst
        %   could plausibly type, each of which stresses a different
        %   escaping or sanitisation boundary: markdown specials, an R
        %   string-literal terminator, a sprintf format directive, an
        %   empty and a whitespace-only label, a non-ASCII label, and one
        %   that is already perfectly well behaved.
        %
        %   Fixed, never randomised: a reproducible failure that names the
        %   exact offending label is worth far more here than broader
        %   coverage that cannot be reproduced.
            labels = {'targ_left', 'targ*right', 'say "hi"', '50% load', ...
                'A\B', '<tag>', '#hash', '[br]', 'back`tick', '', ' ', ...
                '20 Hz', char([99 97 102 233]), 'a-b'};
        end

        % ================================================================ %
        %  Generated-document parsers
        % ================================================================ %

        function labels = chunkLabels(qmdText)
        %CHUNKLABELS  Every "#| label: X" in QMDTEXT, in DOCUMENT ORDER,
        %   as a cellstr -- the census a dispatch test keys on, because a
        %   chunk label names the section builder that ran
        %   (desc-/between-/paired-/mixed-/anova-/combo-/combo-desc-/
        %   combo-grouped-) whereas a section heading does not and is in
        %   several cases a strict prefix of another design's heading.
            [~, ~, labels] = splitChunks(qmdText);
            labels = labels(~cellfun(@isempty, labels));
        end

        function found = headings(qmdText)
        %HEADINGS  Every level-2 markdown heading ("## ...") in QMDTEXT,
        %   in document order, as a cellstr of whole heading lines.
        %
        %   Counted OUTSIDE ```{r} chunks only, so a "###" that a section
        %   builder's own R cat(sprintf(...)) emits per channel can never
        %   be miscounted as a section of the report. One section builder
        %   emits exactly one such heading, so numel(headings) is the
        %   section count plus one for the closing summary.
            [~, outside] = splitChunks(qmdText);
            found = outside(~cellfun(@isempty, regexp(outside, '^##[^#]', 'once')));
            found = found(:)';
        end

        function chunks = rChunks(qmdText)
        %RCHUNKS  The BODY of every ```{r} chunk in QMDTEXT, in document
        %   order, as a cellstr -- fences stripped, "#|" option lines
        %   kept (they are ordinary R comments, so they parse, and
        %   chunkFor needs them to find a chunk by its label).
            chunks = splitChunks(qmdText);
        end

        function code = rCode(qmdText)
        %RCODE  Every ```{r} chunk body of QMDTEXT concatenated into one
        %   runnable R source string, separated by a BLANK line.
        %
        %   The blank line is not cosmetic: concatenating two chunks with
        %   a single newline splices the first chunk's closing "}" onto
        %   the next chunk's first token, and R's own parser then reports
        %   an unexpected symbol in "}cat" -- a syntax error entirely
        %   manufactured by the concatenation, in code that is perfectly
        %   valid as written.
            code = strjoin(ReportFixtures.rChunks(qmdText), [newline newline]);
        end

        function body = chunkFor(qmdText, label)
        %CHUNKFOR  The body of the one ```{r} chunk in QMDTEXT whose
        %   "#| label:" is LABEL, or '' when no such chunk exists.
        %
        %   Slicing by label, rather than searching the whole document, is
        %   what lets a test say "this particular section must not contain
        %   lmerTest::lmer" in a report where another section legitimately
        %   does. '' (rather than an error) on a missing label is
        %   deliberate: verifyEmpty then states "the chunk must not exist"
        %   and contains('', ...) is false, so both forms of assertion
        %   read correctly against the same return value.
            [chunks, ~, labels] = splitChunks(qmdText);
            body = '';
            hit = find(strcmp(labels, char(label)), 1, 'first');
            if ~isempty(hit)
                body = chunks{hit};
            end
        end

        % ================================================================ %
        %  Writing a real report (real exporter + real generator)
        % ================================================================ %

        function [qmdFile, csvFile] = writeReport(entries, folder, stem)
        %WRITEREPORT  Write ENTRIES' real CSV and real .qmd into FOLDER as
        %   STEM.csv / STEM.qmd, and return both paths.
        %
        %   The CSV goes through the REAL exportMeasurementsCSV or
        %   exportSpectralCSV (chosen by the same isfield/~isempty rule
        %   generateQuartoReport itself uses to decide which report kind
        %   to build), and the .qmd through the real generateQuartoReport,
        %   referencing the CSV by its BARE name -- exactly the relative
        %   arrangement a render depends on. Nothing is written anywhere
        %   but FOLDER, which every caller supplies from a
        %   TemporaryFolderFixture, never the repository.
            EEG = entries(1).EEG;
            isErp = isfield(EEG, 'measurements') && ~isempty(EEG.measurements);

            csvName = [stem '.csv'];
            csvFile = fullfile(folder, csvName);
            if isErp
                exportMeasurementsCSV(entries, csvFile);
            else
                exportSpectralCSV(entries, csvFile);
            end

            qmdFile = fullfile(folder, [stem '.qmd']);
            writeTextFile(qmdFile, generateQuartoReport(entries, csvName));
        end

        function columns = csvHeader(csvFile)
        %CSVHEADER  CSVFILE's header line as a cellstr of column names,
        %   read off disk rather than restated -- so a test can census
        %   what the exporter ACTUALLY wrote without naming the columns a
        %   third time (the exporter's own fprintf format string and the
        %   generated R being the first two).
            lines = textLines(fileText(csvFile));
            if isempty(lines)
                columns = {};
                return;
            end
            columns = splitCsvLine(lines{1});
        end

        function values = csvColumn(csvFile, columnName)
        %CSVCOLUMN  Every data row's value in CSVFILE's COLUMNNAME column,
        %   as a cellstr (quoting honoured, so a bin label containing a
        %   comma does not shift the columns).
            lines = textLines(fileText(csvFile));
            lines = lines(~cellfun(@isempty, lines));
            values = {};
            if isempty(lines)
                return;
            end
            header = splitCsvLine(lines{1});
            col = find(strcmp(header, char(columnName)), 1, 'first');
            if isempty(col)
                throw(MException('Alakazam:ReportFixtures:noSuchColumn', ...
                    'I am afraid "%s" is not a column of "%s".', char(columnName), csvFile));
            end
            values = cell(1, numel(lines) - 1);
            for i = 2:numel(lines)
                fields = splitCsvLine(lines{i});
                values{i - 1} = fields{col};
            end
        end

        % ================================================================ %
        %  External tool discovery (returns '' rather than erroring)
        % ================================================================ %

        function exe = rscriptExe()
        %RSCRIPTEXE  A usable Rscript executable, or '' when none is
        %   found, so a caller can assumeTrue(~isempty(...)) into a clean
        %   skip rather than a spurious failure.
        %
        %   Order: the ALAKAZAM_RSCRIPT override (an existing file), then
        %   PATH, then R's own default Windows install folders globbed for
        %   the highest version present. The glob is NOT optional: R's
        %   Windows installer does not put Rscript on PATH unless the user
        %   explicitly asks it to, so a machine with a perfectly working R
        %   very commonly fails the PATH check. Cached for the session.
            persistent cached
            if isempty(cached)
                cached = struct('exe', discoverRscript());
            end
            exe = cached.exe;
        end

        function exe = quartoExe()
        %QUARTOEXE  A usable quarto executable, or '' when none is found.
        %   Order: the ALAKAZAM_QUARTO override (an existing file), then
        %   PATH, then Quarto's own default per-user install folder --
        %   which the Quarto installer populates without adding it to
        %   PATH. Cached for the session.
        %
        %   Only ever a GUARD: an actual render goes through the real
        %   renderQuartoReport, whose own locateQuartoTools is a private
        %   local function a test cannot call, so routing the render
        %   through it exercises that discovery path for free.
            persistent cached
            if isempty(cached)
                cached = struct('exe', discoverQuarto());
            end
            exe = cached.exe;
        end

        function [status, output] = runRscript(rCode)
        %RUNRSCRIPT  Run RCODE under Rscript --vanilla, returning the
        %   process STATUS and its combined OUTPUT.
        %
        %   The code goes into a temporary FILE (under the system temp
        %   folder, never the repository) rather than an -e argument, so
        %   no quoting of the R source survives contact with the Windows
        %   shell. --vanilla still resolves the user library, so packages
        %   installed for the user are found. STATUS is -1 with an
        %   explanatory OUTPUT when no Rscript was found at all.
            exe = ReportFixtures.rscriptExe();
            if isempty(exe)
                status = -1;
                output = 'No Rscript executable was found.';
                return;
            end
            scriptFile = [tempname() '.R'];
            writeTextFile(scriptFile, rCode);
            removeScript = onCleanup(@() deleteIfPresent(scriptFile));
            [status, output] = system(sprintf('"%s" --vanilla "%s"', exe, scriptFile));
        end

        function tf = rPackagesPresent(packages)
        %RPACKAGESPRESENT  True when every package in PACKAGES (a cellstr)
        %   is already installed for the R that rscriptExe found.
        %
        %   Asked before executing any generated setup chunk, because that
        %   chunk's own "install.packages(missing)" branch would otherwise
        %   fire and reach the network from inside a unit test. False (not
        %   an error) when R itself is missing. Cached per package list.
            persistent cache
            if isempty(cache)
                cache = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            end
            key = strjoin(sort(reshape(packages, 1, [])), ',');
            if isKey(cache, key)
                tf = cache(key);
                return;
            end
            code = sprintf(['pkgs <- c(%s)\n' ...
                'ok <- all(vapply(pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1)))\n' ...
                'cat(if (ok) "ALLPRESENT" else "SOMEMISSING")\n'], rVectorLiteral(packages));
            [status, output] = ReportFixtures.runRscript(code);
            tf = status == 0 && contains(output, 'ALLPRESENT');
            cache(key) = tf;
        end

    end
end

% =========================================================================== %
%  Local helpers (callable only from the methods above)
% =========================================================================== %

function o = parseEntryOptions(args, defaultBins, defaultBlocks, preferredField)
%PARSEENTRYOPTIONS  The name-value options erpEntries and spectralEntries
%   share, resolved into one options struct with every per-entry cellstr
%   already expanded to the same length. 'Windows' and 'Measures' are both
%   accepted so each builder reads naturally in its own domain;
%   PREFERREDFIELD names the one THIS builder means, so forwarding a
%   shared argument list to both builders cannot cross the wires.
    p = inputParser();
    p.addParameter('Bindesc', defaultBins);
    p.addParameter('Windows', {});
    p.addParameter('Measures', {});
    p.addParameter('Groups', {'', ''});
    p.addParameter('DatasetTypes', {});
    p.addParameter('Subjects', {});
    p.addParameter('Persons', {});
    p.addParameter('Sessions', {});
    p.addParameter('Values', {});
    p.parse(args{:});
    r = p.Results;

    if strcmp(preferredField, 'Measures')
        blocks = firstNonEmpty(r.Measures, r.Windows);
    else
        blocks = firstNonEmpty(r.Windows, r.Measures);
    end
    if isempty(blocks)
        blocks = defaultBlocks;
    end

    groups = r.Groups;
    n = numel(groups);
    if n == 0
        throw(MException('Alakazam:ReportFixtures:noSubjects', ...
            'I am afraid a fixture needs at least one entry: Groups was empty.'));
    end

    subjects = r.Subjects;
    if isempty(subjects)
        subjects = arrayfun(@(i) sprintf('s%d', i), 1:n, 'UniformOutput', false);
    end
    datasetTypes = r.DatasetTypes;
    if isempty(datasetTypes)
        datasetTypes = repmat({'subject'}, 1, n);
    end
    persons = r.Persons;
    if isempty(persons)
        persons = subjects;
    end
    sessions = r.Sessions;
    if isempty(sessions)
        sessions = repmat({''}, 1, n);
    end

    o = struct('bins', r.Bindesc, 'blocks', {blocks}, 'groups', {groups(:)'}, ...
        'datasetTypes', {datasetTypes(:)'}, 'subjects', {subjects(:)'}, ...
        'persons', {persons(:)'}, 'sessions', {sessions(:)'}, ...
        'values', {r.Values}, 'n', n);
end

function value = firstNonEmpty(preferred, fallback)
%FIRSTNONEMPTY  PREFERRED when it is non-empty, FALLBACK otherwise.
    if ~isempty(preferred)
        value = preferred;
    else
        value = fallback;
    end
end

function entries = buildEntries(o, kind)
%BUILDENTRIES  One ENTRIES struct array from parseEntryOptions' own
%   options struct: KIND ('erp'/'spectral') picks which EEG field the
%   blocks are materialised into.
    nBins = max(numel(o.bins), 1);
    entries = struct('subject', o.subjects, 'datasetType', o.datasetTypes, ...
        'group', o.groups, 'person', o.persons, 'session', o.sessions, ...
        'EEG', repmat({[]}, 1, o.n));
    for i = 1:o.n
        blocks = cell(1, numel(o.blocks));
        for b = 1:numel(o.blocks)
            amplitude = valueOverride(o.values, i, b);
            if strcmp(kind, 'erp')
                blocks{b} = erpWindow(o.blocks{b}, nBins, i, amplitude);
            else
                blocks{b} = spectralMeasure(o.blocks{b}, nBins, i, amplitude);
            end
        end
        EEG = struct();
        EEG.bindesc = o.bins;
        if strcmp(kind, 'erp')
            EEG.measurements = blocks;
        else
            EEG.spectralMeasures = blocks;
        end
        entries(i).EEG = EEG;
    end
end

function amplitude = valueOverride(values, entryIndex, blockIndex)
%VALUEOVERRIDE  The caller-supplied amplitude matrix for one (entry,
%   block) pair, or [] when the fixture is using deterministic values.
    amplitude = [];
    if isempty(values)
        return;
    end
    if size(values, 2) >= blockIndex
        amplitude = values{entryIndex, blockIndex};
    else
        amplitude = values{entryIndex};
    end
end

function win = erpWindow(spec, nBins, entryIndex, amplitude)
%ERPWINDOW  One WINDOWSPEC materialised into the full Measure window
%   struct exportMeasurementsCSV and measureRowTypes both read: the spec's
%   own definition fields plus nChannels x nBins amplitude/latency/area
%   matrices.
    nCh = numel(spec.channels);
    if isempty(amplitude)
        amplitude = deterministicValues(1, nCh, nBins, entryIndex);
    end
    win = struct('label', spec.label, 'start', spec.start, 'stop', spec.stop, ...
        'measure', spec.measure, 'polarity', 'positive', 'width', spec.width, ...
        'localPoints', 3, 'fraction', 0.5, 'areaMode', spec.areaMode, ...
        'scope', spec.scope, 'refChannel', spec.refChannel, ...
        'channels', {spec.channels}, 'amplitude', amplitude, ...
        'latency', 300 + 10 * deterministicValues(1, nCh, nBins, entryIndex), ...
        'area', 2 * deterministicValues(1, nCh, nBins, entryIndex));
end

function m = spectralMeasure(spec, nBins, entryIndex, amplitude)
%SPECTRALMEASURE  One FREQUENCYSPEC materialised into the full
%   SpectralMeasure result struct exportSpectralCSV reads. Every one of
%   the seven matrices is always present (coherence/phaselag included),
%   exactly as SpectralMeasure.m leaves them; whether the CSV actually
%   carries the last two is decided by .refChannel, not by their absence.
    nCh = numel(spec.channels);
    base = deterministicValues(1, nCh, nBins, entryIndex);
    if isempty(amplitude)
        amplitude = base;
    end
    m = struct('label', spec.label, 'freq', spec.freq, ...
        'channels', {spec.channels}, 'refChannel', spec.refChannel, ...
        'power', amplitude .^ 2, 'amplitude', amplitude, 'snr', 1 + base, ...
        'itc', bounded01(base), 'phase', wrapToPiLocal(base), ...
        'coherence', bounded01(base + 0.17), 'phaselag', wrapToPiLocal(base + 0.41));
end

function M = deterministicValues(base, nCh, nBins, entryIndex)
%DETERMINISTICVALUES  A nCh x nBins matrix of reproducible, non-constant
%   values. No rand and no seed anywhere: the per-entry term varies BY BIN
%   as well (the mod(...) term), so differences between bins genuinely
%   vary across subjects -- a fixture whose between-bin difference were
%   constant would give a zero-variance paired difference, which the
%   generated R's own t-test rejects outright as "data are essentially
%   constant".
    M = zeros(nCh, nBins);
    for c = 1:nCh
        for b = 1:nBins
            M(c, b) = base + 0.5 * b + 0.25 * c + 0.1 * entryIndex ...
                + 0.05 * mod(entryIndex * b + c, 7);
        end
    end
end

function M = bounded01(M)
%BOUNDED01  Values squashed into the open (0, 1) interval, the range ITC
%   and coherence actually live in.
    M = 0.5 + 0.4 * sin(M);
end

function M = wrapToPiLocal(M)
%WRAPTOPILOCAL  Values wrapped into (-pi, pi], the range phase and
%   phaselag actually live in -- the very wrap-around that makes linear
%   statistics on them invalid. Spelled out here rather than via
%   wrapToPi, which lives in the Mapping Toolbox.
    M = mod(M + pi, 2 * pi) - pi;
end

function args = unmatchedArgs(p)
%UNMATCHEDARGS  An inputParser's KeepUnmatched leftovers back as a
%   name-value argument list, for forwarding to another builder.
    names = fieldnames(p.Unmatched);
    args = cell(1, 2 * numel(names));
    for i = 1:numel(names)
        args{2 * i - 1} = names{i};
        args{2 * i} = p.Unmatched.(names{i});
    end
end

function [chunks, outside, labels] = splitChunks(qmdText)
%SPLITCHUNKS  QMDTEXT partitioned into CHUNKS (each ```{r} chunk's body,
%   fences stripped), OUTSIDE (every line that is not inside a chunk) and
%   LABELS (each chunk's own "#| label:" value, '' when it has none).
%   One pass, so the three always agree on where the chunk boundaries are.
    lines = textLines(qmdText);
    chunks = {};
    outside = {};
    labels = {};
    body = {};
    inChunk = false;
    for i = 1:numel(lines)
        line = lines{i};
        if ~inChunk
            if startsWith(line, '```{r')
                inChunk = true;
                body = {};
            else
                outside{end + 1} = line; %#ok<AGROW>
            end
        elseif strcmp(strtrim(line), '```')
            inChunk = false;
            chunks{end + 1} = strjoin(body, newline); %#ok<AGROW>
            labels{end + 1} = labelOf(body); %#ok<AGROW>
        else
            body{end + 1} = line; %#ok<AGROW>
        end
    end
    if inChunk
        chunks{end + 1} = strjoin(body, newline);
        labels{end + 1} = labelOf(body);
    end
end

function label = labelOf(body)
%LABELOF  One chunk body's "#| label:" value, or '' when it carries none.
    label = '';
    for i = 1:numel(body)
        token = regexp(body{i}, '^#\|\s*label:\s*(\S+)\s*$', 'tokens', 'once');
        if ~isempty(token)
            label = token{1};
            return;
        end
    end
end

function lines = textLines(txt)
%TEXTLINES  TXT split into lines on any line ending, empty lines kept.
    if isempty(txt)
        lines = {};
        return;
    end
    lines = regexp(char(txt), '\r\n|\n|\r', 'split');
end

function fields = splitCsvLine(line)
%SPLITCSVLINE  One CSV line split into fields, honouring double-quoted
%   fields and their doubled-quote escapes -- csvField quotes any value
%   containing a comma, quote or newline, so a naive strsplit on ',' would
%   silently shift every column after a hostile bin label.
    fields = {};
    current = '';
    inQuotes = false;
    i = 1;
    while i <= numel(line)
        ch = line(i);
        if inQuotes
            if ch == '"'
                if i < numel(line) && line(i + 1) == '"'
                    current(end + 1) = '"'; %#ok<AGROW>
                    i = i + 1;
                else
                    inQuotes = false;
                end
            else
                current(end + 1) = ch; %#ok<AGROW>
            end
        elseif ch == '"'
            inQuotes = true;
        elseif ch == ','
            fields{end + 1} = current; %#ok<AGROW>
            current = '';
        else
            current(end + 1) = ch; %#ok<AGROW>
        end
        i = i + 1;
    end
    fields{end + 1} = current;
end

function txt = fileText(path)
%FILETEXT  A whole text file as one char row vector.
    fid = fopen(path, 'r');
    if fid < 0
        throw(MException('Alakazam:ReportFixtures:cannotRead', ...
            'I am afraid I could not open "%s" for reading.', path));
    end
    closeFile = onCleanup(@() fclose(fid));
    txt = fread(fid, '*char')';
end

function writeTextFile(path, text)
%WRITETEXTFILE  Write TEXT to PATH verbatim (no format interpretation, so
%   a stray '%' or '\' in generated R survives intact).
    fid = fopen(path, 'w');
    if fid < 0
        throw(MException('Alakazam:ReportFixtures:cannotWrite', ...
            'I am afraid I could not open "%s" for writing.', path));
    end
    closeFile = onCleanup(@() fclose(fid));
    fwrite(fid, char(text), 'char');
end

function deleteIfPresent(path)
%DELETEIFPRESENT  Delete PATH when it exists, silently otherwise.
    if exist(path, 'file') == 2
        delete(path);
    end
end

function literal = rVectorLiteral(items)
%RVECTORLITERAL  A cellstr as the inner text of an R c("a", "b") vector.
    quoted = cellfun(@(s) ['"' char(s) '"'], items(:)', 'UniformOutput', false);
    literal = strjoin(quoted, ', ');
end

function exe = discoverRscript()
%DISCOVERRSCRIPT  See ReportFixtures.rscriptExe -- the ALAKAZAM_RSCRIPT
%   override, then the application's own discovery, which also reads R's
%   InstallPath out of the Windows registry (where its installer always
%   writes it, whether or not PATH was updated).
    exe = getenv('ALAKAZAM_RSCRIPT');
    if ~isempty(exe) && isfile(exe)
        return;
    end
    exe = quartoTools();
end

function [rscriptExe, quartoExe] = quartoTools()
%QUARTOTOOLS  locateQuartoTools, once per session.
%   Both discoveries shell out several times on a miss, and neither answer
%   changes while the tests run.
    persistent cached
    if isempty(cached)
        [rs, q] = locateQuartoTools();
        cached = struct('rs', rs, 'q', q);
    end
    rscriptExe = cached.rs;
    quartoExe = cached.q;
end

function exe = discoverQuarto()
%DISCOVERQUARTO  See ReportFixtures.quartoExe -- the ALAKAZAM_QUARTO
%   override, then the application's own discovery.
%
%   This used to do its own lookup: PATH, then Quarto's per-user install
%   folder. It missed the copy RStudio bundles under its own resources
%   folder, which is never on PATH --
%   so on a machine with R and RStudio installed, the render tests skipped
%   with "Quarto not found" while renderQuartoReport itself found it
%   perfectly well and rendered reports all day. The guard was stricter than
%   the thing it guarded, which is the worst way for a skip to be wrong: it
%   is silent, and it hides exactly the end-to-end checks that catch what
%   unit tests cannot.
    exe = getenv('ALAKAZAM_QUARTO');
    if ~isempty(exe) && isfile(exe)
        return;
    end
    [~, exe] = quartoTools();
end
