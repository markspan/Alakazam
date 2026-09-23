function ensure(featureLabel)
%ENSURE  Make sure the Unfold toolbox is on the path, with consent.
%   FEATURELABEL names the calling feature in the consent dialog (default
%   'Regression-based ERPs'). Unfold is one shared, lazily installed
%   dependency rather than a per-feature one, so this stays one function
%   with a label rather than a copy per caller, exactly as
%   TransTools.ensureFieldTrip does.
%
%   WHAT IT IS FOR. Unfold (Ehinger & Dimigen, 2019; Dimigen & Ehinger,
%   2021, J Vis 21(1):3) fits regression-based, overlap-corrected ERPs:
%   rERPs by linear deconvolution, with non-linear covariates through
%   splines. It is needed only by the transformations that offer that
%   analysis; everything else in Alakazam runs without it, which is why this
%   is installed on first use after the user agrees rather than shipped.
%
%   THE ARCHIVE IS A PINNED TAG, NOT A RELEASE ASSET AND NOT A CLONE, and
%   each of those three words was a decision:
%
%   PINNED, the reasoning ensureFieldTrip's own comment gives: a fixed,
%   once-verified version keeps results reproducible over a project's life
%   instead of shifting under a user. The toolbox is actively maintained and
%   stable, which is an argument for using it, not for tracking its default
%   branch: an analysis whose numbers change because of when someone happened
%   to install is not reproducible either way. Update UnfoldUrl by hand when a
%   refresh is actually wanted, and re-run the suite against it.
%
%   NOT A RELEASE ASSET, because the newest releases have none: 1.1 and 1.0
%   carry a zip, 1.2 onwards carry nothing but the auto-generated source
%   archive. The URL below is therefore the source archive of tag 1.3.1.
%
%   NOT A CLONE, which is the interesting one. The toolbox's own
%   instructions are "git clone" plus "git submodule update --init
%   --recursive", and a source archive does not carry submodules. Requiring
%   git would be a new class of dependency for Alakazam, whose other
%   toolkits (EEGLAB, FieldTrip, dipfit) are all plain archive installs. It
%   turns out not to be needed: only three of Unfold's libraries are
%   submodules (lib/gramm, lib/eegvis, lib/ept_TFCE) and all three are
%   plotting or second-level statistics, which Alakazam does not use. The
%   libraries the fitting path does need (erplab, glmnet_matlab, lsmr,
%   cbrewer, luong_bruno) are committed to the repository and so are in the
%   archive. Verified on the archive itself rather than reasoned about:
%   init_unfold runs without error and uf_designmat and uf_glmfit resolve
%   afterwards, with one warning about the absent TFCE folder that
%   Unfold.startToolbox switches off.
%
%   See also UNFOLD.ISAVAILABLE, UNFOLD.STARTTOOLBOX,
%   TRANSTOOLS.ENSUREFIELDTRIP.
    if nargin < 1 || isempty(featureLabel)
        featureLabel = 'Regression-based ERPs';
    end

    if ~isempty(which('uf_designmat'))
        return;   % already usable this session
    end

    % addpath (inside installFromZip) is session-only by design, so an
    % install from a previous session is still on disk but off the path.
    % Reattach it rather than asking again for consent already given, or
    % downloading something already downloaded.
    existing = EEGLabEnvironment.findInstalled('unfold', 'init_unfold.m');
    if ~isempty(existing)
        Unfold.startToolbox(existing);
        return;
    end

    unfoldUrl = 'https://github.com/unfoldtoolbox/unfold/archive/refs/tags/1.3.1.zip';

    % LEGACY-JAVA-GUI: questdlg, matching ensureFieldTrip and AutoGEDAI's
    % ensureGEDAI, the same "optional download, consent-gated" pattern.
    answer = questdlg([ ...
        featureLabel ' needs the Unfold toolbox, which was not found on the MATLAB path.', ...
        newline, newline, ...
        'Unfold is free, open-source (GPLv3) research software by Benedikt Ehinger and ', ...
        'Olaf Dimigen for regression-based, overlap-corrected ERPs. This downloads ', ...
        'version 1.3.1 (about 30 MB) into your Documents/MATLAB folder.', ...
        newline, newline, ...
        'Download and install Unfold now?'], ...
        'Unfold not found', ...
        'Download and install', 'Cancel', 'Download and install');

    if ~strcmp(answer, 'Download and install')
        throw(MException('Alakazam:UnfoldMissing', sprintf([ ...
            'I''m afraid the Unfold toolbox is required for %s, and could not be found on the ' ...
            'MATLAB path. As its installation was declined, please install it manually from ' ...
            'https://github.com/unfoldtoolbox/unfold (add the unzipped folder to your MATLAB ' ...
            'path, then run init_unfold once), or try again and accept the download prompt.'], ...
            featureLabel)));
    end

    EEGLabEnvironment.installFromZip(unfoldUrl, 'unfold', 'init_unfold.m');
    Unfold.startToolbox(EEGLabEnvironment.findInstalled('unfold', 'init_unfold.m'));
end
