function [index, labels, missing] = columns(colheader, wanted)
%COLUMNS  Which eye-tracker columns WANTED names, of those worth a channel.
%   [INDEX, LABELS, MISSING] = EyeEeg.columns(COLHEADER, WANTED) takes a
%   parsed eye track's column names (et.colheader) and 'all' or a list of
%   names, and returns the chosen columns' positions and names, and every
%   wanted name the file does not have.
%
%   TIME AND INPUT ARE NEVER CHOSEN: TIME is the tracker's clock, which the
%   join replaces, and INPUT is the trigger port, which it reads.
%
%   EITHER SPELLING OF A NAME MATCHES. parseeyelink calls a column L_GAZE_X,
%   and pop_importeyetracker names the channel it becomes L-GAZE-X
%   (underscores break EEGLAB's channel decoding, its own comment says), so a
%   stored list may hold either.
%
%   One place for both rules, because EyeTracking picks the columns to join
%   by them and its dialog offers the tick boxes by them, and the two must
%   not disagree about what a stored list means.
%
%   See also EYETRACKING, EYETRACKINGDIALOG.
    names = reshape(cellstr(string(colheader)), 1, []);
    signal = ~ismember(upper(names), {'TIME', 'INPUT'});
    missing = {};
    if (ischar(wanted) || isstring(wanted)) && strcmpi(char(wanted), 'all')
        chosen = signal;
    else
        key = @(c) reshape(strrep(cellstr(string(c)), '-', '_'), 1, []);
        chosen = signal & ismember(key(names), key(wanted));
        missing = setdiff(key(wanted), key(names(signal)), 'stable');
    end
    index = find(chosen);
    labels = names(chosen);
end
