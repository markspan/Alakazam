function [rv, EEG] = ComponentDipoles(EEG)
%COMPONENTDIPOLES  Fit one equivalent current dipole per ICA component, and
%   report how much of each component's scalp map it fails to explain.
%
%   [RV, EEG] = ComponentDipoles(EEG) returns RV, one residual variance per
%   component as a fraction in [0, 1], and EEG with dipfit's own .dipfit
%   field populated. Components that could not be fitted come back NaN.
%
%   WHY A DIPOLE FIT BELONGS AT COMPONENT LEVEL AND NOWHERE ELSE HERE. An
%   equivalent current dipole assumes the activity it explains comes from
%   one small patch. That assumption is wrong for an ERP, which is why
%   Alakazam's source analysis is a distributed inverse instead (see
%   SourceClusterStats). It is however exactly right for an ICA component:
%   a component IS a single fixed scalp topography by construction, so
%   asking "could one dipole have produced this map?" is a well-posed
%   question with a meaningful answer.
%
%   AND THE ANSWER IS USEFUL PRECISELY WHEN IT IS NO. A component that no
%   single dipole can explain is usually not one cortical source: muscle,
%   line noise, a bad channel's projection, or two sources ICA failed to
%   separate. Residual variance is therefore a physical criterion that is
%   independent of ICLabel's classifier, and the two disagreeing is worth
%   the analyst's attention. The convention in the EEGLAB literature is to
%   treat components above about 15% residual variance as unlikely to be
%   single cortical sources; that threshold is a convention, not a law, and
%   is left to the analyst rather than applied here.
%
%   Uses dipfit's own template BEM head model, which is the model dipfit
%   ships and is coregistered to its own electrode template. Note this is a
%   different head model from the one the source cluster test uses
%   (FieldTrip's), and deliberately so: each toolbox's inverse is used with
%   the head model it was built and tested against.
%
%   NOT EVERY COMPONENT CAN BE FITTED, and that is a result rather than a
%   gap. On a 63-component decomposition dipfit returned a residual variance
%   for 36 of them; the rest failed outright. Seeding the search with a
%   custom grid before pop_multifit was tried and made it worse (27 of 63
%   with a 17 mm grid), so pop_multifit's own seeding is left alone. Callers
%   should present a failure explicitly instead of as a blank: a component
%   that no single dipole can be fitted to at all is stronger evidence of a
%   non-dipolar source than any high residual variance.
%
%   BEST EFFORT BY DESIGN. Fitting is slow enough to be noticeable and can
%   fail on an unusual channel set, and nothing downstream depends on it: a
%   failure returns NaNs, which the caller renders as "no fit", rather than
%   taking down a component-selection dialog that is useful without it.
%
%   See also REMOVECOMPONENTS, TRANSTOOLS.TEMPLATE1005FILE.
    rv = [];
    if ~isfield(EEG, 'icaweights') || isempty(EEG.icaweights)
        return;
    end
    nComp = size(EEG.icaweights, 1);
    rv = nan(nComp, 1);

    try
        EEG = fitDipoles(EEG, nComp);
        if isfield(EEG, 'dipfit') && isfield(EEG.dipfit, 'model') && ...
                ~isempty(EEG.dipfit.model)
            fitted = min(nComp, numel(EEG.dipfit.model));
            for k = 1:fitted
                if ~isempty(EEG.dipfit.model(k).rv)
                    rv(k) = EEG.dipfit.model(k).rv;
                end
            end
        end
    catch
        % See the header: a failed fit costs a column, not the dialog.
    end
end

% ======================================================================= %
function EEG = fitDipoles(EEG, nComp)
%FITDIPOLES  dipfit's own settings and multi-fit, on the decomposed channels.
%   Fitted on the channel subset the decomposition actually used, the same
%   way ICLabel is run in RemoveComponents: dipfit indexes chanlocs by the
%   component weights' own channel set, and handing it the full montage
%   would misalign them.
    defaults = dipfitDefaults();

    subset = pop_select(EEG, 'channel', EEG.icachansind);
    subset.icaweights  = EEG.icaweights;
    subset.icasphere   = EEG.icasphere;
    subset.icawinv     = EEG.icawinv;
    subset.icachansind = 1:numel(EEG.icachansind);
    subset.icaact      = [];
    subset = eeg_checkset(subset);

    subset = pop_dipfit_settings(subset, ...
        'hdmfile',      defaults.hdmfile, ...
        'mrifile',      defaults.mrifile, ...
        'chanfile',     defaults.chanfile, ...
        'coordformat',  'MNI', ...
        'chansel',      1:numel(EEG.icachansind));

    % threshold 100 fits every component rather than only those already
    % below some residual variance: the residual variance is the output we
    % want, so pre-filtering on it would leave the interesting ones blank.
    subset = pop_multifit(subset, 1:nComp, 'threshold', 100, 'dipoles', 1);

    EEG.dipfit = subset.dipfit;
end

function defaults = dipfitDefaults()
%DIPFITDEFAULTS  The template BEM files dipfit ships, resolved from the
%   plugin itself rather than hard-coded, since its folder carries a version.
    dipfitPath = fileparts(which('dipfitdefs'));
    if isempty(dipfitPath)
        throw(MException('Alakazam:ComponentDipoles', ...
            'dipfit is not installed, so components cannot be dipole-fitted.'));
    end
    bem = fullfile(dipfitPath, 'standard_BEM');
    defaults = struct( ...
        'hdmfile',  fullfile(bem, 'standard_vol.mat'), ...
        'mrifile',  fullfile(bem, 'standard_mri.mat'), ...
        'chanfile', fullfile(bem, 'elec', 'standard_1005.elc'));
end
