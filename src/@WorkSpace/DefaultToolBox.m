function DefaultToolBox(this)
%% DEFAULTTOOLBOX
% Creates the default toolbox in the toolbox pane of the databrowser
% part of ALAKAZAM
% m.m.span aug 2021
%% 
% fig = figure( 'Name', 'ToolBox', ...'
%     'NumberTitle', 'off', ...
%     'Toolbar', 'none', ...
%     'MenuBar', 'none', ...
%     'CloseRequestFcn', @nCloseAll );
p = uipanel();
box = uix.HBox( 'Parent', p );
%set (fig,  'Position', [0 0 1 1])
% Add three panels to the box
panel{1} = uix.BoxPanel( 'Title', 'Panel 1', 'Parent', box );
panel{2} = uix.BoxPanel( 'Title', 'Panel 2', 'Parent', box );
panel{3} = uix.BoxPanel( 'Title', 'Panel 3', 'Parent', box );

% Add some contents
uicontrol( 'Style', 'PushButton', 'String', 'Button 1', 'Parent', panel{1} );
uicontrol( 'Style', 'PushButton', 'String', 'Button 2', 'Parent', panel{2} );
box1 = uix.VBox( 'Parent', panel{3} );
box2 = uix.HBox( 'Parent', box1 );
uicontrol( 'Style', 'PushButton', 'String', 'Button 3', 'Parent', box1 );
uicontrol( 'Style', 'PushButton', 'String', 'Button 4', 'Parent', box2 );
uicontrol( 'Style', 'PushButton', 'String', 'Button 5', 'Parent', box2 );

% Set the dock/undock callback
set( panel{1}, 'DockFcn', {@nDock, 1} );
set( panel{2}, 'DockFcn', {@nDock, 2} );
set( panel{3}, 'DockFcn', {@nDock, 3} );
     
this.Panel.add(findjobj(p), 'South')

%-------------------------------------------------------------------------%
    function nDock( eventSource, eventData, whichpanel ) %#ok<INUSL>
        % Set the flag
        panel{whichpanel}.Docked = ~panel{whichpanel}.Docked;
        if panel{whichpanel}.Docked
            % Put it back into the layout
            newfig = get( panel{whichpanel}, 'Parent' );
            set( panel{whichpanel}, 'Parent', box );
            delete( newfig );
        else
            % Take it out of the layout
            pos = getpixelposition( panel{whichpanel} );
            newfig = figure( ...
                'Name', get( panel{whichpanel}, 'Title' ), ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'Toolbar', 'none', ...
                'CloseRequestFcn', {@nDock, whichpanel} );
            figpos = get( newfig, 'Position' );
            set( newfig, 'Position', [figpos(1,1:2), pos(1,3:4)] );
            set( panel{whichpanel}, 'Parent', newfig, ...
                'Units', 'Normalized', ...
                'Position', [0 0 1 1] );
        end
    end % nDock

%-------------------------------------------------------------------------%
    function nCloseAll( ~, ~ )
        % User wished to close the application, so we need to tidy up
        
        % Delete all windows, including undocked ones. We can do this by
        % getting the window for each panel in turn and deleting it.
        for ii=1:numel( panel )
            if isvalid( panel{ii} ) && ~strcmpi( panel{ii}.BeingDeleted, 'on' )
                figh = ancestor( panel{ii}, 'figure' );
                delete( figh );
            end
        end
        
    end % nCloseAll

end % Main function

%     LayOut = javaObjectEDT('java.awt.GridLayout',3,1,10,10);
%     LayOut.setVgap(10);
% 
%     this.ToolBox = javaObjectEDT('javax.swing.JPanel',LayOut);
%         
%     this.ToolBox.add(makeGSlider(@zoomcallback,'Zoom the current plot'));
%     this.ToolBox.add(makeGSlider(@scalecallback,'Scale the current plot'));
%     this.ToolBox.add(makeGSlider(@movecallback,'Move through the signal'));
% 
%     this.Panel.add(this.ToolBoxGroup, 'South')
%     
%     function s = makeGSlider(changeCallback,tts)
%         slider =  uicontrol('style','slider', ...
%                 'Style','slider', ...
%                 'SliderStep',[0.001,.01], ... 
%                 'Min', 0.001, ...
%                 'Max', 100, ...
%                 'TooltipString',tts, ...
%                 'Interruptible','on', ...
%                 'Value', 1, ...
%                 'Callback', changeCallback );
%         
%         s =  findjobj(slider);
%     end
% 
%     function zoomcallback(slider, ~)
%         disp(slider.Value);
%     end
%     function scalecallback(slider, ~)
%        disp(slider.Value);
%     end
%     function movecallback(slider, ~)
%        disp(slider.Value);
%     end
% 


