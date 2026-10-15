function plan = keepEvents(plan, keep)
%KEEPEVENTS  A bin plan with only some of its events still in the fit.
%   PLAN = Unfold.keepEvents(PLAN, KEEP) leaves in the fit only the rows of
%   PLAN.events that KEEP marks (and that were in it already). The others
%   stay in .events, as the toolbox keeps them in EEG.event, but are no
%   longer .kept: not in a bin's count, its events or its trials, nor among
%   the values its waveform is held at (.pooled).
%
%   Two steps leave events out: uf_imputeMissing's 'drop', which zeroes the
%   rows of those missing a number their formula uses (Unfold.binModel),
%   and, without overlap correction, uf_epoch, which epochs only the events
%   whose window is clear of the stretches left out and lies inside the
%   recording (Unfold.fitBins).
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, UNFOLD.POOLEDVALUES.
    plan.kept = plan.kept & reshape(logical(keep), 1, []);
    gone = plan.eventSource(~plan.kept);
    for k = 1:numel(plan.membership)
        plan.membership{k} = setdiff(plan.membership{k}, gone, 'stable');
    end
    plan.binCounts = cellfun(@numel, plan.membership);
    plan.cellCounts = cellfun(@(type) nnz(strcmp({plan.events.type}, type) & plan.kept), plan.cellTypes);
    plan.pooled = Unfold.pooledValues(plan.events(plan.kept), plan.eventTypes, plan.formulas);
end
