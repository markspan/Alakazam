function load(this,~,~)
    [this.Name, Path] = uigetfile2('*.wksp');
    if (this.Name == 0) %% Cancel
        return; 
    end
    
    load(fullfile(Path, this.Name), '-mat', 'RawDirectory', 'CacheDirectory', 'ExportsDirectory');

    % Expand any home-relative ("~/...") directories to absolute paths for this
    % machine; absolute paths (other drives, network mounts) pass through.
    this.RawDirectory     = this.fromStoredPath(RawDirectory);
    this.CacheDirectory   = this.fromStoredPath(CacheDirectory);
    this.ExportsDirectory = this.fromStoredPath(ExportsDirectory);
    
    this.open();
end
