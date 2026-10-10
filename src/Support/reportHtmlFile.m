function file = reportHtmlFile(EEG)
%REPORTHTMLFILE  Where a report node's rendered page is now.
%
%   FILE = REPORTHTMLFILE(EEG) is EEG.ReportHtmlFile when that file exists.
%   Otherwise it is the file of that name beside the node itself (EEG.File,
%   where loadNodeEEG says it was read from), which is where the report was
%   written (persistReportNode puts the node beside its page), when that
%   exists; otherwise EEG.ReportHtmlFile as recorded.
%
%   The node records its page by its full path, so a report whose Exports
%   folder was moved (to another disk, say) opened on a page that was no
%   longer there.
%
%   See also REPORTVIEW, ALAKAZAM.PERSISTREPORTNODE.
    file = '';
    if isfield(EEG, 'ReportHtmlFile')
        file = char(EEG.ReportHtmlFile);
    end
    if isempty(file) || isfile(file) || ~isfield(EEG, 'File') || isempty(EEG.File)
        return;
    end
    [~, name, ext] = fileparts(strrep(file, '\', '/'));
    beside = fullfile(fileparts(char(EEG.File)), [name ext]);
    if isfile(beside)
        file = beside;
    end
end
