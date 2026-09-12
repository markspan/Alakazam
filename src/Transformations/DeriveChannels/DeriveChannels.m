function [EEG, options] = DeriveChannels(input, varargin)
%% DeriveChannels  Add channels computed from existing ones ("let" statements).
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
%   abs()/sqrt(). Lines starting with % are comments. See
%   TransTools.ApplyDerivations for the full grammar and its reasoning.
%
%   WORKS AT ANY STAGE. The arithmetic is elementwise over a channel's
%   waveform, so this runs on continuous, epoched or averaged data alike and
%   leaves DataType/DataFormat untouched. Putting it on an Average node is
%   the usual case (an LRP or an N2pc difference is an ERP-domain idea), but
%   deriving before epoching is equally valid when the derived channel is
%   what you want to epoch, baseline or reject on.
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
%   USE ONE PLACE OR THE OTHER. A derived channel is marked
%   .type = 'derived', and whichever step defines derivations replaces every
%   derived channel rather than adding to them -- that is what makes
%   Recalculate and replay idempotent instead of accumulating duplicates. So
%   a non-empty let block in a downstream Measure will replace the channels
%   this node added. Measure is a no-op when its field is blank, which is
%   the combination to use: derive here, leave Measure's field empty.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = DeriveChannels(input)        % interactive dialog
%     [EEG, options] = DeriveChannels(input, opts)  % replay a stored struct
%
%   OPTIONS carries .derivations, the let block as text -- the same field
%   name Measure uses, so a block can be moved between the two unchanged.
%
%   See also TRANSTOOLS.APPLYDERIVATIONS, DERIVECHANNELSDIALOG, MEASURE,
%   DEFINEBINS (bin arithmetic), MERGELETDEFINITIONS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DeriveChannels', varargin{:});

if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
    throw(MException('Alakazam:DeriveChannels', ...
        ['Problem in DeriveChannels: I''m afraid this dataset has no channel list, ' ...
         'so there are no channels to combine.']));
end

if interactive
    options = DeriveChannelsDialog(input, TransformSettings.get('DeriveChannels'));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('DeriveChannels', options);
else
    options = opts;
end

text = char(string(TransTools.FieldOr(options, 'derivations', '')));
[EEG, added] = TransTools.ApplyDerivations(input, text);

if isempty(added)
    % Nothing defined: a no-op rather than an error, so a stored block that
    % has been commented out still replays instead of stopping the branch.
    fprintf('DeriveChannels: no "let" statements, so no channels were added.\n');
else
    fprintf('DeriveChannels: added %s.\n', strjoin(added, ', '));
end
end
