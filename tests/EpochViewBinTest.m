classdef EpochViewBinTest < matlab.unittest.TestCase
%EPOCHVIEWBINTEST  EpochView's "Bin:" choice: one bin's trials alone, with
%   the average below taken over them, sortable, and remembered across
%   views as the other views' bin choices are.
%
%   Run with: runtests('tests/EpochViewBinTest.m').
%
%   See also EPOCHVIEW, VIEWFOCUS, EPOCHSORTTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function onlyBinsWithTrialsOfTheirOwnAreOffered(testCase)
            EEG = EpochViewBinTest.epoched();
            EEG.bindesc(3) = struct('index', 3, 'label', 'A-B', 'combo', ...
                struct('bin', {1, 2}, 'coeff', {1, -1}), 'trials', []);
            EEG.bindesc(4) = struct('index', 4, 'label', 'Empty', 'combo', [], 'trials', []);

            testCase.verifyEqual(EpochView.selectableBins(EEG), [1 2]);
            testCase.verifyEmpty(EpochView.selectableBins(rmfield(EEG, 'bindesc')));
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aChosenBinIsShownAloneWithItsOwnAverage(testCase)
            [view, cleanup] = testCase.openView(); %#ok<ASGLU>
            dropdown = view.BinDropdown;
            testCase.verifyEqual(dropdown.Items, {'All trials', 'A', 'B'});

            dropdown.Value = 3;                                   % "B"
            dropdown.ValueChangedFcn(dropdown, []);

            testCase.verifyEqual(view.TrialOrder, [2 4]);
            data = view.EEG.data;
            testCase.verifyEqual(view.TraceLine.YData, mean(squeeze(data(1, :, [2 4])), 2)', ...
                'AbsTol', 1e-12, 'The average below is over the bin shown.');
            testCase.verifySubstring(char(view.HeatAxes.Title.String), 'B');
            testCase.verifyEqual(view.Grid.ColumnWidth{1}, 0, 'One bin shown alone is not bracketed.');
            focus = view.currentFocus();
            testCase.verifyEqual(focus.Bin, 'B');
        end

        function aBinRememberedFromAnotherViewIsShown(testCase)
            [view, cleanup] = testCase.openView(); %#ok<ASGLU>

            view.applyFocus(struct('Channel', 'Pz', 'Bin', 'A'));

            testCase.verifyEqual(view.TrialOrder, [1 3]);
            testCase.verifyEqual(view.BinDropdown.Value, 2);
            testCase.verifyEqual(view.Channel, 2);

            view.BinDropdown.Value = 1;                           % back to "All trials"
            view.BinDropdown.ValueChangedFcn(view.BinDropdown, []);
            testCase.verifyEqual(sort(unique(view.TrialOrder)), 1:4);
            testCase.verifyFalse(isfield(view.currentFocus(), 'Bin'), ...
                '"All trials" reports no bin, so the remembered one is left alone.');
        end

        function aChosenBinIsSortedToo(testCase)
            [view, cleanup] = testCase.openView(); %#ok<ASGLU>
            view.BinDropdown.Value = 2;                           % "A": trials 1 and 3
            view.BinDropdown.ValueChangedFcn(view.BinDropdown, []);
            labels = view.SortDropdown.Items;

            view.SortDropdown.Value = find(strcmp(labels, 'Event: rating')) - 1;
            view.redraw();

            if AlakazamSettings.get("graphics", "epochImage", "reverseSort")
                testCase.verifyEqual(view.TrialOrder, [1 3]);
            else
                testCase.verifyEqual(view.TrialOrder, [3 1]);
            end
        end
    end

    methods (Access = private)
        function [view, cleanup] = openView(testCase)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            cleanup = onCleanup(@() delete(fig));
            view = EpochView(uitab(uitabgroup(fig)), EpochViewBinTest.epoched());
        end
    end

    methods (Static)
        function EEG = epoched()
        %EPOCHED  Four trials on two channels, bin A holding trials 1 and 3
        %   and bin B trials 2 and 4, each locked to an event with a rating.
            rng(4);
            times = -100:10:390;
            EEG = struct('data', randn(2, numel(times), 4), 'srate', 100, 'times', times, ...
                'pnts', numel(times), 'trials', 4, 'nbchan', 2, 'xmin', times(1) / 1000, ...
                'xmax', times(end) / 1000, 'DataFormat', 'EPOCHED', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}));
            EEG.event = struct('type', {'s', 's', 's', 's'}, 'latency', {11, 61, 111, 161}, ...
                'rating', {9, 1, 4, 7}, 'bini', {1, 2, 1, 2}, 'epoch', {1, 2, 3, 4});
            EEG.epoch = struct('event', {1, 2, 3, 4}, 'eventtype', {'s', 's', 's', 's'}, ...
                'eventlatency', {0, 0, 0, 0}, 'bini', {1, 2, 1, 2});
            EEG.bindesc = struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, ...
                'trials', {[1 3], [2 4]});
        end
    end
end
