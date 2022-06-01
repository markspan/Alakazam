function save(this,~,~)
    [this.Name,Path] = uiextras.uiputfile2('*.wksp');
    RawDirectory = this.RawDirectory;
    CacheDirectory = this.CacheDirectory;
    ExportsDirectory = this.ExportsDirectory;
    save(fullfile(Path, this.Name),'RawDirectory', 'CacheDirectory', 'ExportsDirectory');
end