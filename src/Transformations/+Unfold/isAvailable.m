function tf = isAvailable()
%ISAVAILABLE  Whether the Unfold toolbox is usable this session,
%   WITHOUT ever downloading it or asking. See Unfold.ensure for
%   the consent-gated path that does install it.
%
%   Checks, in order: (1) already usable (which('uf_designmat')), (2)
%   installed by a previous Unfold.ensure but not reattached in this session
%   (EEGLabEnvironment.findInstalled), reattached quietly if found. Never
%   fetches anything and never shows the consent dialog Unfold.ensure's own
%   "not found" branch shows: this is the opposite case, look rather than
%   ask.
%
%   IT ASKS FOR uf_designmat, NOT init_unfold.m. The two are not the same
%   question. installFromZip adds only the one folder holding the probe file,
%   so after an install init_unfold.m is on the path while the toolbox's
%   actual functions, which live in src/uf_toolbox, are not: they arrive
%   only when init_unfold has run. Testing for the initialiser would
%   therefore report a toolbox that cannot yet do anything.
%
%   WHY THIS EXISTS SEPARATELY FROM UNFOLD.ENSURE, the same reasoning as
%   TransTools.isFieldTripAvailable: a caller that runs without the user
%   having asked for regression-based ERPs (a batch step, a test) must never
%   trigger a consent-gated 30 MB download as a side effect of something
%   else. Such a caller checks here and skips its Unfold-dependent work when
%   this returns false. Unfold.ensure stays for the places where the user has
%   directly asked for it.
%
%   See also UNFOLD.ENSURE, UNFOLD.STARTTOOLBOX,
%   TRANSTOOLS.ISFIELDTRIPAVAILABLE.
    if ~isempty(which('uf_designmat'))
        tf = true;
        return;
    end

    existing = EEGLabEnvironment.findInstalled('unfold', 'init_unfold.m');
    if isempty(existing)
        tf = false;
        return;
    end

    % Consent was given whenever this got installed, so reattaching it is
    % not a new decision; and a broken install should leave this answering
    % "no" rather than throwing, since every caller's contract here is a
    % yes or no rather than an error.
    try
        Unfold.startToolbox(existing);
        tf = true;
    catch
        tf = false;
    end
end
