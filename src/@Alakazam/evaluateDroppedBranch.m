function evaluateDroppedBranch(this, sourceFile, targetNode, targetEEG)
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
%
%   EVALUATEDROPPEDBRANCH(THIS, SOURCEFILE, TARGETNODE, TARGETEEG) is how the
%   recursion below calls itself, and TARGETEEG is the dataset TARGETNODE holds,
%   already in memory. Without it, every step saved its result and the next
%   step read the same file straight back: 400 MB written and then read again
%   at each of the first steps of a RIFT chain, for a struct that never left
%   memory. Callers outside this file omit it and the target is loaded once.
%
%   THE SOURCE BRANCH IS READ THROUGH ITS META RECORD, not loaded. All this
%   needs from each source step is its transformation and settings (see
%   eegCacheMeta), and loading every step in full to read them cost about
%   1.7 GB per target on the RIFT chain. Only an AVERAGED source that might be
%   overlaid is loaded, since the overlay needs its waveforms.
    targetFile = targetNode.UserData;

    % A node can outlive its file -- a cache cleared by hand, a workspace
    % copied from another machine, a branch deleted outside the app -- so the
    % files are checked explicitly rather than letting load() throw a raw
    % "Unable to find file" straight through onNodeDropped's own try/catch.
    % A target passed in memory needs no file; the source always does.
    inMemory = nargin >= 4 && ~isempty(targetEEG);
    if ~inMemory && exist(targetFile, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            'I''m afraid the target dataset''s cache file could not be found:\n\n    %s', targetFile));
    end
    if exist(sourceFile, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            'I''m afraid the dragged branch''s cache file could not be found:\n\n    %s', sourceFile));
    end
    if ~inMemory
        targetLoaded = load(targetFile, "EEG");
        targetEEG = targetLoaded.EEG;
        clear targetLoaded;
    end
    % TARGETFILE (just verified to exist, above, or the file this dataset was
    % saved to) always wins over whatever EEG.File already is -- see
    % Alakazam.loadNodeEEG's own note on why the stored field can be stale (a
    % different machine/username).
    targetEEG.File = targetFile;

    % Call is just the transformation id (see onTransformation); no
    % parsing needed.
    sourceMeta = readEegCacheMeta(sourceFile);
    transformId = char(sourceMeta.Call);

    % Only an averaged source that lands on an averaged target can be an
    % overlay, so only then is the source loaded, and the test itself is the
    % original one.
    if strcmpi(sourceMeta.DataFormat, 'AVERAGED') ...
            && strcmpi(TransTools.FieldOr(targetEEG, 'DataFormat', ''), 'AVERAGED')
        sourceLoaded = load(sourceFile, "EEG");
        sourceLoaded.EEG.File = sourceFile;
        if this.isOverlayableAverage(targetEEG, sourceLoaded.EEG)
            % Overlay the dropped average on top of the target average; no
            % new node is created, so there is nothing to recurse into.
            this.overlayAverage(targetEEG, sourceLoaded.EEG);
            return;
        end
    end

    % General case: re-apply the stored transformation to the target,
    % carrying over the source's call and parameters. The id is stored
    % data (a record that may predate a Transformations-folder cleanup),
    % not something just derived from code on disk, so it's validated before
    % feval rather than failing with a cryptic "undefined function" error.
    if exist(transformId, "file") ~= 2
        throw(MException('Alakazam:evaluateDroppedBranch', ...
            ['I''m sorry, but the stored transformation ''%s'' no longer appears to exist ' ...
             '(its .m file seems to be missing from the Transformations folder), so I am ' ...
             'unable to replay this branch.'], transformId));
    end
    [result.EEG, ~] = TransTools.invoke(transformId, targetEEG, sourceMeta.params);
    result.EEG.Call   = sourceMeta.Call;
    result.EEG.params = sourceMeta.params;

    [result.EEG, newNode] = this.persistResultNode(result.EEG, ...
        targetFile, sourceMeta.id, transformId, targetNode);

    % Descend into EVERY child of the source (not just the first) --
    % applying each one, in turn, to the SAME result this step just
    % produced, exactly reconstructing whatever fork the source branch has.
    % The result is handed down in memory; TARGETEEG is not needed again, so
    % it is released before the descent to keep one dataset per level alive
    % rather than two.
    clear targetEEG;
    [srcDir, srcName] = fileparts(sourceFile);
    childDir = fullfile(srcDir, srcName);
    if exist(childDir, "dir")
        childMat = dir(fullfile(childDir, '*.mat'));
        for i = 1:numel(childMat)
            this.evaluateDroppedBranch(fullfile(childDir, childMat(i).name), newNode, result.EEG);
        end
    end
end
