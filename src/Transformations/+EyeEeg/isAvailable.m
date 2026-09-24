function tf = isAvailable()
%ISAVAILABLE  True when EYE-EEG can be used now, without asking anyone.
%   An install from an earlier session is on disk but off the path (addpath
%   is session-only by design), so it is reattached here rather than
%   reported missing; nothing is downloaded and no one is asked. Use
%   EyeEeg.ensure where an install may be offered.
%
%   See also EYEEEG.ENSURE, EYEEEG.ATTACH.
    tf = ~isempty(which('pop_importeyetracker')) && ~isempty(which('parseeyelink'));
    if tf
        return;
    end
    existing = EEGLabEnvironment.findInstalled('eye-eeg', 'pop_importeyetracker.m');
    if isempty(existing)
        return;
    end
    try
        EyeEeg.attach(existing);
        tf = ~isempty(which('pop_importeyetracker'));
    catch
        tf = false;
    end
end
