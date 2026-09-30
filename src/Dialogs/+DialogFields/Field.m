classdef (Abstract) Field < handle
%FIELD  One field of a generated dialog (TransformOptionsDialog): how it is
%   drawn, how much room it takes, and the value it hands back.
%
%   WHY FIELDS ARE OBJECTS. TransformOptionsDialog infers a field's kind from
%   its default value (a cellstr is a drop-down, a logical a checkbox, a
%   number a numeric box), which is what lets a transformation get a dialog
%   for nothing. It also capped what a generated dialog could hold: a channel
%   picker, a table of rows, a preview plot or a field that depends on
%   another could not be inferred from a value, so every transformation that
%   needed one wrote a dialog of its own. A field that is an object says what
%   it is, so the generated dialog can hold any of them, and a new kind is a
%   class in this package rather than a change to the dialog.
%
%   Every field accepts two options besides its own:
%     'EnabledWhen'  @(values) -> logical, where VALUES is a struct of every
%                    field's current value by name. Evaluated whenever any
%                    field changes; the field is greyed out while it is
%                    false. Its value is still returned, so the options
%                    struct keeps one shape whatever was enabled.
%     'Tooltip'      text shown when hovering over the field's controls.
%
%   A subclass implements BUILD (create its controls in a container and
%   call ONCHANGE when the user edits them) and VALUE (what goes into the
%   options struct), and may override HEIGHT, WIDTH, SPANSBOTHCOLUMNS,
%   HASVALUE, VALIDATE and REFRESH.
%
%   See also TRANSFORMOPTIONSDIALOG, DIALOGFIELDS.FROMDEFAULT.

    properties
        EnabledWhen = []   % [] or @(values) -> logical
        Tooltip = ''
    end

    properties (SetAccess = protected)
        Controls = {}      % every control this field created, for enabling
    end

    methods (Abstract)
        build(this, parent, onChange)
        %BUILD  Create the field's controls inside PARENT (a grid layout
        %   cell) and call ONCHANGE() whenever the user edits them.

        v = value(this)
        %VALUE  The field's current value, as it goes into the options.
    end

    methods
        function h = height(~)
        %HEIGHT  The pixel height of the field's row.
            h = 28;
        end

        function w = width(~)
        %WIDTH  The dialog width, in pixels, the field needs to be usable.
            w = 420;
        end

        function tf = spansBothColumns(~)
        %SPANSBOTHCOLUMNS  True for a field too wide for the value column (a
        %   table, a plot): it takes the whole row, under its label.
            tf = false;
        end

        function tf = hasValue(~)
        %HASVALUE  False for a field that only shows something (a plot).
            tf = true;
        end

        function problem = validate(~)
        %VALIDATE  '' when the value can be used; otherwise a sentence
        %   saying what is wrong, which the dialog shows instead of closing.
            problem = '';
        end

        function refresh(~, ~)
        %REFRESH  React to the dialog's current VALUES (a plot redraws).
        end

        function setEnabled(this, tf)
        %SETENABLED  Grey the field's controls out, or back in.
            state = matlab.lang.OnOffSwitchState(logical(tf));
            for k = 1:numel(this.Controls)
                c = this.Controls{k};
                if isvalid(c) && isprop(c, 'Enable')
                    c.Enable = state;
                end
            end
        end
    end

    methods (Access = protected)
        function rest = takeCommonOptions(this, args)
        %TAKECOMMONOPTIONS  Consume 'EnabledWhen' and 'Tooltip' from a
        %   constructor's name-value pairs and return the rest, for the
        %   subclass's own inputParser.
            rest = {};
            if mod(numel(args), 2) ~= 0
                throw(MException('Alakazam:DialogFields', ...
                    'Options come in name-value pairs; one of them is missing its value.'));
            end
            for k = 1:2:numel(args)
                name = char(string(args{k}));
                switch lower(name)
                    case 'enabledwhen'
                        if ~isempty(args{k + 1}) && ~isa(args{k + 1}, 'function_handle')
                            throw(MException('Alakazam:DialogFields', ...
                                'EnabledWhen takes a function of the dialog''s values, @(values) ...'));
                        end
                        this.EnabledWhen = args{k + 1};
                    case 'tooltip'
                        this.Tooltip = char(string(args{k + 1}));
                    otherwise
                        rest(end + 1:end + 2) = {name, args{k + 1}}; %#ok<AGROW>
                end
            end
        end

        function refuseOptions(~, rest)
        %REFUSEOPTIONS  For a field with no options of its own: anything
        %   left after the common ones is a mistake worth naming.
            if ~isempty(rest)
                throw(MException('Alakazam:DialogFields', ...
                    'This field has no option called "%s".', rest{1}));
            end
        end

        function c = registerControl(this, c)
        %REGISTERCONTROL  Remember a control for enabling, and give it the
        %   field's tooltip where it takes one.
            this.Controls{end + 1} = c;
            if ~isempty(this.Tooltip) && isprop(c, 'Tooltip')
                c.Tooltip = this.Tooltip;
            end
        end
    end
end
