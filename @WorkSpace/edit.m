function edit(this,~,~)
%% 
    uigeom = {[.5 1] [.5 1] [.5 1]};
    uilist = { ...
        { 'style' 'text' 'string' 'Raw Data Folder:'} ...
        { 'style' 'edit' 'string' this.RawDirectory} ...
        { 'style' 'text' 'string' 'Intermediate Folder:'} ...
        { 'style' 'edit' 'string' this.CacheDirectory} ...
        { 'style' 'text' 'string' 'Exports Folder:'} ...
        { 'style' 'edit' 'string' this.ExportsDirectory} ...
    };
    result = uiextras.inputgui(uigeom, uilist, 'pophelp(''edit Workspace'')', 'Load a Workspace Definition');
    if isempty(result), return, end
    this.RawDirectory = result{1};
    if  this.RawDirectory(end) ~= '\'
        this.RawDirectory = strcat(this.RawDirectory, '\');
    end
    this.CacheDirectory = result{2};
    if  this.CacheDirectory(end) ~= '\'
        this.CacheDirectory = strcat(this.CacheDirectory, '\');
    end
    this.ExportsDirectory = result{3};
    if  this.ExportsDirectory(end) ~= '\'
        this.ExportsDirectory = strcat(this.ExportsDirectory, '\');
    end
    this.open();
%% 
end