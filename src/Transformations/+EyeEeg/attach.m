function attach(root)
%ATTACH  Put an installed EYE-EEG on the path, with what it needs.
%   EyeEeg.attach(ROOT) adds ROOT (the folder holding pop_importeyetracker.m)
%   and its internal/ folder to the path, after EEGLAB itself.
%
%   TWO FOLDERS, NOT ONE: the pop_ functions sit at the top of the toolbox
%   and delegate to helpers in internal/, and installFromZip adds only the
%   folder its probe file is in. An EYE-EEG with only its top folder on the
%   path starts, and then fails inside its first call.
%
%   EEGLAB FIRST, because EYE-EEG is an EEGLAB plugin: it calls eeg_checkset
%   and the event helpers throughout.
%
%   See also EYEEEG.ENSURE, EYEEEG.ISAVAILABLE.
    if isempty(which('eeg_checkset'))
        EEGLabEnvironment.ensure();
    end
    addpath(root);
    internal = fullfile(root, 'internal');
    if isfolder(internal)
        addpath(internal);
    end
end
