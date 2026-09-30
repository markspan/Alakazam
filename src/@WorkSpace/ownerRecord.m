function record = ownerRecord(this)
%OWNERRECORD  Which workspace this is, as recorded on what it produces.
%   RECORD = ownerRecord(THIS) is struct('name', ..., 'raw', ...): the
%   workspace's name and its Raw directory, the latter stored portably (see
%   toStoredPath) so the record still matches when the workspace is opened
%   on another machine with the same layout under the home folder.
%
%   The Raw directory is the identity, as it is for grand averages (see
%   loadGrandAverages): the Cache and Exports folders are routinely shared
%   by several workspaces, but what a workspace analyses is the recordings
%   in its Raw directory. The name is kept for a reader of the record.
%
%   See also LOADREPORTS, ALAKAZAM.PERSISTREPORTNODE.
    record = struct('name', char(string(this.Name)), 'raw', this.toStoredPath(this.RawDirectory));
end
