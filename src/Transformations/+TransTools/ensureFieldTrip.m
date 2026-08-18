function ensureFieldTrip()
%ENSUREFIELDTRIP  Make sure FieldTrip is on the path, with consent.
%   FieldTrip is only needed for Brain3DView's optional "Source estimate"
%   mode (TransTools.BuildSourceForwardModel/ComputeSourceEstimate) -- the
%   default "Scalp projection" mode (TransTools.DrawBrainMap) needs
%   nothing beyond what Alakazam already ships. Like AutoGEDAI's own
%   ensureGEDAI, this is installed lazily on first use, only after the
%   user explicitly agrees: unlike the small EEGLAB registry plugins
%   EEGLabEnvironment installs quietly at startup, this is a ~400 MB
%   download every user should get to decline.
%
%   The FULL FieldTrip release (fieldtrip-<date>.zip, ~400 MB) is used,
%   NOT the "lite" build (~90 MB): lite strips out exactly the template
%   head models and source models (template/headmodel, template/
%   sourcemodel) BuildSourceForwardModel depends on, since it needs no
%   per-subject MRI -- installing lite would silently break source mode.
%
%   The download URL below is a dated release
%   (https://download.fieldtriptoolbox.org/, no permanent "always latest"
%   alias exists there unlike EEGLAB's own currentversion/ URL) -- pinned
%   deliberately, the same reasoning GEDAI's own version pin uses: a
%   fixed, once-verified version keeps source-modeling results
%   reproducible across a project's lifetime rather than silently
%   shifting under an analyst whenever a new FieldTrip snapshot appears.
%   Update FieldTripUrl by hand when a refresh is actually wanted.
    if ~isempty(which('ft_defaults'))
        return; % already available this session
    end

    % addpath (inside installFromZip) is deliberately session-only, so a
    % previous install is not back on the path in a fresh MATLAB session
    % even though it is still on disk -- reattach it quietly here instead
    % of re-asking for consent (already given) and re-downloading
    % (unnecessary) every single time this is needed.
    existing = EEGLabEnvironment.findInstalled('fieldtrip', 'ft_defaults.m');
    if ~isempty(existing)
        addpath(existing);
        ft_defaults;
        return;
    end

    fieldTripUrl = 'https://download.fieldtriptoolbox.org/fieldtrip-20260812.zip';

    % LEGACY-JAVA-GUI: questdlg, matching AutoGEDAI's own ensureGEDAI --
    % the same "optional heavy download, consent-gated" pattern, not
    % (yet) migrated to a uiconfirm anywhere in this codebase.
    answer = questdlg([ ...
        'Source-estimate mode needs the FieldTrip toolbox, which was not found ', ...
        'on the MATLAB path.', newline, newline, ...
        'FieldTrip is free, open-source (GPLv2/v3) research software from the ', ...
        'Donders Institute. This downloads the full release (about 400 MB, ', ...
        'including its template head/source models) into your Documents/MATLAB ', ...
        'folder.', newline, newline, ...
        'Download and install FieldTrip now?'], ...
        'FieldTrip not found', ...
        'Download and install', 'Cancel', 'Download and install');

    if ~strcmp(answer, 'Download and install')
        throw(MException('Alakazam:FieldTripMissing', ...
            ['FieldTrip is required for source-estimate mode, and was not found ' ...
             'on the MATLAB path. Its installation was declined. Install it ' ...
             'manually from https://www.fieldtriptoolbox.org/download/ (add the ' ...
             'unzipped folder to your MATLAB path, then run ft_defaults once), or ' ...
             'try source-estimate mode again and accept the download prompt.']));
    end

    EEGLabEnvironment.installFromZip(fieldTripUrl, 'fieldtrip', 'ft_defaults.m');
    ft_defaults;
end
