classdef label
    % cursor: an moveable verical area (period)
    properties
        vpatch
        motionCallback
        upCallback
        pfigure
    end
    
    methods
        function obj = label( hAxes, pos, dur, lab, col, mcallback, ucallback, varargin)
            % cursor Construct an instance of this class
            
            obj.motionCallback  = mcallback;    
            obj.upCallback      = ucallback;
            
            obj.pfigure = gcf;
            h = ylim(gca);
            
            if isempty(mcallback) && isempty(ucallback)
                obj.vpatch = patch([pos pos+dur pos+dur pos],[h(1) h(1) h(2) h(2)], col, ...
                    'Parent', hAxes, ...
                    varargin{:} );
                text(pos, h(2) - (.015 * (max(h)-min(h))), lab{1}, 'FontSize', 8, 'Color', col/1.5);
            else
                obj.vpatch = patch([pos pos+dur pos+dur pos],[h(1) h(1) h(2) h(2)], col, ...
                    'ButtonDownFcn', @obj.buttondn, ...
                    'Parent', hAxes, ...
                    varargin{:} );
                
                    text(pos, h(2) + (.015 * (max(h)-min(h))), lab{1}, 'FontSize', 8, 'Color', col/1.5);
            end
        end
        
        function buttondn(obj, h, events)
            ud = get(obj.pfigure,'UserData');            
            
            ud.varea = h;
            ud.downEvents = events;
            
            set(obj.pfigure,'UserData', ud, ...
                'WindowButtonMotionFcn',@obj.buttonmotion,...
                'WindowButtonUpFcn',@obj.buttonup);         
        end
        
        
        function buttonup(obj, h, events)             
            set(h,'WindowButtonMotionFcn','','WindowButtonUpFcn','')
            ud = get(h,'UserData');
            
            if ~isempty(obj.upCallback)
                feval(obj.upCallback, ud.varea, events)
            end
        end
        
        function buttonmotion(obj, h, events)
            ud = get(h,'UserData');
            np = get (gca, 'CurrentPoint');
            
            set(ud.varea,'Value',np(1));
            
            if ~isempty(obj.motionCallback)
                feval(obj.motionCallback, ud.vline, events)
            end
        end
    end
end
