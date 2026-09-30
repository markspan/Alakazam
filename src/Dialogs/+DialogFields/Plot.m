classdef Plot < DialogFields.Field
%PLOT  A preview drawn from the dialog's current values, redrawn whenever
%   any field changes. It contributes nothing to the options.
%
%   DialogFields.Plot(DRAWFCN, Name, Value)
%     DRAWFCN  @(ax, values): draw into the uiaxes AX, where VALUES is a
%              struct of every field's current value by name. The axes is
%              cleared before each call.
%     'Height' in pixels (default 170)
%
%   A drawing that fails does not close the dialog or lose what was typed:
%   the axes shows the error instead, since a preview is advice, and the
%   values it could not draw may still be the ones wanted.
%
%       TransformOptionsDialog(..., ...
%           {'Start'; 'Start'}, -200, {'Stop'; 'Stop'}, 0, ...
%           {'Window'; 'Preview'}, DialogFields.Plot(@(ax, v) drawWindow(ax, v)));
%
%   See also DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Draw
        PlotHeight double = 170
    end

    properties (SetAccess = private)
        Axes   % the uiaxes, once built (visible to tests)
    end

    methods
        function this = Plot(drawFcn, varargin)
            if ~isa(drawFcn, 'function_handle')
                throw(MException('Alakazam:DialogFields', ...
                    'A plot needs a function that draws it, @(ax, values) ...'));
            end
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('Height', 170);
            p.parse(rest{:});
            this.Draw = drawFcn;
            this.PlotHeight = p.Results.Height;
        end

        function h = height(this)
            h = this.PlotHeight;
        end

        function w = width(~)
            w = 520;
        end

        function tf = spansBothColumns(~)
            tf = true;
        end

        function tf = hasValue(~)
            tf = false;
        end

        function build(this, parent, ~)
            this.Axes = uiaxes(parent);
            this.Axes.Toolbar.Visible = 'off';
            disableDefaultInteractivity(this.Axes);
        end

        function v = value(~)
            v = [];
        end

        function refresh(this, values)
            if isempty(this.Axes) || ~isvalid(this.Axes)
                return;
            end
            cla(this.Axes);
            title(this.Axes, '');
            try
                this.Draw(this.Axes, values);
            catch err
                cla(this.Axes);
                title(this.Axes, err.message, 'FontWeight', 'normal', 'FontSize', 9, ...
                    'Interpreter', 'none');
            end
        end
    end
end
