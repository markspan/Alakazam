classdef TextArea < DialogFields.Field
%TEXTAREA  A block of text over several lines, checked before the dialog
%   closes: a script, a list of statements, a note.
%
%   DialogFields.TextArea(VALUE, Name, Value)
%     VALUE       the text, one char with newlines (or a cellstr of lines)
%     'Validate'  @(text) that throws when the text cannot be used; its
%                 message is shown and the dialog stays open, so a typo is
%                 reported in the dialog rather than after a node exists
%     'Height'    in pixels (default 140)
%     'Monospace' true for code (default true)
%   Value: char, the lines joined with newlines.
%
%   See also DIALOGFIELDS.TEXT, DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Initial char = ''
        Validator = []
        AreaHeight double = 140
        Monospace logical = true
    end

    properties (Access = private)
        Area
    end

    methods
        function this = TextArea(value, varargin)
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('Validate', [], @(f) isempty(f) || isa(f, 'function_handle'));
            p.addParameter('Height', 140);
            p.addParameter('Monospace', true);
            p.parse(rest{:});
            this.Validator = p.Results.Validate;
            this.AreaHeight = p.Results.Height;
            this.Monospace = logical(p.Results.Monospace);
            if iscell(value)
                value = strjoin(cellstr(value), newline);
            end
            this.Initial = char(string(value));
        end

        function h = height(this)
            h = this.AreaHeight;
        end

        function w = width(~)
            w = 560;
        end

        function tf = spansBothColumns(~)
            tf = true;
        end

        function build(this, parent, onChange)
            font = 'Helvetica';
            if this.Monospace
                font = 'Consolas';
            end
            this.Area = this.registerControl(uitextarea(parent, ...
                'Value', strsplit(this.Initial, newline), 'FontName', font, ...
                'ValueChangedFcn', @(~, ~) onChange()));
        end

        function v = value(this)
            v = strjoin(cellstr(this.Area.Value), newline);
        end

        function problem = validate(this)
            problem = '';
            if isempty(this.Validator)
                return;
            end
            try
                this.Validator(this.value());
            catch err
                problem = err.message;
            end
        end
    end
end
