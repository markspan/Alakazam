function dir_ = reportsDirectory(this)
%REPORTSDIRECTORY  ExportsDirectory/Reports -- the fixed folder every
%   rendered Quarto report's .qmd/.html/_node.mat is written into (see
%   Alakazam.persistReportNode) and where WorkSpace.loadReports scans to
%   repopulate ReportsTree when the workspace reopens.
%
%   A fixed subfolder of ExportsDirectory, not a separate configurable
%   workspace directory (no new Edit WorkSpace field, no .wksp schema
%   change) -- same "fixed subfolder, scan and re-add" pattern
%   CacheDirectory/GrandAverages already uses for WorkSpace.
%   GrandAveragesTree (see loadGrandAverages/Alakazam.saveGrandAverage).
%   Anchored under ExportsDirectory rather than CacheDirectory
%   specifically so a rendered report -- a final, often slow-to-regenerate
%   analyst output, not a recomputable intermediate -- survives
%   WorkSpace.rawclear's "Clear cache" (an rmdir 's' of CacheDirectory
%   alone).
    dir_ = fullfile(this.ExportsDirectory, 'Reports');
end
