function tn = registerRootNode(this, id, matfilename, kind)
%REGISTERROOTNODE  Add the just-loaded this.EEG to the tree as a root
%   (raw import) node, and recurse into any previously-computed children
%   cached alongside it. KIND is Tree.addNode's own node-kind string --
%   'raw' for a continuous recording (the person-badge icon), 'time' for
%   an already-averaged erpset (the same badge a per-subject Average
%   result gets -- see loadERPFile).
%
%   Previously duplicated identically (module the KIND literal) at the
%   end of loadBVAFile.m, loadSETFile.m, loadMATFile.m and loadERPFile.m.
    opts = WorkSpaceTree.optsFor(this.EEG);
    opts.isRoot = true;
    tn = this.Tree.addNode(id, '', kind, matfilename, opts);
    this.treeTraverse(id, this.CacheDirectory, tn);
end
