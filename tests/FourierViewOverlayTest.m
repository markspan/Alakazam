classdef FourierViewOverlayTest < matlab.unittest.TestCase
%FOURIERVIEWOVERLAYTEST  Overlaying one spectrum on another, as
%   ErpOverlayTest does for ERPs: what may be overlaid (and why not), that
%   every line shows the electrode named in the title, how overlaid lines
%   are drawn and named, a difference across two datasets, and taking the
%   overlay off again.
%
%   Every spectrum is flat at a level that says where it came from: the
%   dataset's LEVEL, plus 10 times a number per electrode name (the same in
%   every dataset), plus the bin. A line can so be told by its value, and
%   the optional smoothing of the plotted spectrum (Settings) leaves it as
%   it is.
%
%   Views are real FourierViews in a hidden uifigure.
%
%   Run with: runtests('tests/FourierViewOverlayTest.m').
%
%   See also FOURIERVIEW, DATASETOVERLAYPROBLEM, OVERLAYNAMES, ERPOVERLAYTEST.

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
        % ---- what may be overlaid ----------------------------------------
        function aSpectrumInAnotherUnitIsRefused(testCase)
            [view, cleanup] = testCase.openView(spectra('a', 'unit', 'Power')); %#ok<ASGLU>
            problem = view.addDataset(spectra('b', 'unit', 'Volt'));
            testCase.verifySubstring(problem, 'cannot share an axis');
            testCase.verifyNumElements(spectrumLines(view), 2, 'A refused overlay leaves the plot alone.');
        end

        function singleTrialSpectraAreRefused(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.verifySubstring(view.addDataset(singleTrials('b')), 'single-trial');
        end

        function aSingleTrialPlotTakesNoOverlay(testCase)
            [view, cleanup] = testCase.openView(singleTrials('a')); %#ok<ASGLU>
            testCase.verifySubstring(view.addDataset(spectra('b')), 'single trials');
        end

        function aWaveformIsNotASpectrum(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            erp = spectra('b');
            erp.DataType = 'TimeDomain';
            testCase.verifySubstring(view.addDataset(erp), 'not a spectrum');
        end

        function noChannelInCommonIsRefused(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.verifySubstring(view.addDataset(spectra('b', 'labels', {'Pz'})), ...
                'no channel in common');
        end

        function theSameDatasetTwiceIsRefused(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b')));
            testCase.verifySubstring(view.addDataset(spectra('b')), 'already');
        end

        % ---- the lines -----------------------------------------------------
        function overlaidLinesArePalerAndGoUnderneath(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b', 'level', 200)));

            own = lineOf(view, 1);
            overlaid = lineOf(view, 3);
            testCase.verifyEqual(own.Color, lineColour(1), 'AbsTol', 1e-12);
            testCase.verifyEqual(overlaid.Color, 0.5 * lineColour(3) + 0.5 * view.Axes.Color, ...
                'AbsTol', 1e-12, 'An overlaid line is paler, by the overlay opacity.');
            children = view.Axes.Children;
            testCase.verifyLessThan(find(children == own), find(children == overlaid), ...
                'The plot''s own line is drawn on top of the overlaid one.');

            view.setOverlayOpacity(1);
            testCase.verifyEqual(lineOf(view, 3).Color, lineColour(3), 'AbsTol', 1e-12);
        end

        function everyLineShowsTheElectrodeInTheTitle(testCase)
        %EVERYLINESHOWSTHEELECTRODEINTHETITLE  The overlaid dataset's
        %   channels are in another order, so it must be matched by name.
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b', 'level', 200, 'labels', {'Cz', 'Fz'})));

            view.onKey(struct('Key', 'downarrow'));   % to Cz

            testCase.verifyEqual(unique(lineOf(view, 3).YData), 200 + 10 * code('Cz') + 1);
        end

        function aSpectrumOfAnotherResolutionIsDrawnOnItsOwnFrequencies(testCase)
            [view, cleanup] = testCase.openView(spectra('a', 'nfreq', 129)); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b', 'nfreq', 257)));
            testCase.verifyNumElements(lineOf(view, 3).XData, 257);
        end

        function linesAreNamedByWhatSetsTheirDatasetsApart(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            view.setDatasetPath('a', {'S01', 'Fourier', 'Average'});
            testCase.assertEmpty(view.addDataset(spectra('b'), {'S02', 'Fourier', 'Average'}));

            testCase.verifyEqual(string(view.Axes.Legend.String), ...
                ["S01: Low", "S01: High", "S02: Low", "S02: High"]);
        end

        function aSingleSpectrumGetsTheStripOnceSomethingIsOverlaid(testCase)
        %ASINGLESPECTRUMGETSTHESTRIPONCESOMETHINGISOVERLAID  A Welch spectrum
        %   alone is one black line with nothing to tick; with a second one
        %   overlaid, both are lines to tick, compare and take off again.
            [view, cleanup] = testCase.openView(spectra('a', 'bins', {}, 'unit', 'PSD')); %#ok<ASGLU>
            testCase.verifyEmpty(findall(view.Strip, 'Type', 'uicheckbox'));
            testCase.verifyEqual(lineOf(view, 1).Color, [0 0 0]);

            testCase.assertEmpty(view.addDataset(spectra('b', 'bins', {}, 'unit', 'PSD')));

            testCase.verifyNumElements(findall(view.Strip, 'Type', 'uicheckbox'), 2);
            testCase.verifyEqual(lineOf(view, 1).Color, lineColour(1), 'AbsTol', 1e-12);
            testCase.verifyEqual(char(control(view, 'DifferenceButton').Enable), 'on');
        end

        % ---- the difference -----------------------------------------------
        function aDifferenceAcrossDatasetsIsInterpolatedOntoTheFirst(testCase)
            [view, cleanup] = testCase.openView(spectra('a', 'nfreq', 129)); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b', 'level', 200, 'nfreq', 257)));

            tick(view, 2, false);   % a's High
            tick(view, 4, false);   % b's High
            setState(control(view, 'DifferenceButton'), true);

            curve = findobj(view.Axes, 'Tag', 'DifferenceLine');
            testCase.verifyNumElements(curve.XData, 129, 'On the first line''s frequencies.');
            testCase.verifyEqual(curve.YData, -100 * ones(1, 129), 'AbsTol', 1e-9, ...
                'a''s Low minus b''s Low at Fz.');
        end

        % ---- taking it off --------------------------------------------------
        function removingTheOverlayKeepsThePlotsOwnLines(testCase)
            [view, cleanup] = testCase.openView(spectra('a')); %#ok<ASGLU>
            testCase.assertEmpty(view.addDataset(spectra('b')));
            tick(view, 2, false);

            push(control(view, 'RemoveOverlayButton'));

            testCase.verifyNumElements(view.Series, 2);
            testCase.verifyEqual(view.Visible, [true false], 'The plot''s own ticks are kept.');
            testCase.verifyEmpty(control(view, 'RemoveOverlayButton'));
            testCase.verifyEmpty(view.addDataset(spectra('b')), 'It can be overlaid again.');
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
end

% ======================================================================= %
function eeg = spectra(file, varargin)
%SPECTRA  An averaged spectrum saved as FILE: bins Low and High (or, with
%   'bins' {}, one spectrum of a continuous recording, as Welch makes) at
%   the channels called 'labels', each flat at LEVEL + 10*CODE(label) + bin,
%   in 'unit'.
    p = inputParser;
    p.addParameter('unit', 'Power');
    p.addParameter('level', 100);
    p.addParameter('labels', {'Fz', 'Cz'});
    p.addParameter('nfreq', 129);
    p.addParameter('bins', {'Low', 'High'});
    p.parse(varargin{:});
    o = p.Results;

    nBins = max(numel(o.bins), 1);
    data = zeros(numel(o.labels), o.nfreq, nBins);
    for c = 1:numel(o.labels)
        for b = 1:nBins
            data(c, :, b) = o.level + 10 * code(o.labels{c}) + b;
        end
    end
    eeg = struct('data', data, 'freqs', linspace(0, 125, o.nfreq), 'srate', 250, ...
        'nbchan', numel(o.labels), 'trials', 1, 'pnts', o.nfreq, ...
        'DataType', 'FrequencyDomain', 'DataFormat', 'Averaged', ...
        'chanlocs', struct('labels', o.labels), 'File', file, 'id', 'Average', ...
        'SpectrumUnit', o.unit);
    if isempty(o.bins)
        eeg.DataFormat = 'CONTINUOUS';
        eeg.id = 'Welch';
    else
        eeg.bindesc = struct('label', o.bins);
    end
end

function eeg = singleTrials(file)
%SINGLETRIALS  Fourier's output on epoched data: a spectrum per trial.
    eeg = spectra(file, 'bins', {});
    eeg.data = repmat(eeg.data, [1, 1, 3]);
    eeg.trials = 3;
    eeg.DataFormat = 'EPOCHED';
end

function c = code(label)
%CODE  A number per electrode name, the same in every dataset.
    c = find(strcmpi({'Fz', 'Cz', 'Pz'}, label), 1);
end

function h = lineOf(view, i)
    h = findobj(view.Axes, 'Tag', 'SpectrumLine', 'UserData', i);
end

function h = spectrumLines(view)
    h = findobj(view.Axes, 'Tag', 'SpectrumLine');
end

function h = control(view, tag)
%CONTROL  The strip's control tagged TAG, as it is now (the strip is rebuilt
%   on every redraw).
    h = findall(view.Strip, 'Tag', tag);
end

function tick(view, i, value)
%TICK  Tick or untick line I, as a user would.
    boxes = findall(view.Strip, 'Type', 'uicheckbox');
    rows = arrayfun(@(b) b.Layout.Row, boxes);
    setState(boxes(rows == i), value);
end

function setState(h, value)
%SETSTATE  Set a checkbox or state button to VALUE and fire its callback,
%   which a programmatic Value change does not.
    h.Value = value;
    h.ValueChangedFcn(h, []);
end

function push(h)
%PUSH  Push a button, as a click would.
    h.ButtonPushedFcn(h, []);
end
