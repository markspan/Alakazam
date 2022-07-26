classdef cursor
    % cursor: an moveable verical line (event)
    properties
        vline
        motionCallback
        upCallback
        pAxes
        pFigure
        ID
    end
    
    methods
        function obj = cursor( hAxes, pos, mcallback, ucallback, varargin)
            % cursor Construct an instance of this class
            obj.motionCallback  = mcallback;    
            obj.upCallback      = ucallback;
            obj.pAxes = hAxes;
            obj.pFigure = get(get(hAxes, 'Parent'), 'Parent');
            for v = 1:length(varargin)
                if strcmp(varargin{v}, "ID")
                    obj.ID = varargin{v+1};            
                    varargin(v) = [];
                    varargin(v) = [];
                    break;
                end
            end

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
            set(obj.pFigure,...
                'WindowButtonMotionFcn',@obj.buttonmotion,...
                'WindowButtonUpFcn',@obj.buttonup);         
        end
        
        
        function buttonup(obj, h, events)             
            set(h,'WindowButtonMotionFcn','','WindowButtonUpFcn','')
            if ~isempty(obj.upCallback)
                feval(obj.upCallback, obj.vline, events)
            end
        end
        
        function buttonmotion(obj, h, events)
            np = get (gca, 'CurrentPoint');
            set(obj.vline,'Value',np(1));
            drawnow;
            if ~isempty(obj.motionCallback)
                feval(obj.motionCallback,obj.vline, events)
            end
        end
    end
end
