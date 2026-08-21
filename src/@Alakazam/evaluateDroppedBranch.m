function evaluateDroppedBranch(this, sourceFile, targetNode)
%EVALUATEDROPPEDBRANCH  Re-apply a dragged branch onto a target dataset.
%   EVALUATEDROPPEDBRANCH(THIS, SOURCEFILE, TARGETNODE) applies SOURCEFILE's
%   own step onto the dataset at TARGETNODE, then recurses into EVERY child
%   of SOURCEFILE (not just the first): a branch can genuinely fork, e.g. an
%   Average -> Measure chain alongside a sibling SpectralMeasure run
%   directly on the same epoched (ArtefactDetect) parent, since
%   SpectralMeasure needs single-trial data and so cannot descend from an
%   Average the way Measure does. Both then live as sibling children in the
%   SAME child folder (see persistResultNode's own "child folder MUST be
%   named after the source's own stem" note) -- so replaying past that
%   point needs to walk into BOTH, not assume exactly one, the way a plain
%   linear while-loop over "the" next child previously did (that version
%   picked up every *.mat sibling as a single comma-separated-list argument
%   to fullfile(), silently building one nonsense concatenated path instead
%   of visiting each child in turn -- which is what actually broke Apply to
%   All Raw Files for any branch ending in both an ERP Measure and a
%   Spectral Measure). Mirrors collectBranchTree's own recursive, fork-
%   aware walk (used by Save Template), just applying each step immediately
%   instead of collecting it into a flat list.
%
%   Special case: dropping one AVERAGED dataset onto a matching AVERAGED
%   dataset overlays their plots instead of transforming -- isOverlayableAverage's
%   own job to recognise (see its header comment for why that is a source-side
%   .Call check, not a step-position one: it needs to reject Measure et al
%   reached either as the user's own direct drop or by descending into a
%   branch's children). An overlay is terminal for this path (there is no
%   new persisted node to attach further descendants to), matching the
%   original single-chain version's own behaviour.
    targetFile = targetNode.UserData;

    % Both files are stored tree-node paths, not something just derived
    % from code on disk -- a node can outlive its file (cache cleared by
    % hand, a workspace copied from another machine, a branch deleted
    % outside the app), so this is checked explicitly rather than letting
    % load() throw a raw "Unable to find file" straight through
    % onNodeDropped's own try/catch.
    if exist(targetFile, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            'The target dataset''s cache file is missing:\n\n    %s', targetFile));
    end
    if exist(sourceFile, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            'The dragged branch''s cache file is missing:\n\n    %s', sourceFile));
    end
    targetStruct = load(targetFile, "EEG");
    sourceStruct = load(sourceFile, "EEG");
    % TARGETFILE/SOURCEFILE (just verified to exist, above) always win
    % over whatever EEG.File already is -- see Alakazam.loadNodeEEG's own
    % note on why the stored field can be stale (a different machine/
    % username).
    targetStruct.EEG.File = targetFile;
    sourceStruct.EEG.File = sourceFile;

    % Call is just the transformation id (see onTransformation); no
    % parsing needed.
    transformId = char(sourceStruct.EEG.Call);

    if this.isOverlayableAverage(targetStruct.EEG, sourceStruct.EEG)
        % Overlay the dropped average on top of the target average; no
        % new node is created, so there is nothing to recurse into.
        this.overlayAverage(targetStruct.EEG, sourceStruct.EEG);
        return;
    end

    % General case: re-apply the stored transformation to the target,
    % carrying over the source's call and parameters. The id is stored
    % data (loaded from a .mat file that may predate a Transformations-
    % folder cleanup), not something just derived from code on disk, so
    % it's validated before feval rather than failing with a cryptic
    % "undefined function" error.
    if exist(transformId, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            ['Stored transformation ''%s'' no longer exists ' ...
             '(its .m file is missing from the Transformations ' ...
             'folder). Cannot replay this branch.'], transformId));
    end
    [result.EEG, ~] = feval(transformId, targetStruct.EEG, sourceStruct.EEG.params);
    result.EEG.Call   = sourceStruct.EEG.Call;
    result.EEG.params = sourceStruct.EEG.params;

    [result.EEG, newNode] = this.persistResultNode(result.EEG, ...
        targetStruct.EEG.File, sourceStruct.EEG.id, transformId, targetNode);

    % Descend into EVERY child of the source (not just the first) --
    % applying each one, in turn, to the SAME result this step just
    % produced, exactly reconstructing whatever fork the source branch has.
    [srcDir, srcName] = fileparts(sourceFile);
    childDir = fullfile(srcDir, srcName);
    if exist(childDir, "dir")
        childMat = dir(fullfile(childDir, '*.mat'));
        for i = 1:numel(childMat)
            this.evaluateDroppedBranch(fullfile(childDir, childMat(i).name), newNode);
        end
    end
end
