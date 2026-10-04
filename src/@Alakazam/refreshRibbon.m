function refreshRibbon(this)
%REFRESHRIBBON  Rebuild the ribbon's buttons from the transformations and
%   plugins installed now, after a plugin was installed or removed.
    if ~isempty(this.Ribbon) && isvalid(this.Ribbon)
        this.Ribbon.refresh(Plugins.roots(fullfile(this.RootDir, "Transformations")));
    end
end
