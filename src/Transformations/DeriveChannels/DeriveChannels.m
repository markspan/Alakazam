function [EEG, options] = DeriveChannels(input, varargin)
%% DeriveChannels  Add, overwrite or remove channels ("let" statements).
%
%   A difference wave between electrodes is a channel operation, not a bin
%   operation: a bin says which EVENTS go into an average, while this says
%   how to combine the CHANNELS of whatever is already there. ERPLAB keeps
%   the same distinction (pop_eegchanoperator against pop_binoperator), and
%   so does Alakazam: bin arithmetic (bin 5 = bin 4 - bin 3) lives in
%   DefineBins, channel arithmetic lives here.
%
%   One statement per line:
%
%       let LRP      = C3 - C4
%       let midline  = (Fz + Cz + Pz) / 3
%       let RMSfront = sqrt((Fz*Fz + Cz*Cz) / 2)
%
%   The grammar is deliberately small and is evaluated directly, never
%   eval-ed: + - * / on channels and numbers, unary minus, parentheses, and
%   abs()/sqrt(). A channel whose name is not a plain word goes in double
%   quotes (let eogv = LEOG - "53"), and a bare number that is also a
%   channel's name is refused. Lines starting with % are comments. See
%   TransTools.ApplyDerivations for the full grammar and its reasoning.
%
%   A NAME THE DATA ALREADY HAS IS OVERWRITTEN, and [] REMOVES IT:
%
%       let ECG = -ECG          % an inverted ECG the right way up
%       let ECG2 = []           % the channel is gone
%
%   The lines run in order, each on the channels the lines above left, so
%   "let ECG2 = ECG" and then "let ECG = []" keeps a copy under the new name.
%   An overwritten channel keeps its place, position and type.
%
%   WORKS AT ANY STAGE. The arithmetic is elementwise over a channel's
%   waveform, so this runs on continuous, epoched or averaged data alike and
%   leaves DataType/DataFormat untouched. Putting it on an Average node is
%   the usual case (an LRP or an N2pc difference is an ERP-domain idea), but
%   deriving before epoching is equally valid when the derived channel is
%   what you want to epoch, baseline or reject on.
%
%   ON AN AVERAGE, NO ERROR BAND. The standard error and aSME of a derived
%   channel depend on how its source channels covary over trials, which an
%   average no longer holds, so they are NaN (see
%   TransTools.AlignChannelCompanions) and the view draws the line without
%   a band. Derived on the epochs, before Average, the channel gets both.
%
%   WHY THIS IS ITS OWN STEP, when Measure's own "derived channels" field
%   already ran the same engine. Because a derivation is a change to the
%   data, not a measurement of it, and hiding it inside Measure meant you
%   could not plot an LRP without scoring it, could not baseline or
%   re-reference a derived channel afterwards, and had to repeat the let
%   block in every Measure node that wanted the same channel (including
%   across subjects, for a grand average to line up). As a node it is
%   visible, plottable, and composes with everything downstream.
%
%   STEPS ADD UP. A later DeriveChannels node, or a let block in a
%   downstream Measure, works on the channels this node left, its derived
%   ones included, and overwrites one only if it names it again. Until
%   2026-10-22 each such step first removed every channel marked 'derived',
%   so a second node could not use the first one's channels ("ECG2 is not a
%   channel" while the dialog listed it). Recalculate and replay still add
%   no duplicates: a step re-run starts from its parent's data, and a name
%   that is already there is overwritten, not added twice.
%
%   TOOLBOX OR OWN CODE. ERPLAB's pop_eegchanoperator does channel arithmetic,
%   but ERPLAB is not a toolbox Alakazam installs, and its formulas are not
%   replayable steps; here a derived channel is replaced, not duplicated, on
%   Recalculate (above). The arithmetic itself is MATLAB's. Checked by
%   DeriveChannelsTest.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = DeriveChannels(input)        % interactive dialog
%     [EEG, options] = DeriveChannels(input, opts)  % replay a stored struct
%
%   OPTIONS carries .derivations, the let block as text -- the same field
%   name Measure uses, so a block can be moved between the two unchanged.
%
%   See also TRANSTOOLS.APPLYDERIVATIONS, MEASURE,
%   DEFINEBINS (bin arithmetic), MERGELETDEFINITIONS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DeriveChannels', varargin{:});

if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
    throw(MException('Alakazam:DeriveChannels', ...
        ['Problem in DeriveChannels: I''m afraid this dataset has no channel list, ' ...
         'so there are no channels to combine.']));
end

if interactive
    stored = TransformSettings.get('DeriveChannels');
    labels = {input.chanlocs.labels};
    example = sprintf('%% One per line, e.g. a lateralised difference:\n%% let LRP = %s - %s\n', ...
        labels{1}, labels{min(2, numel(labels))});
    % The block is checked at OK against this dataset's own channels, by the
    % engine the transformation runs, so a typo, an unknown channel or a
    % name clash is reported in the dialog rather than after the node
    % exists, and the two cannot disagree about what parses.
    options = TransformOptionsDialog( ...
        'title', 'Derive Channels', ...
        'Description', sprintf(['One "let <name> = <expression>" per line. Channels by label, ' ...
            'in double quotes when the label is not a plain word ("53", "EOG-L"); + - * / with ' ...
            'parentheses, abs() and sqrt(); %% starts a comment. A name that is already a ' ...
            'channel is overwritten (let ECG = -ECG), and let <name> = [] removes it.\nChannels: %s'], ...
            strjoin(labels, ', ')), ...
        {'Statements'; 'derivations'}, DialogFields.TextArea( ...
            TransTools.FieldOr(stored, 'derivations', example), 'Height', 220, ...
            'Validate', @(text) TransTools.ApplyDerivations(channelsOnly(input), text)));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('DeriveChannels', options);
else
    options = opts;
end

text = char(string(TransTools.FieldOr(options, 'derivations', '')));
[EEG, added, replaced, removed] = TransTools.ApplyDerivations(input, text);

% Nothing defined is a no-op rather than an error, so a stored block that
% has been commented out still replays instead of stopping the branch.
done = {};
if ~isempty(added);    done{end + 1} = ['added ' strjoin(added, ', ')];       end
if ~isempty(replaced); done{end + 1} = ['overwrote ' strjoin(replaced, ', ')]; end
if ~isempty(removed);  done{end + 1} = ['removed ' strjoin(removed, ', ')];   end
if isempty(done)
    fprintf('DeriveChannels: no "let" statements, so no channels were changed.\n');
else
    fprintf('DeriveChannels: %s.\n', strjoin(done, '; '));
end
end

% ======================================================================= %
function d = channelsOnly(EEG)
%CHANNELSONLY  The dataset's channels over three samples: enough for the
%   derivation engine to resolve labels, evaluate the grammar and refuse
%   removing a channel the ICA decomposition uses when the dialog checks a
%   block, without copying the recording.
    d = struct('chanlocs', EEG.chanlocs, 'nbchan', numel(EEG.chanlocs), ...
        'data', zeros(numel(EEG.chanlocs), 3), ...
        'icachansind', TransTools.FieldOr(EEG, 'icachansind', []));
end
