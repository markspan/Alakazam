classdef SourceCacheTest < matlab.unittest.TestCase
%SOURCECACHETEST  The stored source estimate, and the two checks that
%   decide whether it may be reused.
%
%   Reuse is the dangerous kind of optimisation: getting it wrong does not
%   make an analysis slower, it makes it answer a different question, with
%   plausible numbers and no symptom. So most of this file is about the
%   circumstances in which reuse must be REFUSED, and the two gates are
%   tested separately because they catch different mistakes:
%
%     SourceCache.Key          the settings differ (channels, mesh, method,
%                              orientation, regularisation)
%     SourceCache.Fingerprint  the settings match but the DATA is not the
%                              data the estimate was computed from -- which
%                              happens whenever a later transformation
%                              inherits the field while changing EEG.data
%
%   The estimates themselves are made by Source Estimate, a plugin
%   (AlakazamSourceEstimate), whose own tests check them against an
%   independent inverse and their reuse by the source cluster test. These
%   run on estimates built by hand, without FieldTrip.
%
%   Run with: runtests('tests/SourceCacheTest.m').
%
%   See also SOURCECACHE.KEY, SOURCECACHE.LOOKUP, SOURCECACHE.FINGERPRINT,
%   SOURCECACHE.SPACE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- the settings key -------------------------------------------
        function identicalSettingsGiveEqualKeys(testCase)
            labels = {'Fz', 'Cz', 'Pz'};
            opts = testCase.settings();
            testCase.verifyTrue(isequaln( ...
                SourceCache.Key(labels, opts), ...
                SourceCache.Key(labels, opts)));
        end

        function everySettingThatChangesTheAnswerChangesTheKey(testCase)
        %EVERYSETTINGTHATCHANGESTHEANSWERCHANGESTHEKEY  One case per field,
        %   because a key that ignores a field is worse than no key at all:
        %   it asserts equivalence that does not hold.
            labels = {'Fz', 'Cz', 'Pz'};
            base = testCase.settings();
            baseKey = SourceCache.Key(labels, base);

            % TIMEWINDOW AND RESAMPLEHZ ARE ABSENT ON PURPOSE. They were
            % here, and they were wrong to be: the spatial filter is
            % data-independent, so cropping commutes with inverting (a
            % relative 1.5e-16, measured for mne, sloreta and eloreta) and
            % a wider estimate genuinely is a superset of a narrower one.
            % Keyed on them, a whole-epoch estimate could not answer for
            % 200-400 ms and every subject re-inverted per window tried.
            % SourceCache.Lookup checks coverage at the point of use
            % instead, which the cropping tests below cover.
            changes = { ...
                'SourceSpace', 8196; ...
                'Method',      'sloreta'; ...
                'Orientation', 'magnitude'; ...
                'RegParam',    0.10};
            for k = 1:size(changes, 1)
                changed = base;
                changed.(changes{k, 1}) = changes{k, 2};
                testCase.verifyFalse(isequaln(baseKey, ...
                    SourceCache.Key(labels, changed)), ...
                    sprintf('Changing %s left the key unchanged.', changes{k, 1}));
            end
        end

        function theChannelSetAndItsOrderBothMatter(testCase)
        %THECHANNELSETANDITSORDERBOTHMATTER  The leadfield's rows ARE the
        %   channels in that order, so a permutation is not a relabelling,
        %   it silently pairs each channel with another's forward field.
            opts = testCase.settings();
            keyA = SourceCache.Key({'Fz', 'Cz', 'Pz'}, opts);
            keyB = SourceCache.Key({'Fz', 'Pz', 'Cz'}, opts);
            keyC = SourceCache.Key({'Fz', 'Cz'}, opts);

            testCase.verifyFalse(isequaln(keyA, keyB), 'Channel order is ignored.');
            testCase.verifyFalse(isequaln(keyA, keyC), 'Channel count is ignored.');
        end

        function caseDiffersButTheChannelsAreTheSame(testCase)
        %CASEDIFFERSBUTTHECHANNELSARETHESAME  Label case is not meaningful
        %   anywhere else in the pipeline, so it must not block reuse here.
            opts = testCase.settings();
            testCase.verifyTrue(isequaln( ...
                SourceCache.Key({'Fz', 'Cz'}, opts), ...
                SourceCache.Key({'FZ', 'cz'}, opts)));
        end

        % ---- cropping a stored estimate to what was asked for -----------
        function aStoredEstimateIsCroppedToTheRequestedWindow(testCase)
        %ASTOREDESTIMATEISCROPPEDTOTHEREQUESTEDWINDOW  The reuse that the
        %   window-in-the-key design made impossible.
            EEG = testCase.datasetWithEstimate(0:10:190);   % 0..190 ms, 100 Hz
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());

            [values, info] = SourceCache.Lookup(EEG, 'A', key, ...
                struct('TimeWindow', [50 150], 'ResampleHz', []));

            testCase.verifyNotEmpty(values);
            testCase.verifyEqual(info.times, 50:10:150);
            testCase.verifyEqual(size(values, 2), 11);
            % and it is the stored data, not a recomputation of it
            testCase.verifyEqual(values, EEG.sourceEstimate.values(:, 6:16, 1));
        end

        function aStoredEstimateIsThinnedToTheRequestedRate(testCase)
            EEG = testCase.datasetWithEstimate(0:10:190);
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());

            [values, info] = SourceCache.Lookup(EEG, 'A', key, ...
                struct('TimeWindow', [], 'ResampleHz', 50));

            testCase.verifyEqual(info.times, 0:20:180);
            testCase.verifyEqual(values, EEG.sourceEstimate.values(:, 1:2:19, 1));
        end

        function aWindowWiderThanTheEstimateIsRefused(testCase)
        %AWINDOWWIDERTHANTHEESTIMATEISREFUSED  Cropping is free, inventing
        %   latencies the estimate never had is not.
        %
        %   The estimate has to be narrower than its EPOCH for this to mean
        %   anything. Asking for a window wider than the epoch itself is not
        %   refused and should not be: the restriction clamps to the times
        %   the dataset actually has, so both paths agree and the request is
        %   answerable. An earlier version of this test asked for exactly
        %   that and passed only while the coverage rule was too strict.
            EEG = testCase.datasetWithEstimate(100:10:200, [], 0:10:300);
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());
            testCase.verifyEmpty(SourceCache.Lookup(EEG, 'A', key, ...
                struct('TimeWindow', [0 300], 'ResampleHz', [])), ...
                'An estimate over 100-200 ms cannot answer for 0-300 ms.');
        end

        function aRateFinerThanTheEstimateIsRefused(testCase)
        %ARATEFINERTHANTHEESTIMATEISREFUSED  Likewise: the epoch must be
        %   finer than the estimate, or the compute path could not have
        %   produced the finer sampling either and there is nothing to
        %   refuse.
            EEG = testCase.datasetWithEstimate(0:20:200, [], 0:5:200);  % 50 Hz stored, 200 Hz epoch
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());
            testCase.verifyEmpty(SourceCache.Lookup(EEG, 'A', key, ...
                struct('TimeWindow', [], 'ResampleHz', 200)), ...
                'A 50 Hz estimate cannot answer a 200 Hz request.');
        end

        function noRequestReturnsTheStoredEstimateWhateverItsExtent(testCase)
        %NOREQUESTRETURNSTHESTOREDESTIMATEWHATEVERITSEXTENT  Brain3DView and
        %   the report assets ask for what is stored and slice it
        %   themselves. Omitting the request must not be read as asking for
        %   the whole epoch: a deliberately narrow estimate is exactly what
        %   they hold, and demanding it cover the epoch refused every one of
        %   them.
            EEG = testCase.datasetWithEstimate(100:10:200, [], 0:10:300);
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());
            [values, info] = SourceCache.Lookup(EEG, 'A', key);
            testCase.verifyEqual(info.times, 100:10:200);
            testCase.verifyEqual(size(values, 2), 11);
        end

        function askingForNothingInParticularReturnsTheWholeEstimate(testCase)
            EEG = testCase.datasetWithEstimate(0:10:190);
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());
            [values, info] = SourceCache.Lookup(EEG, 'A', key);
            testCase.verifyEqual(info.times, 0:10:190);
            testCase.verifyEqual(size(values, 2), 20);
        end

        function aCroppedEstimateDropsItsResidualVariance(testCase)
        %ACROPPEDESTIMATEDROPSITSRESIDUALVARIANCE  RV is the share of the
        %   scalp data the estimate fails to explain over the samples it
        %   saw, so the stored figure describes the whole epoch. Carrying it
        %   onto a narrower window would look like a measurement of that
        %   window and would not be one.
            EEG = testCase.datasetWithEstimate(0:10:190, 0.25);
            key = SourceCache.Key({'fz', 'cz'}, testCase.settings());

            [~, whole] = SourceCache.Lookup(EEG, 'A', key);
            testCase.verifyEqual(whole.ResidualVariance, 0.25, ...
                'An uncropped reuse keeps the figure it was given.');

            [~, cropped] = SourceCache.Lookup(EEG, 'A', key, ...
                struct('TimeWindow', [50 150], 'ResampleHz', []));
            testCase.verifyTrue(isnan(cropped.ResidualVariance));
        end

        % ---- which sheet a consumer should work on ----------------------
        function aDatasetWithoutAnEstimateKeepsTheFallback(testCase)
            space = SourceCache.Space(struct('data', []), 20484);
            testCase.verifyEqual(space, 20484);
        end

        function theStoredSheetIsAdopted(testCase)
        %THESTOREDSHEETISADOPTED  A view that insisted on the full-resolution
        %   sheet would refuse every estimate stored at a coarser one, which
        %   is the size worth keeping: 128 MB against 499 MB for a fit that
        %   differs by a twentieth of a percent.
            EEG = struct('sourceEstimate', ...
                struct('key', struct('sourceSpace', 5124)));
            testCase.verifyEqual(SourceCache.Space(EEG, 20484), 5124);
        end

        function anUnrecognisedSheetIsIgnored(testCase)
        %ANUNRECOGNISEDSHEETISIGNORED  Only the sheets FieldTrip ships are
        %   accepted, so a malformed or hand-edited estimate cannot send a
        %   caller looking for a mesh file that does not exist.
            for bad = {7000, -1, 'twenty thousand', [5124 8196], []}
                EEG = struct('sourceEstimate', ...
                    struct('key', struct('sourceSpace', bad{1})));
                testCase.verifyEqual(SourceCache.Space(EEG, 20484), 20484, ...
                    'An unrecognised source space was adopted.');
            end
        end

        function anEstimateWithoutAKeyIsIgnored(testCase)
        %ANESTIMATEWITHOUTAKEYISIGNORED  Written by an older version: choose
        %   the default rather than guess from the size of the values.
            EEG = struct('sourceEstimate', struct('values', zeros(5124, 3)));
            testCase.verifyEqual(SourceCache.Space(EEG, 20484), 20484);
        end

        % ---- the data fingerprint ---------------------------------------
        function thesameDataFingerprintsTheSame(testCase)
            EEG = testCase.tinyDataset();
            testCase.verifyTrue(isequaln(SourceCache.Fingerprint(EEG), ...
                SourceCache.Fingerprint(EEG)));
        end

        function rescaledDataIsDetected(testCase)
        %RESCALEDDATAISDETECTED  The realistic case: a later transformation
        %   inherits the estimate and changes the data under it.
            EEG = testCase.tinyDataset();
            changed = EEG; changed.data = EEG.data * 1.05;
            testCase.verifyFalse(isequaln(SourceCache.Fingerprint(EEG), ...
                SourceCache.Fingerprint(changed)));
        end

        function aSignFlipIsDetected(testCase)
        %ASIGNFLIPISDETECTED  Caught by the signed total and the corners,
        %   though not by the absolute total on its own, which is why there
        %   is more than one summary.
            EEG = testCase.tinyDataset();
            flipped = EEG; flipped.data = -EEG.data;
            testCase.verifyFalse(isequaln(SourceCache.Fingerprint(EEG), ...
                SourceCache.Fingerprint(flipped)));
        end

        function aDifferentShapeIsDetected(testCase)
            EEG = testCase.tinyDataset();
            trimmed = EEG; trimmed.data = EEG.data(:, 1:end-1, :);
            testCase.verifyFalse(isequaln(SourceCache.Fingerprint(EEG), ...
                SourceCache.Fingerprint(trimmed)));
        end

        function changedLatenciesAreDetected(testCase)
        %CHANGEDLATENCIESAREDETECTED  The data can be identical while the
        %   time base is not, and the window is applied against the times.
            EEG = testCase.tinyDataset();
            shifted = EEG; shifted.times = EEG.times + 100;
            testCase.verifyFalse(isequaln(SourceCache.Fingerprint(EEG), ...
                SourceCache.Fingerprint(shifted)));
        end

        function anEmptyDatasetFingerprintsWithoutComplaint(testCase)
        %ANEMPTYDATASETFINGERPRINTSWITHOUTCOMPLAINT  This runs on the reuse
        %   path, where throwing would turn a missed optimisation into a
        %   failed analysis.
            fingerprint = SourceCache.Fingerprint(struct('data', []));
            testCase.verifyTrue(isstruct(fingerprint));
        end
    end

    methods (Access = private)
        function opts = settings(~)
            opts = struct('SourceSpace', 5124, 'Method', 'mne', ...
                'Orientation', 'normal', 'RegParam', 0.05, ...
                'TimeWindow', [250 450], 'ResampleHz', 100);
        end

        function EEG = datasetWithEstimate(testCase, times, residualVariance, epochTimes)
        %DATASETWITHESTIMATE  A dataset carrying one stored estimate over
        %   TIMES, with each vertex's value equal to its latency index so a
        %   crop is recognisable in the result rather than merely the right
        %   shape.
        %
        %   EPOCHTIMES defaults to TIMES, the ordinary case of an estimate
        %   spanning its whole epoch. Pass a wider or finer one to build the
        %   case where the estimate CANNOT answer: coverage is judged
        %   against the latencies the compute path would select from the
        %   epoch, so an estimate narrower than its own epoch is the only
        %   way to be short of them.
            if nargin < 4 || isempty(epochTimes)
                epochTimes = times;
            end
            rng(4);
            EEG = struct('data', randn(2, numel(epochTimes), 1), 'times', epochTimes);
            values = repmat(1:numel(times), 3, 1);

            info = struct('ScaleLabel', 'dSPM');
            if nargin > 2
                info.ResidualVariance = residualVariance;
            end

            % The fingerprint is taken before the estimate is attached, the
            % same order SourceEstimate itself uses: it identifies the DATA,
            % not the struct that ends up carrying it.
            EEG.sourceEstimate = struct( ...
                'values', values, ...
                'times', times, ...
                'bins', {{'A'}}, ...
                'vertexLabels', {{{'v1', 'v2', 'v3'}}}, ...
                'info', info, ...
                'key', SourceCache.Key({'fz', 'cz'}, testCase.settings()), ...
                'dataFingerprint', SourceCache.Fingerprint(EEG));
        end

        function EEG = tinyDataset(~)
            rng(9);
            EEG = struct('data', randn(4, 10, 2), 'times', 0:10:90);
        end
    end
end
