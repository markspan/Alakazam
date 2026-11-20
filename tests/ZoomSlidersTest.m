classdef ZoomSlidersTest < matlab.unittest.TestCase
%ZOOMSLIDERSTEST  The x and y zoom sliders under a spectrum plot.
%
%   The x zoom is a fraction of 0 Hz to Nyquist, anchored at the axes' left
%   edge as it is, so 0 Hz stays in view until the toolbar pans away from
%   it, and a pan is then kept; the window never leaves [0, Nyquist]. The y
%   zoom is relative to whatever natural range the view last gave it: on a
%   linear axis it scales that range towards 0 (a magnitude keeps 0 at the
%   bottom, a phase stays centred on 0), on a log axis it keeps the bottom
%   and brings the top down in decades, and it survives the view redrawing
%   another channel.
%
%   The mouse wheel (scrollYZoom) zooms the same y range by 1.25 a notch,
%   past both ends of the slider's: beyond a hundredth of the range in, and
%   beyond the natural range out. The slider follows where it can and rests
%   at its end where it cannot, and dragging it takes over again.
%
%   Each case zooms by setting a slider and firing its callback, as a user's
%   release of the slider does. 0.5 on the slider is a tenth of the range
%   (0.01^0.5).
%
%   Run with: runtests('tests/ZoomSlidersTest.m').
%
%   See also ZOOMSLIDERS, FOURIERVIEW, SPECTRALMEASUREVIEW.

    properties
        Figure
        Axes
        Zoom
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Views')));
        end
    end

    methods (TestMethodSetup)
        function build(testCase)
        %BUILD  A plot with Nyquist at 125 Hz and its two sliders.
            try
                testCase.Figure = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            testCase.addTeardown(@() delete(testCase.Figure));
            grid = uigridlayout(testCase.Figure, [3 1], "RowHeight", {'1x', 24, 24});
            testCase.Axes = uiaxes(grid);
            testCase.Axes.Layout.Row = 1;
            testCase.Zoom = ZoomSliders(grid, [2 3], testCase.Axes, 125, []);
        end
    end

    methods (Test)
        function theXZoomKeepsZeroHertzInView(testCase)
            testCase.verifyEqual(xlim(testCase.Axes), [0, 125], 'The whole range to start with.');
            testCase.slide('XZoom', 0.5);
            testCase.verifyEqual(xlim(testCase.Axes), [0, 12.5], 'AbsTol', 1e-9);
        end

        function theXZoomKeepsAPanMadeWithTheToolbar(testCase)
            testCase.slide('XZoom', 0.5);
            testCase.Axes.XLim = [50, 62.5];   % as the toolbar's pan leaves it
            testCase.slide('XZoom', 0.25);
            testCase.verifyEqual(xlim(testCase.Axes), [50, 50 + 125 * 0.01 ^ 0.25], 'AbsTol', 1e-9);
        end

        function theXZoomStaysInsideTheRange(testCase)
            testCase.Axes.XLim = [120, 125];
            testCase.slide('XZoom', 0.5);
            testCase.verifyEqual(xlim(testCase.Axes), [112.5, 125], 'AbsTol', 1e-9);
        end

        function aLinearYZoomScalesTowardsZero(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 10]);
            testCase.slide('YZoom', 0.5);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 1], 'AbsTol', 1e-12);
        end

        function aPhaseStaysCentredOnZero(testCase)
            testCase.Zoom.applyYZoom(pi, -pi);
            testCase.slide('YZoom', 0.5);
            testCase.verifyEqual(ylim(testCase.Axes), [-pi, pi] / 10, 'AbsTol', 1e-12);
        end

        function aLogYZoomKeepsTheBottom(testCase)
            testCase.Axes.YScale = 'log';
            testCase.Zoom.applyYZoom(1000, 1);
            testCase.verifyEqual(ylim(testCase.Axes), [1, 1000], 'AbsTol', 1e-9);
            testCase.slide('YZoom', 0.5);
            testCase.verifyEqual(ylim(testCase.Axes), [1, 1000 ^ 0.1], 'AbsTol', 1e-9, ...
                'A tenth of the decades, from the bottom up, as 0.5 is a tenth of a linear range.');
        end

        function theYZoomSurvivesARedrawOfAnotherChannel(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.slide('YZoom', 0.5);
            testCase.Zoom.applyYZoom(20);   % the view redrawing a channel twice as large
            testCase.verifyEqual(ylim(testCase.Axes), [0, 2], 'AbsTol', 1e-12);
        end
    end

    methods (Test)
        % ---- the mouse wheel ------------------------------------------------
        function theWheelZoomsInPastTheSlider(testCase)
        %THEWHEELZOOMSINPASTTHESLIDER  Thirty notches away from the user are
        %   1.25^-30, about an 800th of the range, where the slider stops at
        %   a hundredth; the slider rests at its end.
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(-30);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 10 * 1.25 ^ -30], 'RelTol', 1e-12);
            testCase.verifyEqual(testCase.slider('YZoom').Value, 1);
        end

        function theWheelZoomsOutPastTheNaturalRange(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(4);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 10 * 1.25 ^ 4], 'RelTol', 1e-12);
            testCase.verifyEqual(testCase.slider('YZoom').Value, 0);
        end

        function aPhaseZoomedOutStaysCentredOnZero(testCase)
            testCase.Zoom.applyYZoom(pi, -pi);
            testCase.Zoom.scrollYZoom(2);
            testCase.verifyEqual(ylim(testCase.Axes), [-pi, pi] * 1.25 ^ 2, 'RelTol', 1e-12);
        end

        function theSliderFollowsTheWheelWithinItsRange(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(-10);
            testCase.verifyEqual(testCase.slider('YZoom').Value, ...
                log(1.25 ^ -10) / log(0.01), 'AbsTol', 1e-12);
        end

        function theSliderTakesOverFromTheWheel(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(-40);
            testCase.slide('YZoom', 0.5);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 1], 'AbsTol', 1e-12);
        end

        function aWheelZoomSurvivesARedrawOfAnotherChannel(testCase)
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(3);
            testCase.Zoom.applyYZoom(20);   % the view redrawing a channel twice as large
            testCase.verifyEqual(ylim(testCase.Axes), [0, 20 * 1.25 ^ 3], 'RelTol', 1e-12);
        end

        function onALogAxisTheWheelMovesTheTopInDecades(testCase)
            testCase.Axes.YScale = 'log';
            testCase.Zoom.applyYZoom(1000, 1);
            testCase.Zoom.scrollYZoom(-2);
            testCase.verifyEqual(ylim(testCase.Axes), [1, 1000 ^ (1.25 ^ -2)], 'RelTol', 1e-9);
        end

        function theWheelStopsShortOfAnUndrawableRange(testCase)
        %THEWHEELSTOPSSHORTOFANUNDRAWABLERANGE  No limit a user would meet,
        %   but a millionth of the range at most, so the axis can still be
        %   drawn however far the wheel is turned.
            testCase.Zoom.applyYZoom(10);
            testCase.Zoom.scrollYZoom(-1000);
            testCase.verifyEqual(ylim(testCase.Axes), [0, 10 * 1e-6], 'RelTol', 1e-12);
        end
    end

    methods (Access = private)
        function s = slider(testCase, tag)
        %SLIDER  The slider tagged TAG.
            s = findall(testCase.Figure, 'Tag', tag);
        end

        function slide(testCase, tag, value)
        %SLIDE  Move the slider tagged TAG to VALUE and release it.
            slider = findall(testCase.Figure, 'Tag', tag);
            slider.Value = value;
            slider.ValueChangedFcn(slider, []);
        end
    end
end
