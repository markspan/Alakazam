function save(this,~,~)
%SAVE  Write the current workspace directories to a .wksp file (JSON).
%   Prompts for a save location, then writes RawDirectory/CacheDirectory/
%   ExportsDirectory as a plain JSON object -- portable paths (toStoredPath)
%   so a workspace saved on one machine opens on another -- plus every
%   transformation's remembered options for this workspace (see
%   TransformSettings), so re-opening this .wksp file later restores them
%   too. Cancelling the dialog (Name == 0) is a no-op.
    [this.Name, Path] = uiextras.uiputfile2('*.wksp');
    if isequal(this.Name, 0)
        return; % cancelled
    end

    workspace = struct( ...
        'RawDirectory',     this.toStoredPath(this.RawDirectory), ...
        'CacheDirectory',   this.toStoredPath(this.CacheDirectory), ...
        'ExportsDirectory', this.toStoredPath(this.ExportsDirectory), ...
        'TransformSettings', TransformSettings.allValues());

    fid = fopen(fullfile(Path, this.Name), 'w');
    fprintf(fid, '%s', jsonencode(workspace, 'PrettyPrint', true));
    fclose(fid);
end
