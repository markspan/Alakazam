function DefaultToolBox(this)
%% DEFAULTTOOLBOX
% Creates the default toolbox in the toolbox pane of the databrowser
% part of ALAKAZAM
% m.m.span aug 2021
%% 
    LayOut = javaObjectEDT('java.awt.GridLayout',3,1,10,10);
    LayOut.setVgap(10);

    this.ToolBox = javaObjectEDT('javax.swing.JPanel',LayOut);        
    this.ToolBox.add(makeGSlider(@zoomcallback,'Zoom the current plot'));
    this.ToolBox.add(makeGSlider(@scalecallback,'Scale the current plot'));
    this.ToolBox.add(makeGSlider(@movecallback,'Move through the signal'));

    this.Panel.add(this.ToolBox, 'South')
    
    function s = makeGSlider(changeCallback,tts)
        slider =  uicontrol('style','slider', ...
                'Style','slider', ...
                'SliderStep',[0.001,.01], ... 
                'Min', 0.001, ...
                'Max', 100, ...
                'TooltipString',tts, ...
                'Interruptible','on', ...
                'Value', 1, ...
                'Callback', changeCallback );
        
        s =  findjobj(slider);
    end

    function zoomcallback(slider, ~)
        disp(slider.Value);
    end
    function scalecallback(slider, ~)
       disp(slider.Value);
    end
    function movecallback(slider, ~)
       disp(slider.Value);
    end

end

