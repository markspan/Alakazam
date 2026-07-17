function onSettingsChanged(this)
%ONSETTINGSCHANGED  Re-draw open views so changed settings take effect.
    for k = 1:numel(this.PlotsTabGroup.Children)
        tab = this.PlotsTabGroup.Children(k);
        if ~isgraphics(tab) || ~isvalid(tab)
            continue;
        end
        for viewName = ["AverageView", "EpochView"]
            view = getappdata(tab, char(viewName));
            if ~isempty(view) && isvalid(view)
                try
                    view.redraw();
                catch err
                    warning('Alakazam:viewRefresh', ...
                        'Could not refresh %s: %s', char(viewName), err.message);
                end
            end
        end
    end
end
