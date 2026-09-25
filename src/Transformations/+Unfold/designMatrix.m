function EEG = designMatrix(EEG, plan)
%DESIGNMATRIX  The design of a bin plan, built by the toolbox itself.
%   EEG = Unfold.designMatrix(EEG, PLAN) sets EEG.event to PLAN.events and
%   runs uf_designmat over PLAN.eventTypes, each with its own formula from
%   PLAN.formulas (see Unfold.binModel), so EEG.unfold holds X, colnames,
%   variablenames, variabletypes, cols2variablenames, cols2eventtypes,
%   eventtypes and splines as the toolbox documents them
%   (https://www.unfoldtoolbox.org/datastructures.html).
%
%   ONE CALL FOR THE FIT AND FOR THE DIALOG'S PREVIEW. Nothing here reads
%   the data (that starts with the time expansion), so DeconvolveDialog
%   builds the same design on the events alone, and a formula the toolbox
%   refuses, or a term that turns into other columns than were meant, shows
%   while it can still be edited, not after the fit has run.
%
%   A REFUSAL NAMES THE BIN. uf_designmat's own message is about its
%   parser, not about which of several formulas it was reading, so when it
%   fails each event type is tried alone and the error
%   (Alakazam:Unfold:Formula) says which bin's formula it was, and what the
%   toolbox said about it.
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, DECONVOLVEDIALOG.
    EEG.event = plan.events;
    try
        EEG = design(EEG, plan.eventTypes, plan.formulas);
    catch err
        throw(namedRefusal(EEG, plan, err));
    end
end

% ======================================================================= %
function EEG = design(EEG, eventTypes, formulas)
%DESIGN  uf_designmat with one formula per event type. The toolbox takes a
%   list of formulas only when there are two or more: a list of one is not
%   split, and the cell then reaches its formula parser, which fails with
%   "Function is not defined for 'cell' inputs". So a single event type is
%   passed the way the toolbox passes each one to itself.
    if isscalar(eventTypes)
        EEG = uf_designmat(EEG, 'eventtypes', eventTypes(1), 'formula', formulas{1});
    else
        EEG = uf_designmat(EEG, 'eventtypes', cellfun(@(t) {t}, eventTypes, 'UniformOutput', false), ...
            'formula', formulas);
    end
end

function err = namedRefusal(EEG, plan, cause)
%NAMEDREFUSAL  The toolbox's error, with the bin whose formula caused it.
    for k = 1:numel(plan.eventTypes)
        one = EEG;
        one.event = plan.events(strcmp({plan.events.type}, plan.eventTypes{k}));
        try
            design(one, plan.eventTypes(k), plan.formulas(k));
        catch inner
            err = MException('Alakazam:Unfold:Formula', '%s', sprintf( ...
                'Unfold cannot build the formula of "%s", %s. What it said: %s', ...
                plan.typeLabels{k}, plan.formulas{k}, inner.message));
            return;
        end
    end
    err = MException('Alakazam:Unfold:Formula', '%s', sprintf([ ...
        'Unfold cannot build this design, although it accepts each bin''s formula on its own. ' ...
        'What it said: %s'], cause.message));
end
