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
%     timeWindow   applied BEFORE the inverse, deliberately, so that
%     resampleHz   sLORETA's data covariance comes from the tested window.
%                  An estimate made over a different window is therefore not
%                  a superset that can be cropped: it is a different fit.
%
%   That last one is the subtle one, and the reason this key cannot simply
%   record the widest window and trim.
%
%   See also SOURCEESTIMATE, SOURCECLUSTERSTATS.
    key = struct();
    key.channels    = lower(cellstr(string(resolvedLabels(:))))';
    key.sourceSpace = double(TransTools.FieldOr(opts, 'SourceSpace', 20484));
    key.method      = lower(char(string(TransTools.FieldOr(opts, 'Method', 'mne'))));
    key.orientation = lower(char(string(TransTools.FieldOr(opts, 'Orientation', 'normal'))));
    key.regParam    = double(TransTools.FieldOr(opts, 'RegParam', 0.05));
    key.timeWindow  = normaliseWindow(TransTools.FieldOr(opts, 'TimeWindow', []));
    key.resampleHz  = normaliseRate(TransTools.FieldOr(opts, 'ResampleHz', []));
end

% ======================================================================= %
function w = normaliseWindow(window)
%NORMALISEWINDOW  [] and a window covering everything are NOT the same key.
%   [] means "whatever this dataset happens to span", which differs between
%   datasets; an explicit window is the same for all of them. Conflating
%   them would let an estimate made on one epoch be reused for another.
    if isempty(window)
        w = [];
    else
        w = double(window(:))';
    end
end

function r = normaliseRate(rate)
    if isempty(rate)
        r = [];
    else
        r = double(rate);
    end
end
