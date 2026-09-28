classdef SpectralMeasureViewControlsTest < matlab.unittest.TestCase
%SPECTRALMEASUREVIEWCONTROLSTEST  The Spectral Measure view picks its
%   channel and bin with dropdowns above the plot, as FourierView and the
%   other views do, and has no buttons.
%
%   The dropdowns and the keys are two ways to the same state, so each is
%   checked both ways: picking in a dropdown changes what is drawn, and
%   stepping with a key, or a focus shared from another view, moves the
%   dropdowns along.
%
%   Run with: runtests('tests/SpectralMeasureViewControlsTest.m').
%
%   See also SPECTRALMEASUREVIEW, ZOOMSLIDERS, VIEWFOCUSTEST,
%   FOURIERVIEWCONTROLSTEST.

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
            [view, cleanup] = testCase.openView(spectrum({'A', 'B'})); %#ok<ASGLU>
            testCase.verifyEmpty(findall(view.Figure, 'Type', 'uibutton'));
            testCase.verifyNotEmpty(findall(view.Figure, 'Tag', 'XZoom'), 'The zoom sliders stay.');
        end

        function thereIsAChannelAndABinDropdown(testCase)
            [view, cleanup] = testCase.openView(spectrum({'A', 'B'})); %#ok<ASGLU>
            testCase.verifyEqual(string(view.ChannelDropdown.Items), ["Fz", "Cz", "Oz"]);
            testCase.verifyEqual(string(view.BinDropdown.Items), ["A", "B"]);
        end

        function pickingInTheDropdownsDrawsThatSpectrum(testCase)
            eeg = spectrum({'A', 'B'});
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            choose(view.ChannelDropdown, 3);
            choose(view.BinDropdown, 2);

            testCase.verifyEqual([view.Channel, view.CurrentBin], [3, 2]);
            curve = findobj(view.Axes, 'Tag', 'SpectrumLine');
            testCase.verifyEqual(curve.YData, eeg.spectrum(3, :, 2), 'AbsTol', 1e-12);
        end

        function theKeysAndASharedFocusMoveTheDropdownsAlong(testCase)
            [view, cleanup] = testCase.openView(spectrum({'A', 'B'})); %#ok<ASGLU>

            view.onKey(struct('Key', 'downarrow'));
            view.onKey(struct('Key', 'rightarrow'));
            testCase.verifyEqual([view.ChannelDropdown.Value, view.BinDropdown.Value], [2, 2]);

            view.applyFocus(struct('Channel', 'Oz', 'Bin', 'A'));
            testCase.verifyEqual([view.ChannelDropdown.Value, view.BinDropdown.Value], [3, 1]);
        end

        function oneBinHasOnlyTheChannelDropdown(testCase)
            [view, cleanup] = testCase.openView(spectrum({'A'})); %#ok<ASGLU>
            testCase.verifyEmpty(view.BinDropdown);
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
            view = SpectralMeasureView(uitab(uitabgroup(fig)), eeg);
        end
    end
end

function eeg = spectrum(bins)
%SPECTRUM  A SpectralMeasure result at Fz, Cz and Oz, one bin per label in
%   BINS, every spectrum flat at 10*channel + bin so a line can be told by
%   its value, and no measurement markers (as ViewFocusTest's).
    labels = {'Fz', 'Cz', 'Oz'};
    eeg = struct();
    eeg.srate = 1000;
    eeg.chanlocs = struct('labels', labels);
    eeg.specFreqs = 0:0.5:100;
    eeg.spectrum = zeros(numel(labels), numel(eeg.specFreqs), numel(bins));
    for c = 1:numel(labels)
        for b = 1:numel(bins)
            eeg.spectrum(c, :, b) = 10 * c + b;
        end
    end
    eeg.spectralMeasures = {};
    eeg.bindesc = struct('label', bins, 'index', num2cell(1:numel(bins)));
end

function choose(dropdown, value)
%CHOOSE  Pick VALUE in DROPDOWN as a user would: set it, then fire its
%   ValueChangedFcn, which a programmatic Value change does not.
    dropdown.Value = value;
    dropdown.ValueChangedFcn(dropdown, []);
end
