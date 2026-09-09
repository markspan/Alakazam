classdef ViewFocusTest < matlab.unittest.TestCase
%VIEWFOCUSTEST  The channel and bin last looked at must survive moving to
%   another node in the workspace tree.
%
%   THE RULE THIS FILE EXISTS TO PIN IS "LABELS, NOT INDICES". Two datasets
%   in one workspace routinely differ in channel count and order: a
%   re-referenced set has lost its reference, an interpolated one has a
%   different montage, a spectral result carries only what it measured.
%   Remembering the index would show a different electrode while looking as
%   though it had worked, which is the failure a test has to rule out
%   because nothing on screen would reveal it.
%
%   Most cases run against ViewFocus itself, which needs no figure. The
%   last three open a real AverageView, because a view resolves the label
%   against its own labels, and a test of the memory alone would not notice
%   a view resolving it wrongly.
%
%   Run with: runtests('tests/ViewFocusTest.m').
%
%   See also VIEWFOCUS, ALAKAZAMPLOTTER, AVERAGEVIEW.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Views'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function itStartsWithNoMemory(testCase)
            focus = ViewFocus();
            testCase.verifyEmpty(focus.ChannelLabel);
            testCase.verifyEmpty(focus.BinLabel);
        end

        function aLabelIsFoundRegardlessOfCaseAndPadding(testCase)
        %ALABELISFOUNDREGARDLESSOFCASEANDPADDING  Labels arrive from several
        %   recording systems, and "CZ", "Cz" and "Cz " are the same
        %   electrode to everyone except strcmp.
            labels = {'Fz', 'Cz', 'Pz'};
            testCase.verifyEqual(ViewFocus.indexOfLabel(labels, 'Cz'), 2);
            testCase.verifyEqual(ViewFocus.indexOfLabel(labels, 'cz'), 2);
            testCase.verifyEqual(ViewFocus.indexOfLabel(labels, ' CZ '), 2);
        end

        function anAbsentLabelIsEmptyNotAGuess(testCase)
            testCase.verifyEmpty(ViewFocus.indexOfLabel({'Fz', 'Cz'}, 'Oz'));
            testCase.verifyEmpty(ViewFocus.indexOfLabel({}, 'Cz'));
            testCase.verifyEmpty(ViewFocus.indexOfLabel({'Fz'}, ''));
        end

        function aBinOnlyViewDoesNotEraseTheChannel(testCase)
        %ABINONLYVIEWDOESNOTERASETHECHANNEL  Moving through a mix of view
        %   kinds is ordinary: looking at a scalp map must not forget which
        %   electrode the waveform views were on.
            focus = ViewFocus();
            focus.capture(FakeFocusView('Cz', ''));
            focus.capture(FakeFocusView('', 'Related'));

            testCase.verifyEqual(focus.ChannelLabel, 'Cz');
            testCase.verifyEqual(focus.BinLabel, 'Related');
        end

        function aViewWithNoFocusIsSkipped(testCase)
        %AVIEWWITHNOFOCUSISSKIPPED  ReportView and SignalView implement
        %   neither method, and must not be an error to pass in.
            focus = ViewFocus();
            focus.capture([]);
            focus.apply([]);
            testCase.verifyEmpty(focus.ChannelLabel);
        end

        function nothingIsAppliedWhenNothingIsRemembered(testCase)
            focus = ViewFocus();
            view = FakeFocusView('Cz', '');
            focus.apply(view);
            testCase.verifyEmpty(view.Applied, ...
                'A fresh memory must leave a new view on its own default.');
        end

        function anAverageViewAdoptsARememberedChannel(testCase)
            [view, fig] = testCase.averageView({'Fz', 'Cz', 'Pz', 'Oz'});
            closeFig = onCleanup(@() delete(fig)); %#ok<NASGU>

            testCase.assertEqual(view.Channel, 1, 'A view should start on its first channel.');
            view.applyFocus(struct('Channel', 'Pz', 'Bin', ''));

            testCase.verifyEqual(view.Channel, 3);
            reported = view.currentFocus();
            testCase.verifyEqual(reported.Channel, 'Pz', ...
                'What the view reports back must be what it is showing.');
        end

        function aChannelThisMontageLacksLeavesTheViewAlone(testCase)
        %ACHANNELTHISMONTAGELACKSLEAVESTHEVIEWALONE  Moving from a wide
        %   recording to a result carrying four channels is ordinary, not an
        %   error, and the view keeps its own default.
            [view, fig] = testCase.averageView({'Fz', 'Cz'});
            closeFig = onCleanup(@() delete(fig)); %#ok<NASGU>

            view.applyFocus(struct('Channel', 'PO7', 'Bin', ''));
            testCase.verifyEqual(view.Channel, 1);
        end

        function theIndexIsNotWhatIsCarried(testCase)
        %THEINDEXISNOTWHATISCARRIED  The whole point, as a test. Cz is
        %   channel 2 in one montage and channel 4 in the other; carrying
        %   the index would land on Pz and look perfectly plausible.
            [wide, figA] = testCase.averageView({'Fp1', 'Cz', 'Pz', 'Oz'});
            closeA = onCleanup(@() delete(figA)); %#ok<NASGU>
            [narrow, figB] = testCase.averageView({'Fp1', 'F3', 'Pz', 'Cz'});
            closeB = onCleanup(@() delete(figB)); %#ok<NASGU>

            wide.applyFocus(struct('Channel', 'Cz', 'Bin', ''));
            testCase.assertEqual(wide.Channel, 2);

            focus = ViewFocus();
            focus.capture(wide);
            focus.apply(narrow);

            testCase.verifyEqual(narrow.Channel, 4, ...
                'The remembered label must be resolved in the new montage.');
        end
    end

    methods (Access = private)
        function [view, fig] = averageView(testCase, labels)
        %AVERAGEVIEW  A real AverageView over a dataset with LABELS.
            eeg = makeTestEEG('nbchan', numel(labels), 'labels', labels, 'trials', 1);
            eeg.DataFormat = 'Averaged';
            eeg.trials = 1;
            eeg.data = eeg.data(:, :, 1);
            eeg.File = 'fixture';
            eeg.id = 'Average';

            fig = uifigure('Visible', 'off');
            tab = uitab(uitabgroup(fig));
            view = AverageView(tab, eeg);
            testCase.assertNotEmpty(view);
        end
    end
end
