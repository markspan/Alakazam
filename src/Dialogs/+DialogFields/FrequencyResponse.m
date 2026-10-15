classdef FrequencyResponse < DialogFields.Plot
%FREQUENCYRESPONSE  A filter's amplitude response, redrawn from the dialog's
%   current values: the gain in dB against a logarithmic frequency axis,
%   the level at which a cutoff is defined dotted across, and each cutoff
%   marked and labelled in Hz. It contributes nothing to the options.
%
%   DialogFields.FrequencyResponse(RESPONSEFCN, Name, Value)
%     RESPONSEFCN  @(values) returning [F, GAIN, CUTOFFS], where VALUES is
%                  a struct of every field's current value by name: the
%                  frequencies in Hz, the linear gain at each (1 passes a
%                  frequency unchanged, 0.5 halves it), and the cutoffs to
%                  mark, in Hz ([] for none, 0 for a filter that is off).
%                  An error it throws is shown in the plot instead, as Plot
%                  shows any drawing's.
%     'Floor'      the bottom of the gain axis, in dB (default -60)
%     'Level'      the linear gain at which the cutoffs are defined, dotted
%                  across (default 0.5, half amplitude, about -6 dB)
%     'Color'      the curve's colour
%     'Height'     in pixels (default 170)
%
%   DialogFields.FrequencyResponse.draw(AX, F, GAIN, Name, Value) draws the
%   same picture on any axes, with 'Cutoffs' and the options above. The
%   Filter dialog, which lays out its own window, draws its response with
%   it, so a filter looks the same whichever dialog sets it.
%
%   Frequencies at or below 0 Hz are left out, since a logarithmic axis
%   has no place for them, and a gain below the floor is drawn at the
%   floor: a stopband's exact zeros are -Inf dB and would break the curve.
%   The axis reaches above 0 dB far enough to show any passband ripple.
%
%       TransformOptionsDialog(..., ...
%           {'High-pass (Hz)'; 'Highpass'}, 0.1, ...
%           {'Amplitude response'; 'Response'}, DialogFields.FrequencyResponse( ...
%               @(v) myResponse(v.Highpass, srate)));
%
%   See also DIALOGFIELDS.PLOT, FILTERDIALOG.

    methods
        function this = FrequencyResponse(responseFcn, varargin)
            if ~isa(responseFcn, 'function_handle')
                throw(MException('Alakazam:DialogFields', ...
                    'A frequency response needs a function that computes it, @(values) ...'));
            end
            [style, rest] = takeStyle(varargin);
            this@DialogFields.Plot(@(ax, values) drawFrom(ax, responseFcn, values, style), rest{:});
        end
    end

    methods (Static)
        function draw(ax, f, gain, varargin)
        %DRAW  The response GAIN (linear) at F (Hz) on AX, as described above.
            p = inputParser;
            p.addParameter('Cutoffs', []);
            p.addParameter('Floor', -60);
            p.addParameter('Level', 0.5);
            p.addParameter('Color', [0.29 0.50 0.79]);
            p.parse(varargin{:});
            o = p.Results;

            f = reshape(double(f), 1, []);
            gain = reshape(double(gain), 1, []);
            shown = f > 0;
            f = f(shown);
            gainDb = max(20 * log10(abs(gain(shown))), o.Floor);
            grey = [0.4 0.4 0.4];

            cla(ax);
            semilogx(ax, f, gainDb, 'Color', o.Color, 'LineWidth', 1.2, 'Tag', 'FrequencyResponse');
            hold(ax, 'on');
            yline(ax, 20 * log10(o.Level), ':', 'Color', grey, 'Tag', 'CutoffLevel');
            for cutoff = reshape(double(o.Cutoffs), 1, [])
                if cutoff > 0
                    xline(ax, cutoff, ':', sprintf('%g Hz', cutoff), 'Color', grey, ...
                        'LabelVerticalAlignment', 'bottom', 'FontSize', 8, 'Tag', 'Cutoff');
                end
            end
            hold(ax, 'off');
            xlim(ax, f([1 end]));
            ylim(ax, [o.Floor, max(3, ceil(max(gainDb)) + 1)]);
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, 'Gain (dB)');
        end
    end
end

function drawFrom(ax, responseFcn, values, style)
%DRAWFROM  Ask RESPONSEFCN for the response at the dialog's VALUES and draw it.
    [f, gain, cutoffs] = responseFcn(values);
    DialogFields.FrequencyResponse.draw(ax, f, gain, 'Cutoffs', cutoffs, style{:});
end

function [style, rest] = takeStyle(args)
%TAKESTYLE  Split the drawing's own options from those Plot takes.
    style = {};
    rest = {};
    for k = 1:2:numel(args)
        if any(strcmpi(args{k}, {'Floor', 'Level', 'Color'}))
            style(end + (1:2)) = args(k:k + 1);
        else
            rest(end + (1:2)) = args(k:k + 1);
        end
    end
end
