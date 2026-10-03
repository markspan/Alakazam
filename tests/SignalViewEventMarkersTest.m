classdef SignalViewEventMarkersTest < matlab.unittest.TestCase
%SIGNALVIEWEVENTMARKERSTEST  The event markers of the continuous view are
%   redrawn, not added to: one marker per event in view, however often the
%   view is scrolled or zoomed.
%
%   An area event (one with a duration) is a shaded patch with its label
%   written over it. The view clears its markers by their tag before each
%   redraw, and only the patch was tagged, so every redraw left one more
%   copy of each visible area's label on the axes.
%
%   Run with: runtests('tests/SignalViewEventMarkersTest.m').
%
%   See also SIGNALVIEW, LABEL.

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
        function anAreaKeepsOneLabelThroughRedraws(testCase)
            [view, fig] = testCase.view();
            closeFig = onCleanup(@() delete(fig));
            show(view, 0, 0);   % the whole recording, the area in view

            for k = 1:5
                view.redraw();
            end
            testCase.verifyNumElements(findobj(view.Axes, 'Type', 'patch', 'Tag', 'event'), 1);
            testCase.verifyNumElements(findobj(view.Axes, 'Type', 'text', 'String', 'blink'), 1, ...
                'Each redraw should replace the area''s label, not add another.');
        end

        function anAreaScrolledOutOfViewTakesItsLabelWithIt(testCase)
            [view, fig] = testCase.view();
            closeFig = onCleanup(@() delete(fig));
            show(view, 0, 0);
            show(view, 0.9, 1);   % zoomed in on the end, the area's start out of view

            testCase.verifyEmpty(findobj(view.Axes, 'Type', 'patch', 'Tag', 'event'));
            testCase.verifyEmpty(findobj(view.Axes, 'Type', 'text', 'String', 'blink'));
        end
    end

    methods (Access = private)
        function [view, fig] = view(testCase)
        %VIEW  A SignalView of an 8 s recording with one area event, a
        %   "blink" of 1 s from 2 s, and one point event at 3.6 s.
            t = (0:1999) / 250;
            eeg = struct('srate', 250, 'nbchan', 2, 'trials', 1, 'pnts', numel(t), 'times', t, ...
                'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
                'chanlocs', struct('labels', {'Fz', 'Cz'}), 'File', 'fixture', 'id', 'Filter');
            eeg.data = [sin(2 * pi * t); cos(2 * pi * t)];
            eeg.event = struct('type', {'blink', 'S  1'}, 'latency', {500, 900}, 'duration', {250, 0});

            fig = uifigure('Visible', 'off', 'Position', [100 100 900 500]);
            tab = uitab(uitabgroup(fig, 'Position', [0 0 900 500]));
            view = SignalView(tab, eeg.times, eeg, ...
                "ShowAxisTicks", true, "YLimMode", "fixed", "MmPerSec", 25, ...
                "AutoStackSignals", string({eeg.chanlocs.labels}));
            testCase.assertNumElements(view.Overlay.AreaTime, 1, 'The fixture has one area event.');
        end
    end
end

% ======================================================================= %
function show(view, zoom, position)
%SHOW  The view at ZOOM (0 the whole recording) and scrolled to POSITION
%   (0 the start, 1 the end).
    view.ZoomSlider.Value = zoom;
    view.ScrollSlider.Value = position;
    view.redraw();
end
