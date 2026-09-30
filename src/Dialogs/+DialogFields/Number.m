classdef Number < DialogFields.Field
%NUMBER  A numeric box.
%
%   DialogFields.Number(VALUE, Name, Value) with
%     'Limits'   [low high], inclusive; the box refuses anything outside
%                (default [-Inf Inf])
%     'Integer'  true to round what is typed to a whole number
%   Value: double. A scalar numeric default passed to TransformOptionsDialog
%   becomes a Number without limits.
%
%   See also DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Initial double
        Limits double = [-Inf Inf]
        Integer logical = false
    end

    properties (Access = private)
        Box
    end

    methods
        function this = Number(value, varargin)
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('Limits', [-Inf Inf], @(x) isnumeric(x) && numel(x) == 2 && x(1) <= x(2));
            p.addParameter('Integer', false);
            p.parse(rest{:});
            this.Limits = double(p.Results.Limits(:)).';
            this.Integer = logical(p.Results.Integer);
            this.Initial = double(value);
            if this.Initial < this.Limits(1) || this.Initial > this.Limits(2)
                this.Initial = min(max(this.Initial, this.Limits(1)), this.Limits(2));
            end
        end

        function build(this, parent, onChange)
            rounding = matlab.lang.OnOffSwitchState(this.Integer);
            this.Box = this.registerControl(uieditfield(parent, 'numeric', ...
                'Value', this.Initial, 'Limits', this.Limits, ...
                'RoundFractionalValues', rounding, 'ValueChangedFcn', @(~, ~) onChange()));
        end

        function v = value(this)
            v = double(this.Box.Value);
        end
    end
end
