function key = Key(resolvedLabels, opts)
%KEY  Everything that decides what a source estimate contains.
%
%   KEY = SourceEstimateKey(RESOLVEDLABELS, OPTS) builds the struct a stored
%   estimate carries so that a later analysis can tell whether it may reuse
%   it. Two keys are interchangeable exactly when isequaln says so.
%
%   THE POINT IS NOT CACHING, IT IS REFUSING TO REUSE THE WRONG THING. A
%   cached estimate that is silently accepted under different settings does
%   not make an analysis slower, it makes it wrong, and wrong in a way no
%   downstream check could detect: the numbers are plausible, the clusters
%   are plausible, and they answer a question nobody asked. So this key errs
%   heavily towards declaring a mismatch.
%
%   WHY EACH FIELD IS IN IT:
%     channels     the leadfield's rows ARE these channels, in this order. A
%                  different set is a different forward model, and a
%                  different order silently permutes the data.
%     sourceSpace  the vertices the estimate is defined on.
%     method       dSPM and sLORETA return different quantities entirely.
%     orientation  signed and magnitude are not convertible.
%     regParam     chooses which of the infinitely many solutions is
%                  returned; two estimates at different regularisation are
%                  different answers, not different precisions.
%   WHAT IS DELIBERATELY ABSENT: the time window and the sample rate. They
%   used to be here, on the grounds that a data-covariance method such as
%   sLORETA sees only the window under analysis, so an estimate over a wider
%   one was a different fit rather than a superset that could be cropped.
%
%   That turned out not to describe this code. Every ft_inverse_* spatial
%   filter is data-independent (bit-identical operators from two entirely
%   different datasets on one leadfield, for mne, eloreta and sloreta), so
%   the data covariance never reaches the estimate and cropping commutes
%   with inverting: measured at a relative 1.5e-16, decimation likewise.
%   Keeping them here meant a whole-epoch estimate could not answer for
%   200-400 ms and every subject re-inverted per window tried. Coverage is
%   checked instead, at the point of use, by SourceCache.Lookup.
%
%   See also SOURCEESTIMATE, SOURCECLUSTERSTATS.
    key = struct();
    key.channels    = lower(cellstr(string(resolvedLabels(:))))';
    key.sourceSpace = double(TransTools.FieldOr(opts, 'SourceSpace', 20484));
    key.method      = lower(char(string(TransTools.FieldOr(opts, 'Method', 'mne'))));
    key.orientation = lower(char(string(TransTools.FieldOr(opts, 'Orientation', 'normal'))));
    key.regParam    = double(TransTools.FieldOr(opts, 'RegParam', 0.05));
end
