classdef FourierViewControlsTest < matlab.unittest.TestCase
%FOURIERVIEWCONTROLSTEST  The spectrum view picks its channel and bin (or
%   trial) with dropdowns above the plot, as the other views do, and has no
%   buttons.
%
%   The dropdowns and the keys are two ways to the same state, so each is
%   checked both ways: picking in a dropdown changes what is drawn, and
%   stepping with a key moves the dropdown along.
%
%   Run with: runtests('tests/FourierViewControlsTest.m').
%
%   See also FOURIERVIEW, ZOOMPANBUTTONS, FOURIERVIEWPHASETEST.

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
        function thereAreNoButtons(testCase)
            [view, cleanup] = testCase.openView(FourierViewControlsTest.averaged()); %#ok<ASGLU>
            testCase.verifyEmpty(findall(view.Figure, 'Type', 'uibutton'));
        end

        function anAverageHasAChannelAndABinDropdown(testCase)
            [view, cleanup] = testCase.openView(FourierViewControlsTest.averaged()); %#ok<ASGLU>

            testCase.verifyEqual(string(view.ChannelDropdown.Items), ["Fz", "Cz", "Pz"]);
            testCase.verifyEqual(string(view.StepDropdown.Items), ["Frequent", "Rare"]);
            testCase.verifyNotEmpty(findall(view.Figure, 'Type', 'uilabel', 'Text', 'Bin:'));
        end

        function pickingInTheDropdownsChangesWhatIsDrawn(testCase)
            eeg = FourierViewControlsTest.averaged();
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            choose(view.ChannelDropdown, 3);
            choose(view.StepDropdown, 2);

            testCase.verifyEqual([view.Channel, view.CurrentTrial], [3, 2]);
            curve = findobj(view.Axes, 'Type', 'line');
            testCase.verifyEqual(curve(1).YData, eeg.data(3, :, 2), 'AbsTol', 1e-12, ...
                'The spectrum of channel 3 in bin 2 is drawn.');
        end

        function theKeysMoveTheDropdownsAlong(testCase)
            [view, cleanup] = testCase.openView(FourierViewControlsTest.averaged()); %#ok<ASGLU>

            view.onKey(struct('Key', 'downarrow'));
            view.onKey(struct('Key', 'rightarrow'));

            testCase.verifyEqual(view.ChannelDropdown.Value, 2);
            testCase.verifyEqual(view.StepDropdown.Value, 2);
        end

        function singleTrialsArePickedByTrialWithTheirBin(testCase)
            [view, cleanup] = testCase.openView(FourierViewControlsTest.epoched()); %#ok<ASGLU>

            testCase.verifyNotEmpty(findall(view.Figure, 'Type', 'uilabel', 'Text', 'Trial:'));
            testCase.verifyEqual(string(view.StepDropdown.Items), ...
                ["1, in bin ""Frequent""", "2, in bin ""Frequent""", "3, in bin ""Rare"""]);
        end

        function oneSpectrumPerChannelHasOnlyTheChannelDropdown(testCase)
            eeg = FourierViewControlsTest.averaged();
            eeg.data = eeg.data(:, :, 1);
            eeg = rmfield(eeg, 'bindesc');
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            testCase.verifyEmpty(view.StepDropdown);
            testCase.verifyNumElements(findall(view.Figure, 'Type', 'uidropdown'), 1);
        end
    end

    methods (Access = private)
        function [view, cleanup] = openView(testCase, eeg)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            cleanup = onCleanup(@() delete(fig));
            view = FourierView(uitab(uitabgroup(fig)), eeg);
        end
    end

    methods (Static)
        function EEG = averaged()
        %AVERAGED  Three channels, two bins of an averaged spectrum, each
        %   channel and bin a flat spectrum at a level of its own (flat, so
        %   the optional smoothing of the plotted spectrum leaves it as is).
            freqs = linspace(0, 125, 129);
            data = zeros(3, numel(freqs), 2);
            for ch = 1:3
                for b = 1:2
                    data(ch, :, b) = 10 * ch + b;
                end
            end
            EEG = struct('data', data, 'freqs', freqs, 'srate', 250, 'nbchan', 3, ...
                'trials', 2, 'pnts', numel(freqs), 'DataType', 'FrequencyDomain', ...
                'DataFormat', 'Averaged', 'chanlocs', struct('labels', {'Fz', 'Cz', 'Pz'}), ...
                'bindesc', struct('label', {'Frequent', 'Rare'}, 'trials', {[1 2], 3}));
        end

        function EEG = epoched()
        %EPOCHED  The per-trial spectra of three trials, two of them in the
        %   first bin: Fourier keeps bindesc, which then describes trials.
            EEG = FourierViewControlsTest.averaged();
            EEG.data = cat(3, EEG.data, EEG.data(:, :, 1));
            EEG.trials = 3;
            EEG.DataFormat = 'EPOCHED';
        end
    end
end

function choose(dropdown, value)
%CHOOSE  Pick VALUE in DROPDOWN as a user would: set it, then fire its
%   ValueChangedFcn, which a programmatic Value change does not.
    dropdown.Value = value;
    dropdown.ValueChangedFcn(dropdown, []);
end
