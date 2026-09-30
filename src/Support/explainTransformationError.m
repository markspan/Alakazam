function [title, message] = explainTransformationError(transformId, ME, varargin)
%EXPLAINTRANSFORMATIONERROR  The title and text of the dialog shown when a
%   transformation, or what follows it, fails.
%
%   [TITLE, MESSAGE] = explainTransformationError(ID, ME) explains ME, an
%   error raised while running transformation ID, as a title and a cellstr
%   of lines for uialert. Name-value options:
%
%     'Phase'    what was going on when ME was raised:
%                  'run'   the transformation itself (the default)
%                  'save'  writing its result to the workspace
%                  'draw'  drawing its result
%     'Dataset'  the dataset concerned: the input for 'run', the result
%                otherwise. Described in one line (its kind, channels,
%                epochs or bins, length), since "the wrong kind of data"
%                means nothing without saying what kind it was.
%     'Kept'     for 'save' and 'draw': true when the result stays in the
%                tree anyway (a recalculation, which has already overwritten
%                its files), false when it was taken out again (the
%                default).
%
%   WHY THE PHASE MATTERS. Every failure used to read "ID could not run on
%   this dataset", followed by a guess that the data was of the wrong kind.
%   When DeriveChannels ran correctly and AverageView then failed to draw
%   the result, that message sent the reader to check their data and their
%   let statements, both of which were fine; the fault was in the view. A
%   failure after the step says so, and says what became of the result.
%
%   WHY THE GUESS IS NOW NARROWER. A guard clause of Alakazam's own (an
%   'Alakazam:' identifier) explains itself and is shown as it is. A raw
%   MATLAB error is one of two kinds. Arrays that do not fit together, or an
%   index past the end, is what data of an unexpected shape produces, so
%   that one names the dataset's shape and says what to check. Anything else
%   is a mistake in the code rather than in the data, and is called that.
%   Both give the location, capped at four stack frames.
%
%   Pure: no figure, so the wording is testable without a running app.
%
%   See also ALAKAZAM.SHOWTRANSFORMATIONERROR, ALAKAZAM.ONTRANSFORMATION.
    p = inputParser();
    p.addParameter('Phase', 'run', @(x) any(strcmpi(x, {'run', 'save', 'draw'})));
    p.addParameter('Dataset', []);
    p.addParameter('Kept', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    phase = lower(char(p.Results.Phase));
    kept = logical(p.Results.Kept);
    described = describeDataset(p.Results.Dataset);
    ownGuard = startsWith(ME.identifier, 'Alakazam:');

    reason = ME.message;
    % Alakazam's guard clauses open with "Problem in <Transform>: ", which
    % the dialog's title already says.
    prefix = sprintf('Problem in %s: ', transformId);
    if startsWith(reason, prefix)
        reason = extractAfter(reason, prefix);
    end

    switch phase
        case 'run'
            title = sprintf('Couldn''t run %s', transformId);
            message = {sprintf('I''m sorry, but %s could not run on this dataset:', transformId), '', reason};
            if ~ownGuard && isShapeError(ME)
                message = [message, {'', sprintf(['The arrays inside %s did not fit together, which is what ' ...
                    'data of a shape it does not expect produces. %s If %s needs another kind of data ' ...
                    '(segmented, averaged or frequency-domain), select that in the tree; if it should ' ...
                    'work on data like this, it is a defect in %s.'], transformId, ...
                    sentence('It was given', described), transformId, transformId)}];
            elseif ~ownGuard
                message = [message, {'', sprintf(['This is an error %s did not anticipate rather than ' ...
                    'a message it gives on purpose, so it is most likely a defect in %s, not a ' ...
                    'problem with your data.'], transformId, transformId)}];
            end
        case 'save'
            title = sprintf('Couldn''t save the result of %s', transformId);
            message = {sprintf('%s ran, but its result could not be saved%s:', transformId, fate(kept)), '', reason};
        case 'draw'
            title = sprintf('Couldn''t show the result of %s', transformId);
            message = {sprintf('%s ran, but its result could not be drawn%s:', transformId, fate(kept)), '', reason, ...
                '', strtrim(sprintf(['The fault is in the view that draws results like this one, not in ' ...
                'your data or in the settings you chose. %s'], sentence('The result was', described)))};
    end

    if ~ownGuard || ~strcmp(phase, 'run')
        where = stackText(ME);
        if ~isempty(where)
            message = [message, {'', sprintf('Technical detail (%s): %s', ME.identifier, where)}];
        end
    end
end

% ======================================================================= %
function text = fate(kept)
%FATE  What became of the result, as the end of the opening sentence.
    if kept
        text = ', so it is in the tree but cannot be shown';
    else
        text = ', so it has not been added to the tree';
    end
end

function s = sentence(lead, described)
%SENTENCE  "<LEAD> <DESCRIBED>." or nothing, when there is no description.
    s = '';
    if ~isempty(described)
        s = sprintf('%s %s.', lead, described);
    end
end

function tf = isShapeError(ME)
%ISSHAPEERROR  Whether ME is MATLAB saying arrays did not fit together or an
%   index ran past the end: the errors data of an unexpected shape produces.
%   Read from the identifier (MATLAB:sizeDimensionsMustMatch, MATLAB:dimagree,
%   MATLAB:innerdim, MATLAB:catenate:dimensionMismatch, MATLAB:badsubscript,
%   MATLAB:index:outOfBounds, MATLAB:subsassigndimmismatch, and their kin),
%   since the message text is translated and the identifier is not.
    tf = startsWith(ME.identifier, 'MATLAB:') && ~isempty(regexpi(ME.identifier, ...
        '(dim|size|subscript|numel|catenate|index|reshape|outofbounds)', 'once'));
end

function text = describeDataset(EEG)
%DESCRIBEDATASET  One line saying what kind of dataset EEG is, or '' when
%   it is not one.
    text = '';
    if ~isstruct(EEG) || ~isfield(EEG, 'data') || isempty(EEG.data)
        return;
    end
    nChan = size(EEG.data, 1);
    nSamp = size(EEG.data, 2);
    if isfield(EEG, 'DataType') && strcmpi(char(string(EEG.DataType)), 'FREQUENCYDOMAIN')
        text = sprintf('frequency-domain data, %s by %d frequencies', count(nChan, 'channel'), nSamp);
        return;
    end
    switch upper(inferDataFormat(EEG))
        case 'CONTINUOUS'
            if isfield(EEG, 'srate') && ~isempty(EEG.srate) && EEG.srate > 0
                text = sprintf('continuous data, %s over %.1f s', count(nChan, 'channel'), nSamp / EEG.srate);
            else
                text = sprintf('continuous data, %s by %d samples', count(nChan, 'channel'), nSamp);
            end
        case 'EPOCHED'
            text = sprintf('segmented data, %s by %s of %d samples', count(nChan, 'channel'), ...
                count(size(EEG.data, 3), 'epoch'), nSamp);
        otherwise
            text = sprintf('an average, %s by %s of %d samples', count(nChan, 'channel'), ...
                count(size(EEG.data, 3), 'bin'), nSamp);
    end
end

function s = count(n, noun)
%COUNT  "1 channel", "32 channels".
    if n == 1
        s = sprintf('%d %s', n, noun);
    else
        s = sprintf('%d %ss', n, noun);
    end
end

function text = stackText(ME)
%STACKTEXT  The first few stack frames, as "name (line N) <- ...".
%   The whole stack rather than Alakazam's own files only: an error inside
%   FieldTrip or EEGLAB is exactly where the calling frame alone does not
%   say enough. Capped at four, since past that it is a stack trace rather
%   than an explanation.
    text = '';
    if isempty(ME.stack)
        return;
    end
    n = min(4, numel(ME.stack));
    parts = arrayfun(@(f) sprintf('%s (line %d)', f.name, f.line), ME.stack(1:n), 'UniformOutput', false);
    text = strjoin(parts, ' <- ');
end
