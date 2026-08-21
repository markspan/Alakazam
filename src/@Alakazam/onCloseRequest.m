function onCloseRequest(this)
%ONCLOSEREQUEST  MainFigure's CloseRequestFcn: destroy the app.
%   delete(this) closes MainFigure directly (not via
%   CloseRequestFcn again -- delete() bypasses close callbacks), so
%   this cannot recurse.
    delete(this);
end
