function save(this,~,~)
    [this.Name,Path] = uiextras.uiputfile2('*.wksp');

    % Store directories portably: those inside the user's home become "~/..."
    % so the workspace opens on another machine; others stay absolute.
    RawDirectory     = this.toStoredPath(this.RawDirectory);
    CacheDirectory   = this.toStoredPath(this.CacheDirectory);
    ExportsDirectory = this.toStoredPath(this.ExportsDirectory);
    save(fullfile(Path, this.Name),'RawDirectory', 'CacheDirectory', 'ExportsDirectory');
end