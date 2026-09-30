classdef Checkbox < DialogFields.Field
%CHECKBOX  A tick box.
%
%   DialogFields.Checkbox(TF, Name, Value). Value: logical. A scalar logical
%   default passed to TransformOptionsDialog becomes one.
%
%   See also DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Initial logical
    end

    properties (Access = private)
        Box
    end

    methods
        function this = Checkbox(tf, varargin)
            rest = this.takeCommonOptions(varargin);
            this.refuseOptions(rest);   % no options of its own
            this.Initial = logical(tf);
        end

        function build(this, parent, onChange)
            this.Box = this.registerControl(uicheckbox(parent, 'Text', '', ...
                'Value', this.Initial, 'ValueChangedFcn', @(~, ~) onChange()));
        end

        function v = value(this)
            v = logical(this.Box.Value);
        end
    end
end
