classdef Text < DialogFields.Field
%TEXT  A one-line text box.
%
%   DialogFields.Text(VALUE, Name, Value). Value: char. Any default passed to
%   TransformOptionsDialog that is not a choice, a tick box or a number
%   becomes one.
%
%   See also DIALOGFIELDS.TEXTAREA, DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Initial char = ''
    end

    properties (Access = private)
        Box
    end

    methods
        function this = Text(value, varargin)
            rest = this.takeCommonOptions(varargin);
            this.refuseOptions(rest);   % no options of its own
            % A list (a numeric vector, a string array) is shown as one line,
            % separated by spaces, rather than as a multi-row char the box
            % cannot hold.
            if isempty(value)
                this.Initial = '';
            else
                parts = string(value);
                this.Initial = char(strjoin(reshape(parts, 1, []), ' '));
            end
        end

        function build(this, parent, onChange)
            this.Box = this.registerControl(uieditfield(parent, 'text', ...
                'Value', this.Initial, 'ValueChangedFcn', @(~, ~) onChange()));
        end

        function v = value(this)
            v = char(this.Box.Value);
        end
    end
end
