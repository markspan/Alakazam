function ensure(featureLabel)
%ENSURE  Make EYE-EEG usable, installing it with the user's consent.
%   EyeEeg.ensure(FEATURELABEL) returns quietly when EYE-EEG is already on
%   the path or installed from an earlier session (it is then reattached).
%   Otherwise it asks, once, whether to download it, and throws
%   Alakazam:EyeEegMissing if the answer is no.
%
%   EYE-EEG (Dimigen, Sommer, Hohlfeld, Jacobs & Kliegl, 2011) is free,
%   open-source research software under the GPLv3, the same terms as Unfold,
%   and like Unfold it is installed on first use after the user agrees rather
%   than shipped.
%
%   PINNED TO TAG v1.01, the source archive of that tag, for the reason every
%   pinned dependency here has: an analysis whose numbers change because of
%   when someone happened to install is not reproducible. v1.01 in particular
%   carries the fix for EEGLAB 2025.1 and later, whose event handling broke
%   eye-movement detection in 1.0. Update EyeEegUrl by hand when a refresh is
%   actually wanted, and re-run the suite against it.
%
%   See also EYEEEG.ISAVAILABLE, EYEEEG.ATTACH, UNFOLD.ENSURE.
    if nargin < 1 || isempty(featureLabel)
        featureLabel = 'Eye-tracking import';
    end

    if EyeEeg.isAvailable()
        return;   % on the path, or reattached from an earlier install
    end

    eyeEegUrl = 'https://github.com/olafdimigen/eye-eeg/archive/refs/tags/v1.01.zip';

    % LEGACY-JAVA-GUI: questdlg, matching Unfold.ensure and ensureFieldTrip,
    % the same "optional download, consent-gated" pattern.
    answer = questdlg([ ...
        featureLabel ' needs the EYE-EEG toolbox, which was not found on the MATLAB path.', ...
        newline, newline, ...
        'EYE-EEG is free, open-source (GPLv3) research software by Olaf Dimigen and ', ...
        'colleagues for joining eye-tracking and EEG recordings. This downloads version ', ...
        '1.01 into your Documents/MATLAB folder.', ...
        newline, newline, ...
        'Download and install EYE-EEG now?'], ...
        'EYE-EEG not found', ...
        'Download and install', 'Cancel', 'Download and install');

    if ~strcmp(answer, 'Download and install')
        throw(MException('Alakazam:EyeEegMissing', '%s', sprintf([ ...
            'I''m afraid the EYE-EEG toolbox is required for %s, and could not be found on the ' ...
            'MATLAB path. As its installation was declined, please install it manually from ' ...
            'https://github.com/olafdimigen/eye-eeg (add the unzipped folder and its internal ' ...
            'folder to your MATLAB path), or try again and accept the download prompt.'], ...
            featureLabel)));
    end

    EEGLabEnvironment.installFromZip(eyeEegUrl, 'eye-eeg', 'pop_importeyetracker.m');
    EyeEeg.attach(EEGLabEnvironment.findInstalled('eye-eeg', 'pop_importeyetracker.m'));
end
