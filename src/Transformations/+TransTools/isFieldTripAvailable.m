function tf = isFieldTripAvailable()
%ISFIELDTRIPAVAILABLE  Whether FieldTrip is already usable this session,
%   WITHOUT ever downloading it or asking -- see TransTools.ensureFieldTrip
%   for the consent-gated path that DOES install it.
%
%   Checks, in order: (1) already on the path (which('ft_defaults')), (2)
%   previously installed by ensureFieldTrip but not yet reattached this
%   session (EEGLabEnvironment.findInstalled), reattached quietly if
%   found. Never fetches anything, and never pops the questdlg
%   ensureFieldTrip's own "not found" branch shows -- this is the
%   opposite case, "look, do not ask".
%
%   WHY THIS EXISTS SEPARATELY FROM ENSUREFIELDTRIP: a caller that runs
%   without the user having directly opted into Source-estimate mode --
%   a batch report step (GenerateSourceEstimateReportAssets), or a test
%   (FieldTripFixtures, which reuses this) -- must never trigger a ~400 MB
%   consent-gated download as a side effect of something else the user
%   asked for. Such a caller checks here first and simply skips its
%   FieldTrip-dependent work when this returns false. ensureFieldTrip
%   stays reserved for the one place a user has directly asked for the
%   download: Brain3DView's own Projection dropdown.
%
%   See also TRANSTOOLS.ENSUREFIELDTRIP, FIELDTRIPFIXTURES.
    if ~isempty(which('ft_defaults'))
        tf = true;
        return;
    end

    existing = EEGLabEnvironment.findInstalled('fieldtrip', 'ft_defaults.m');
    if isempty(existing)
        tf = false;
        return;
    end

    % Same "reattach without re-asking" reasoning as ensureFieldTrip's own
    % matching branch: consent was already given whenever this got
    % installed, and evalc keeps ft_defaults' own narration out of
    % whatever caller is just trying to get a yes/no answer.
    addpath(existing);
    evalc('ft_defaults');
    tf = true;
end
