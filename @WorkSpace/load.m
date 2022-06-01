function load(this,~,~)
    [this.Name, Path] = Tools.uigetfile2('*.wksp');
    if (this.Name == 0) %% Cancel
        return; 
    end
    
    load(fullfile(Path, this.Name), '-mat', 'RawDirectory', 'CacheDirectory', 'ExportsDirectory');
    
    this.RawDirectory = RawDirectory;
    this.CacheDirectory = CacheDirectory;
    this.ExportsDirectory = ExportsDirectory;
    
    this.open();
end
