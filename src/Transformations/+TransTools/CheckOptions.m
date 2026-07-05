function options = CheckOptions(GuiCommand, SourceTransform, varargin)

if (nargin == 0)
    SourceTransform= 'Alakazam::Unknown';
end

if (nargin < 2)
    ME = MException(SourceTransform,'Problem: No Data Supplied');
    throw(ME);
end

if (nargin == 3)
     eval(['Gui = ' GuiCommand])
     win  = Gui.GetGuiWinToMakeModal();
     win.setAlwaysOnTop(true);
     waitfor(Gui, 'Finished');
     options = Gui.GetValues();
     delete(Gui);
else
     options = varargin{2};
end

if (iscell(options))
    options = options{:};
end
