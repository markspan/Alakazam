function load(this,~,~)
    [this.Name, Path] = Tools.uigetfile2('*.wksp');
    if (this.Name == 0) %% Cancel
        return; 
    end
    
    load(fullfile(Path, this.Name), '-mat', 'RawDirectory', 'CacheDirectory', 'ExportsDirectory');
    
    this.RawDirectory = strrep(strrep(RawDirectory, '\', '/'), '/', filesep);
    this.CacheDirectory = strrep(strrep(CacheDirectory, '\', '/'), '/', filesep);
    this.ExportsDirectory = strrep(strrep(ExportsDirectory, '\', '/'), '/', filesep);
    
    this.open();
end
