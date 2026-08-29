function [EEG, options] = invoke(transformId, inputEEG, params)
%INVOKE  Call a transformation, and hold it to the plugin contract.
%   [EEG, OPTIONS] = TransTools.invoke(ID, INPUTEEG) runs transformation ID
%   interactively: it may open its own options dialog.
%
%   [EEG, OPTIONS] = TransTools.invoke(ID, INPUTEEG, PARAMS) replays it with
%   a previously captured PARAMS struct, which must not prompt.
%
%   WHY THIS EXISTS. The plugin contract used to be a convention: four
%   separate places called feval(transformId, ...) and each trusted whatever
%   came back. A convention with no boundary is not an interface, it is a
%   habit, and the failure mode is silence -- a transformation that returns
%   the wrong shape corrupts the workspace tree downstream of the call,
%   somewhere else entirely, long after the plugin that did it has returned.
%
%   Every call now goes through here, so a violation stops at the plugin
%   that committed it and is reported against that plugin by name.
%
%   WHAT IS CHECKED, and what deliberately is not:
%
%     - the id resolves to something callable
%     - the entry returns TWO outputs (a one-output plugin currently fails
%       with MATLAB's own "Too many output arguments", which names nothing)
%     - EEG is [], a struct, or a graphics handle (a pure-plot plugin)
%     - options is a struct, or empty when the call was cancelled
%     - cancelling is consistent: an empty EEG means an empty options
%
%   NOT checked here: that options survives a jsonencode/jsondecode round
%   trip, which templates and the script exporter both depend on. It is a
%   real clause, but running it on every call would cost more than it
%   catches, and enforcing it now would surface latent breakage in
%   transformations nobody has ever saved a template for. It belongs in a
%   conformance check an author runs deliberately.
%
%   ALSO NOT CHECKED, and worth stating plainly: that cancelling returns []
%   rather than throwing. Nothing at this seam can tell "threw because the
%   analyst cancelled" from "threw because it broke", which is exactly why
%   DefineBins raised an error dialog on Cancel for as long as it did.
%   Making that checkable needs cancellation to be expressible -- a
%   sanctioned identifier the seam recognises -- rather than a convention
%   about return values.
%
%   See also TRANSTOOLS.INITGUARD, ALAKAZAM.ONTRANSFORMATION.
    transformId = char(transformId);

    if exist(transformId, 'file') ~= 2
        throw(MException('Alakazam:contract:unknownTransformation', ...
            ['I am afraid there is no transformation called "%s" on the path, so it ' ...
             'cannot be run. A transformation is a folder under src/Transformations/ ' ...
             'holding an entry function of the same name.'], transformId));
    end

    try
        if nargin < 3
            [EEG, options] = feval(transformId, inputEEG);
        else
            [EEG, options] = feval(transformId, inputEEG, params);
        end
    catch err
        if strcmp(err.identifier, 'MATLAB:maxlhs') || ...
                strcmp(err.identifier, 'MATLAB:TooManyOutputs')
            throw(MException('Alakazam:contract:outputCount', ...
                ['The transformation "%s" does not return the two outputs the plugin ' ...
                 'contract requires. Its signature should be:\n\n' ...
                 '    function [EEG, options] = %s(input, varargin)\n\n' ...
                 'The second output is the options struct describing what it did, and ' ...
                 'is what makes the step replayable and exportable.'], ...
                transformId, transformId));
        end
        rethrow(err);                            % a real failure inside the plugin
    end

    checkReturn(transformId, EEG, options);
end

% ======================================================================= %
function checkReturn(transformId, EEG, options)
%CHECKRETURN  Hold one call's return values to the contract.
%   Each message names the transformation and the clause, because the reader
%   is whoever is writing that plugin, and "wrong type" without either is a
%   message they have to go looking for the meaning of.
    if ~(isempty(EEG) || isstruct(EEG) || allHandles(EEG))
        throw(MException('Alakazam:contract:badResult', ...
            ['The transformation "%s" returned a %s as its first output. The contract ' ...
             'allows three things: an EEG struct (the transformed dataset), [] (the ' ...
             'analyst cancelled), or a graphics handle (a plugin that only draws).'], ...
            transformId, class(EEG)));
    end

    if ~(isempty(options) || isstruct(options) || isInitSentinel(options))
        throw(MException('Alakazam:contract:badOptions', ...
            ['The transformation "%s" returned a %s as its options. The contract needs ' ...
             'a plain struct: it is stored on the result node, replayed onto other ' ...
             'datasets, and written into the exported analysis script, none of which ' ...
             'work with anything else.'], transformId, class(options)));
    end

    % Cancelling is one decision, so it has to be reported once. A plugin
    % that returns no dataset but does return a settled options struct has
    % told the caller two different things about whether anything happened.
    if isempty(EEG) && isstruct(options)
        throw(MException('Alakazam:contract:inconsistentCancel', ...
            ['The transformation "%s" returned no dataset but did return options. An ' ...
             'empty first output means the analyst cancelled, and nothing was decided, ' ...
             'so the options should be empty too.'], transformId));
    end
end

function tf = isInitSentinel(options)
%ISINITSENTINEL  Whether OPTIONS is the 'Init' sentinel.
%
%   'Init' IS PART OF THE CONTRACT, not an exception to it. TransTools.
%   InitGuard hands a transformation the char 'Init' in place of an options
%   struct when it was called with no options at all, and the nine
%   transformations that end their replay branch with `options = opts;` pass
%   it straight back out. mergeSeedFields already documents the same value
%   arriving as stored options.
%
%   An earlier version of this check rejected it, on the reasoning that
%   options must be a struct -- which is true of options a transformation
%   has actually settled, and not true of the sentinel that means it never
%   got any. Enforcing a contract clause that the contract does not contain
%   is worse than not enforcing it, because it breaks working plugins.
    tf = (ischar(options) || isstring(options)) && strcmpi(string(options), "Init");
end

function tf = allHandles(value)
%ALLHANDLES  Whether VALUE is graphics handles, for the pure-plot plugins.
%   ishandle() errors on some non-graphics inputs rather than returning
%   false, so it is guarded.
    tf = false;
    try
        tf = ~isempty(value) && all(ishandle(value(:)));
    catch
        tf = false;
    end
end
