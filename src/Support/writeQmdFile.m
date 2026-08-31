function writeQmdFile(qmdFile, qmdText, errorId)
%WRITEQMDFILE  Write a generated Quarto document to disk, and close it.
%   writeQmdFile(QMDFILE, QMDTEXT, ERRORID) writes QMDTEXT to QMDFILE,
%   throwing ERRORID if the file cannot be opened. ERRORID names the calling
%   report action, so the message says which one failed.
%
%   CLOSED BEFORE RETURNING, not merely scheduled for closing: every caller
%   hands the same path straight to renderQuartoReport, which reads it back.
%   A file still held open by MATLAB is the kind of thing that works on one
%   platform and fails on another, so the close is not left to whenever the
%   caller's own cleanup happens to run.
%
%   Four report actions wrote these same ten lines
%   (onExportMeasurements/Spectral/DataQuality, onClusterStats).
%   The generation-before-opening order they all share matters and is kept:
%   opening the file first would truncate it, so a generator that then threw
%   would leave an empty, unexplained .qmd behind.
%
%   See also RENDERQUARTOREPORT, GENERATEQUARTOREPORT.
    fid = fopen(qmdFile, 'w');
    if fid < 0
        throw(MException(errorId, 'I couldn''t open "%s" for writing.', qmdFile));
    end
    closeFile = onCleanup(@() fclose(fid));
    fwrite(fid, qmdText, 'char');
    clear closeFile;   % close now: the caller reads this file back next
end
