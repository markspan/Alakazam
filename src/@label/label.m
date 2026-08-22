classdef label
    %LABEL  A labelled time window (a draggable patch spanning [pos,
    %   pos+dur]) drawn on hAxes -- the fixed-duration-interval counterpart
    %   of the single-instant @cursor class. MCALLBACK/UCALLBACK, if given,
    %   are called while dragging / on release (see buttonmotion/buttonup);
    %   both are optional and every current caller (SignalView.m) passes
    %   them empty, so dragging is currently unused in the live app.
    properties
        VPatch
        MotionCallback
        UpCallback
        PAxes
        PFigure
    end

    methods
        function obj = label( hAxes, pos, dur, lab, col, mcallback, ucallback, varargin)
            %LABEL  Construct an instance of this class.

            obj.MotionCallback = mcallback;
            obj.UpCallback     = ucallback;

            % Derived from the passed-in hAxes, not gcf/gca: those never
            % track a uiaxes, so on a uiaxes-hosted view this would silently
            % resolve to the wrong figure/axes (or none).
            obj.PAxes   = hAxes;
            obj.PFigure = get(get(hAxes, 'Parent'), 'Parent');
            h = ylim(hAxes);

            % lab is a plain label (a char row vector or a scalar string,
            % not a cell -- every current caller passes one directly), so
            % 'Interpreter','none' is what keeps it literal text rather
            % than TeX markup (an underscore etc. would otherwise be
            % interpreted rather than shown).
            if isempty(mcallback) && isempty(ucallback)
                obj.VPatch = patch([pos pos+dur pos+dur pos],[h(1) h(1) h(2) h(2)], col, ...
                    'Parent', hAxes, ...
                    varargin{:} );
                text(pos, h(2) - (.015 * (max(h)-min(h))), lab, ...
                    'Parent', hAxes, 'FontSize', 8, 'Color', col/1.5, 'Interpreter', 'none');
            else
                obj.VPatch = patch([pos pos+dur pos+dur pos],[h(1) h(1) h(2) h(2)], col, ...
                    'ButtonDownFcn', @obj.buttondn, ...
                    'Parent', hAxes, ...
                    varargin{:} );

                text(pos, h(2) + (.015 * (max(h)-min(h))), lab, ...
                    'Parent', hAxes, 'FontSize', 8, 'Color', col/1.5, 'Interpreter', 'none');
            end
        end

        function buttondn(obj, h, events)
        %BUTTONDN  ButtonDownFcn on obj.VPatch: start tracking the mouse.
        %   Wires the figure's own Window*Fcn directly (mirroring @cursor's
        %   buttondn) -- obj.VPatch is already reachable via the OBJ this
        %   callback closes over, so unlike an earlier version of this
        %   method, nothing needs stashing on the figure's UserData first.
            set(obj.PFigure, ...
                'WindowButtonMotionFcn', @obj.buttonmotion, ...
                'WindowButtonUpFcn', @obj.buttonup);
        end

        function buttonup(obj, h, events)
            set(h,'WindowButtonMotionFcn','','WindowButtonUpFcn','')
            if ~isempty(obj.UpCallback)
                feval(obj.UpCallback, obj.VPatch, events)
            end
        end

        function buttonmotion(obj, h, events)
        %BUTTONMOTION  Drag obj.VPatch so its left edge tracks the mouse,
        %   preserving its width (@cursor's own buttonmotion instead sets
        %   its xline's scalar Value directly -- a patch has no such
        %   property, so the equivalent here is moving its XData).
            np = get(obj.PAxes, 'CurrentPoint');
            x = get(obj.VPatch, 'XData');
            width = max(x) - min(x);
            left = np(1);
            set(obj.VPatch, 'XData', [left, left + width, left + width, left]);

            if ~isempty(obj.MotionCallback)
                feval(obj.MotionCallback, obj.VPatch, events)
            end
        end
    end
end
