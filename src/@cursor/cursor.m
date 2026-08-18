classdef cursor
    %CURSOR  A moveable vertical line (a single instant/event) drawn on
    %   hAxes -- the single-instant counterpart of the fixed-duration
    %   @label class. MCALLBACK/UCALLBACK, if given, are called while
    %   dragging / on release (see buttonmotion/buttonup).
    properties
        VLine
        MotionCallback
        UpCallback
        PAxes
        PFigure
        ID
    end

    methods
        function obj = cursor( hAxes, pos, mcallback, ucallback, varargin)
            %CURSOR  Construct an instance of this class
            obj.MotionCallback = mcallback;
            obj.UpCallback     = ucallback;
            obj.PAxes   = hAxes;
            obj.PFigure = get(get(hAxes, 'Parent'), 'Parent');
            for v = 1:length(varargin)
                if strcmp(varargin{v}, "ID")
                    obj.ID = varargin{v+1};
                    varargin(v) = [];
                    varargin(v) = [];
                    break;
                end
            end

            if isempty(mcallback) && isempty(ucallback)
                obj.VLine = xline(pos,  ...
                    'Parent', hAxes, ...
                    varargin{:} );
            else
                obj.VLine = xline(pos,  ...
                    'ButtonDownFcn', @obj.buttondn, ...
                    'Parent', hAxes, ...
                    varargin{:} );
            end
        end

        function buttondn(obj, h, events)
            set(obj.PFigure,...
                'WindowButtonMotionFcn',@obj.buttonmotion,...
                'WindowButtonUpFcn',@obj.buttonup);
        end


        function buttonup(obj, h, events)
            set(h,'WindowButtonMotionFcn','','WindowButtonUpFcn','')
            if ~isempty(obj.UpCallback)
                feval(obj.UpCallback, obj.VLine, events)
            end
        end

        function buttonmotion(obj, h, events)
            % Uses the stored axes (obj.PAxes), not gca: gca never tracks a
            % uiaxes, so this would silently target the wrong axes (or none)
            % once the axes this cursor lives on became a uiaxes.
            np = get (obj.PAxes, 'CurrentPoint');
            set(obj.VLine,'Value',np(1));
            drawnow;
            if ~isempty(obj.MotionCallback)
                feval(obj.MotionCallback,obj.VLine, events)
            end
        end
    end
end
