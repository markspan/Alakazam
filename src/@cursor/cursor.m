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
        ID
    end

    methods
        function obj = cursor( hAxes, pos, mcallback, ucallback, varargin)
            %CURSOR  Construct an instance of this class
            obj.MotionCallback = mcallback;
            obj.UpCallback     = ucallback;
            obj.PAxes   = hAxes;
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
        %   THE FIGURE IS RESOLVED HERE, NOT CACHED, and not by walking a
        %   fixed number of levels. This used to be
        %   get(get(hAxes, 'Parent'), 'Parent') taken in the constructor,
        %   which assumed the axes sat one container below the figure. In
        %   this app it sits in a uigridlayout inside a uitab, so that
        %   expression returned the uitab, and setting a Window*Fcn on a
        %   uitab errors: "Unrecognized property WindowButtonMotionFcn for
        %   class Tab". Nothing had noticed because every caller passes no
        %   motion or release callback, so this method is never wired up
        %   (see SignalView.drawPointEvents and drawAreaEvents).
        %
        %   Caching would be wrong even at the right depth now that a plot
        %   can be moved into a window of its own (see undockTab): the
        %   figure an axes belongs to is not fixed for the life of the
        %   object, so it is asked for at the moment of the drag.
            set(ancestor(obj.PAxes, 'figure'),...
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
