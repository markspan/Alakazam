function key = SnapshotKey(resolvedLabels, sourceSpace, method)
%SNAPSHOTKEY  The estimate a report snapshot needs.
%
%   KEY = SourceEstimateSnapshotKey(RESOLVEDLABELS, SOURCESPACE, METHOD)
%   describes exactly what TransTools.RenderSourceEstimateSnapshot would
%   compute, so a caller holding a stored estimate can ask whether it is the
%   same thing.
%
%   IT LIVES HERE, NEXT TO THE RENDERER, ON PURPOSE. The report used to
%   build this key itself, restating the renderer's own choices: magnitude
%   orientation, the default regularisation, no window. Those are not the
%   report's decisions to know. If the renderer ever asked InverseSolution
%   for something else, the report's key would keep matching estimates that
%   are no longer what the renderer produces, or -- more likely -- match
%   nothing at all and quietly stop reusing, with no error and no wrong
%   answer to notice. That exact failure has already happened once in this
%   feature, in Brain3D, where a key built from the wrong channel list meant
%   the reuse path never ran.
%
%   The snapshot solves the WHOLE time course to find its own peak instant,
%   hence the empty window and rate; and it asks for no orientation, which
%   is InverseSolution's own 'magnitude' default.
%
%   See also TRANSTOOLS.RENDERSOURCEESTIMATESNAPSHOT,
%   TRANSTOOLS.SOURCEESTIMATEKEY, TRANSTOOLS.STOREDSOURCEESTIMATE.
    key = SourceCache.Key(resolvedLabels, struct( ...
        'SourceSpace', sourceSpace, ...
        'Method',      method, ...
        'Orientation', 'magnitude', ...
        'RegParam',    0.05, ...
        'TimeWindow',  [], ...
        'ResampleHz',  []));
end
