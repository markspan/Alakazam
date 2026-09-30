function discardResultNode(this, node, parentNode, inputEEG)
%DISCARDRESULTNODE  Take a just-added result node out again, as if the step
%   that made it had never run.
%
%   discardResultNode(THIS, NODE, PARENTNODE, INPUTEEG) deletes NODE's
%   cache file and sidecars (and anything under it, of which a new node has
%   nothing), closes any tab that was opened for it, removes it from the
%   tree, selects PARENTNODE again and makes INPUTEEG, the dataset the step
%   was given, the current one. The parent's own plot is brought back if it
%   can be; if even that fails, the tree is still consistent, which is what
%   matters.
%
%   WHY A STEP IS UNDONE WHEN ITS RESULT CANNOT BE SHOWN. onTransformation
%   saves the node before drawing it. When the drawing failed, the node
%   stayed: selecting it showed nothing, or its parent's plot, and it looked
%   like an unchanged copy of its parent sitting in the tree after an error
%   dialog that said the step had not run. A step now completes (computed,
%   saved and shown) or leaves no trace, and the dialog says which.
%
%   See also ONTRANSFORMATION, PERSISTRESULTNODE, DELETEBRANCHFILES.
    tree = this.Workspace.ActiveTree;
    try
        this.deleteBranchFiles(char(string(node.UserData)));
    catch
        % A file that was never written has nothing to delete.
    end
    tree.removeNode(node.Id);
    if ~isempty(parentNode)
        tree.SelectedNodes = parentNode;
    end
    this.Workspace.EEG = inputEEG;
    try
        this.Plotter.plotCurrent();
    catch
        % The parent's plot is a courtesy; the dialog that follows matters more.
    end
end
