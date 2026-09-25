function codes = otherEventsChoice(options)
%OTHEREVENTSCHOICE  Which event codes outside the bins a Deconvolve setting
%   models: 'all', or a row cellstr of codes, empty meaning none.
%   CODES = Unfold.otherEventsChoice(OPTIONS) reads OPTIONS.otherEvents.
%
%   AN EMPTY LIST IS A REAL ANSWER ("none"), which is why this is not
%   TransTools.FieldOr: that reads an empty field as an absent one and would
%   hand back the default, modelling every code. It has to survive a template
%   too, where JSON brings an empty list back as [] and a list of one code
%   back as a plain string.
%
%   OPTIONS SAVED BEFORE THE CHOICE WAS PER CODE carry only modelOtherEvents
%   (true or false), and false there still means none. This is the one place
%   that older field is read: Deconvolve, its dialog and Unfold.binModel all
%   ask here, so a stored setting means the same to each of them.
%
%   See also DECONVOLVE, DECONVOLVEDIALOG, UNFOLD.BINMODEL.
    codes = 'all';
    if ~isstruct(options)
        return;
    end
    if isfield(options, 'otherEvents')
        value = options.otherEvents;
        if isempty(value)
            codes = {};
        elseif (ischar(value) || isstring(value)) && strcmpi(char(value), 'all')
            codes = 'all';
        else
            codes = reshape(cellstr(string(value)), 1, []);
        end
    elseif isfield(options, 'modelOtherEvents') && ~isempty(options.modelOtherEvents) ...
            && ~logical(options.modelOtherEvents)
        codes = {};
    end
end
