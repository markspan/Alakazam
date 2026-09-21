function file = resultCacheFile(parentFile, transformId)
%RESULTCACHEFILE  Where a transformation's result on PARENTFILE is cached.
%   FILE = resultCacheFile(PARENTFILE, TRANSFORMID) is a new .mat path in the
%   folder named after PARENTFILE's own stem (created if needed), called
%   TRANSFORMID followed by a DDhhMMss time stamp, e.g. "Fourier051423.mat".
%
%   The folder MUST be named after the parent's stem: the tree is rebuilt
%   from disk (WorkSpace.treeTraverse), and a branch replayed
%   (evaluateDroppedBranch, replayBranch), by re-deriving that folder name
%   from a node's own file path rather than storing it anywhere. The stamp
%   format is kept for existing cache trees; the tree takes a node's label
%   from its sidecar, not from the file name.
%
%   A file already of that name (the same transformation run twice on one
%   parent within a second, as a replayed branch with two such siblings can)
%   gets a numbered suffix instead of being overwritten.
%
%   One definition, shared by persistResultNode (a result made in the app)
%   and replayBranch (a result made on a parallel worker), so the two cannot
%   drift apart in where they put things.
%
%   See also PERSISTRESULTNODE, REPLAYBRANCH.
    [parentDir, parentName] = fileparts(parentFile);
    childDir = fullfile(parentDir, parentName);
    if ~exist(childDir, 'dir')
        mkdir(childDir);
    end
    stem = [char(transformId) datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>
    file = fullfile(childDir, [stem '.mat']);
    k = 1;
    while exist(file, 'file') == 2
        file = fullfile(childDir, sprintf('%s_%d.mat', stem, k));
        k = k + 1;
    end
end
