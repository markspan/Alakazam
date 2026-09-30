classdef CoherenceTopographyViewTest < matlab.unittest.TestCase
%COHERENCETOPOGRAPHYVIEWTEST  The CohTopo view draws every bin's map in one
%   plot and lets the side column choose which.
%
%   It used to show one bin at a time behind a dropdown, which made the
%   comparison a coherence topography is for (one condition's focus against
%   another's) a matter of memory. The cases pin the new behaviour: all bins
%   at once, a tickbox per bin that hides and shows its map, and a focus
%   from another view that adds its bin rather than replacing the others.
%
%   Views are real, in a hidden uifigure, as in ViewFocusTest. The maps may
%   come out as "no map" where EEGLAB's topoplot is not on the path; what is
%   checked is which bins are drawn, which holds either way.
%
%   Run with: runtests('tests/CoherenceTopographyViewTest.m').
%
%   See also COHERENCETOPOGRAPHYVIEW, COHERENCETOPOGRAPHY.

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
        function everyBinIsDrawnAtOnce(testCase)
            view = testCase.view(topography({'60 Hz', '64 Hz', 'Peripheral', 'SSVEP'}));

            testCase.verifyNumElements(view.Axes, 4);
            testCase.verifyEqual(titles(view), {'60 Hz', '64 Hz', 'Peripheral', 'SSVEP'});
            testCase.verifyNumElements(findall(view.CheckboxGrid, 'Type', 'uicheckbox'), 4);
        end

        function untickingABinTakesItsMapAway(testCase)
            view = testCase.view(topography({'60 Hz', '64 Hz', 'SSVEP'}));

            toggle(view, '64 Hz', false);

            testCase.verifyEqual(titles(view), {'60 Hz', 'SSVEP'});
            toggle(view, '64 Hz', true);
            testCase.verifyEqual(titles(view), {'60 Hz', '64 Hz', 'SSVEP'});
        end

        function withNothingTickedTheViewSaysSo(testCase)
            view = testCase.view(topography({'60 Hz', '64 Hz'}));

            toggle(view, '60 Hz', false);
            toggle(view, '64 Hz', false);

            testCase.verifyEmpty(view.Axes);
            note = findall(view.MapGrid, 'Type', 'uilabel');
            testCase.verifySubstring(note(1).Text, 'Tick a bin');
        end

        function aFocusAddsItsBinAndKeepsTheOthers(testCase)
            view = testCase.view(topography({'60 Hz', '64 Hz', 'SSVEP'}));
            toggle(view, 'SSVEP', false);

            view.applyFocus(struct('Bin', 'SSVEP'));

            testCase.verifyEqual(titles(view), {'60 Hz', '64 Hz', 'SSVEP'});
            testCase.verifyEqual(view.currentFocus().Bin, '60 Hz');
        end
    end

    methods (Access = private)
        function view = view(testCase, eeg)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            view = CoherenceTopographyView(uitab(uitabgroup(fig)), eeg);
        end
    end
end

% ======================================================================= %
function eeg = topography(binLabels)
%TOPOGRAPHY  A CoherenceTopography result over four scalp channels and a
%   photodiode reference, one frequency per bin.
    labels = {'O1', 'Oz', 'O2', 'Pz', 'Diode'};
    theta = [-18, 0, 18, 0, 0];
    radius = [0.5, 0.5, 0.5, 0.35, 0];
    chanlocs = struct('labels', labels, 'theta', num2cell(theta), 'radius', num2cell(radius));
    nBins = numel(binLabels);
    eeg = struct();
    eeg.chanlocs = chanlocs;
    eeg.CohTopoValues = [rand(4, nBins); nan(1, nBins)];
    eeg.CohTopoDrawn = 1:4;
    eeg.CohTopoChanlocs = chanlocs(1:4);
    eeg.CohTopoFreqs = nan(1, nBins);   % no frequency: titles are the labels alone
    eeg.CohTopoRef = 'Diode';
    eeg.CohTopoLimit = 1;
    eeg.CohTopoBinLabels = binLabels;
    eeg.CohTopoMethod = 'frames';
end

function toggle(view, label, value)
%TOGGLE  Tick or untick LABEL's box as a click would.
    boxes = findall(view.CheckboxGrid, 'Type', 'uicheckbox');
    box = boxes(strcmp({boxes.Text}, label));
    box.Value = value;
    box.ValueChangedFcn(box, []);
end

function t = titles(view)
%TITLES  The label each drawn map is titled with, in order (a map that
%   could not be drawn is titled "<label> (no map: ...)").
    t = arrayfun(@(ax) regexprep(char(string(ax.Title.String)), ' \(no map:.*$', ''), ...
        view.Axes, 'UniformOutput', false);
end
