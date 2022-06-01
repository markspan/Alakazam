classdef cursor
    % cursor: an moveable verical line (event)
    properties
        vline
        motionCallback
        upCallback
        pAxes
        pFigure
    end
    
    methods
        function obj = cursor( hAxes, pos, mcallback, ucallback, varargin)
            % cursor Construct an instance of this class
            obj.motionCallback  = mcallback;    
            obj.upCallback      = ucallback;
            obj.pAxes = hAxes;
            obj.pFigure = get(get(hAxes, 'Parent'), 'Parent');
            if isempty(mcallback) && isempty(ucallback)
                obj.vline = xline(pos,  ...
                    'Parent', hAxes, ...
                    varargin{:} );
            else
                obj.vline = xline(pos,  ...
                    'ButtonDownFcn', @obj.buttondn, ...
                    'Parent', hAxes, ...
                    varargin{:} );
            end
        end
        
        function buttondn(obj, h, events)
            ud = get(obj.pFigure,'UserData');            
            
            ud.vline = h;
            ud.downEvents = events;
            
            set(obj.pFigure,'UserData', ud, ...
                'WindowButtonMotionFcn',@obj.buttonmotion,...
                'WindowButtonUpFcn',@obj.buttonup);         
        end
        
        
        function buttonup(obj, h, events)             
            set(h,'WindowButtonMotionFcn','','WindowButtonUpFcn','')
            ud = get(h,'UserData');
            
            if ~isempty(obj.upCallback)
                feval(obj.upCallback, ud.vline, events)
            end
        end
        
        function buttonmotion(obj, h, events)
            ud = get(h,'UserData');
            np = get (gca, 'CurrentPoint');
            
            set(ud.vline,'Value',np(1));
            
            if ~isempty(obj.motionCallback)
                feval(obj.motionCallback, ud.vline, events)
            end
        end
    end
end
