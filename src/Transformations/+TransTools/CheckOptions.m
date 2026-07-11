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
     % Block until the dialog signals it is done (its OK/Cancel callbacks
     % call uiresume on this same figure -- see e.g. IIRFilterApp.m), the
     % standard App Designer pattern for a modal-style dialog that returns
     % a value, also unblocking automatically if the figure is closed/
     % deleted any other way. Replaces a former custom Finished-property/
     % waitfor protocol, and a former mlapptools-based always-on-top step
     % (GUI apps built for this now set their own WindowStyle instead --
     % see IIRFilterApp.m's createComponents -- both native, undocumented-
     % internals-free replacements). GetMainFigure is the one method every
     % app used this way is expected to implement, alongside GetValues.
     uiwait(Gui.GetMainFigure());
     options = Gui.GetValues();
     delete(Gui);
else
     options = varargin{2};
end

if (iscell(options))
    options = options{:};
end
