classdef ArtefactDetectBreakdownTest < matlab.unittest.TestCase
%ARTEFACTDETECTBREAKDOWNTEST  The per-detector record ArtefactDetect writes
%   as it runs, which the tree's "Rejection breakdown..." reads.
%
%   Knowing a trial was rejected is not the same as knowing which of the four
%   detectors did it, and with several ticked that is the question that tells
%   you which threshold to move. These cases pin the counting, especially the
%   part a reader is most likely to get wrong: the per-detector figures
%   OVERLAP and do not sum to the total.
%
%   Run with: runtests('tests/ArtefactDetectBreakdownTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'ArtefactDetect'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theBreakdownIsAlwaysRecorded(testCase)
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            out = ArtefactDetect(EEG, testCase.opts({'Absolute threshold'}));

            testCase.assertTrue(isfield(out.etc.alz, 'artefactDetectors'));
            b = out.etc.alz.artefactDetectors;
            testCase.verifyEqual(b.methods, {'Absolute threshold'});
            testCase.verifyEqual(b.nTrials, 3);
        end

        function oneDetectorAccountsForEverythingItself(testCase)
        %ONEDETECTORACCOUNTSFOREVERYTHINGITSELF  With a single detector the
        %   attribution is trivial but must still be right: its own count,
        %   its "only this" count and the total are all the same number.
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            EEG.data(1, 5, 2) = 500;

            out = ArtefactDetect(EEG, testCase.opts({'Absolute threshold'}));
            b = out.etc.alz.artefactDetectors;

            testCase.verifyEqual(b.epochs, 1);
            testCase.verifyEqual(b.onlyThis, 1);
            testCase.verifyEqual(b.totalEpochs, 1);
        end

        function theTotalMatchesWhatWasActuallyRejected(testCase)
        %THETOTALMATCHESWHATWASACTUALLYREJECTED  The report has to agree with
        %   the data beside it, or it is worse than no report.
            EEG = makeTestEEG('nbchan', 3, 'trials', 5);
            EEG.data(1, 5, 2) = 500;     % absolute threshold
            EEG.data(2, 9, 4) = -500;    % absolute threshold, another trial

            out = ArtefactDetect(EEG, testCase.opts({'Absolute threshold'}));
            b = out.etc.alz.artefactDetectors;

            rejected = squeeze(any(any(isnan(out.data), 1), 2));
            testCase.verifyEqual(b.totalEpochs, nnz(rejected));
            testCase.verifyEqual(b.totalEpochs, 2);
        end

        function eachDetectorIsCountedOnItsOwn(testCase)
        %EACHDETECTORISCOUNTEDONITSOWN  The point of the feature. One trial
        %   carries a lone spike (sample-to-sample), another a sustained
        %   step (step function), and each detector must be credited with
        %   the trial it alone explains.
            EEG = makeTestEEG('nbchan', 1, 'trials', 4);
            EEG.data(:) = 0;
            EEG.data(1, 10, 2) = 150;                  % a one-sample jump
            half = round(size(EEG.data, 2) / 2);
            EEG.data(1, half:end, 3) = 1000;           % a sustained step

            o = testCase.opts({'Step function', 'Sample-to-sample'});
            o.Threshold = 100;
            out = ArtefactDetect(EEG, o);
            b = out.etc.alz.artefactDetectors;

            step = find(strcmp(b.methods, 'Step function'), 1);
            s2s  = find(strcmp(b.methods, 'Sample-to-sample'), 1);
            testCase.verifyTrue(b.epochMask(2, s2s), 'The spike is sample-to-sample.');
            testCase.verifyTrue(b.epochMask(3, step), 'The step is the step function.');
            testCase.verifyFalse(b.epochMask(1, step), 'Trial 1 is clean.');
            testCase.verifyFalse(b.epochMask(1, s2s));
            testCase.verifyEqual(b.totalEpochs, 2);
        end

        function overlappingDetectorsDoNotSumToTheTotal(testCase)
        %OVERLAPPINGDETECTORSDONOTSUMTOTHETOTAL  The reading trap, pinned. A
        %   big excursion trips several detectors on the SAME trial, so the
        %   per-detector counts add up to more than the number of trials
        %   actually lost. Anyone treating them as a partition would blame
        %   the wrong detector.
            EEG = makeTestEEG('nbchan', 1, 'trials', 4);
            EEG.data(:) = 0;
            EEG.data(1, 10, 2) = 500;   % over the threshold AND a jump

            o = testCase.opts({'Absolute threshold', 'Sample-to-sample'});
            o.Threshold = 100;
            out = ArtefactDetect(EEG, o);
            b = out.etc.alz.artefactDetectors;

            testCase.verifyEqual(b.totalEpochs, 1, 'One trial was lost.');
            testCase.verifyEqual(sum(b.epochs), 2, 'But two detectors each claim it.');
            testCase.verifyEqual(b.onlyThis, [0 0], ...
                'And neither caught it alone, so switching either off loses nothing.');
        end

        function onlyThisNamesTheDetectorYouCannotRemove(testCase)
        %ONLYTHISNAMESTHEDETECTORYOUCANNOTREMOVE  The actionable column: a
        %   trial only one detector can see makes that detector the one you
        %   would actually lose data by switching off.
            EEG = makeTestEEG('nbchan', 1, 'trials', 4);
            EEG.data(:) = 0;
            EEG.data(1, 10, 2) = 500;                  % both detectors
            EEG.data(1, 20, 3) = 150;                  % a jump under +/-500

            o = testCase.opts({'Absolute threshold', 'Sample-to-sample'});
            o.Minimum = -400; o.Maximum = 400; o.Threshold = 100;
            out = ArtefactDetect(EEG, o);
            b = out.etc.alz.artefactDetectors;

            abs_ = find(strcmp(b.methods, 'Absolute threshold'), 1);
            s2s  = find(strcmp(b.methods, 'Sample-to-sample'), 1);
            testCase.verifyEqual(b.onlyThis(abs_), 0, ...
                'Everything the threshold caught, the jump detector caught too.');
            testCase.verifyEqual(b.onlyThis(s2s), 1, ...
                'But trial 3 is only visible to the jump detector.');
            testCase.verifyEqual(b.totalEpochs, 2);
        end

        function noDetectorsTickedStillRecordsAnEmptyReport(testCase)
        %NODETECTORSTICKEDSTILLRECORDSANEMPTYREPORT  So the tree can say "no
        %   detectors were ticked" rather than having to treat a missing
        %   field, which it cannot tell apart from an old node.
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            out = ArtefactDetect(EEG, testCase.opts({}));

            testCase.assertTrue(isfield(out.etc.alz, 'artefactDetectors'));
            b = out.etc.alz.artefactDetectors;
            testCase.verifyEmpty(b.methods);
            testCase.verifyEqual(b.totalEpochs, 0);
            testCase.verifyEqual(b.nTrials, 3);
            testCase.verifyEqual(size(b.epochMask), [3 0]);
        end

        function theChannelScopeIsReportedAlongsideTheCounts(testCase)
        %THECHANNELSCOPEISREPORTEDALONGSIDETHECOUNTS  A count is unreadable
        %   without knowing how many channels it was taken over, so the
        %   record carries that too.
            EEG = makeTestEEG('nbchan', 3, 'trials', 2);
            o = testCase.opts({'Absolute threshold'});
            out = ArtefactDetect(EEG, o);
            b = out.etc.alz.artefactDetectors;

            testCase.verifyEqual(b.channelsTested, 3);
            testCase.verifyEqual(b.scope, 'Whole epoch');
        end

        function channelEpochCountsAreCompleteUnderAPerChannelScope(testCase)
        %CHANNELEPOCHCOUNTSARECOMPLETEUNDERAPERCHANNELSCOPE  Two channels of
        %   one trial both over the threshold count as two channel-epochs,
        %   not one: the old loop stopped at the first bad channel, which
        %   would have under-reported this.
            EEG = makeTestEEG('nbchan', 3, 'trials', 2);
            EEG.data(1, 5, 1) = 500;
            EEG.data(2, 6, 1) = 500;

            o = testCase.opts({'Absolute threshold'});
            o.Scope = 'This channel only';
            out = ArtefactDetect(EEG, o);
            b = out.etc.alz.artefactDetectors;

            testCase.verifyEqual(b.channelEpochs, 2);
            testCase.verifyEqual(b.epochs, 1, 'Both are in the same trial.');
        end
    end

    methods (Access = private)
        function o = opts(~, methods)
            o = struct('Method', {methods}, 'Minimum', -100, 'Maximum', 100, ...
                'Threshold', 100, 'Window', 200, 'Step', 50, ...
                'TestStart', 0, 'TestStop', 0, ...
                'Channels', 'All channels', 'Scope', 'Whole epoch');
        end
    end
end
