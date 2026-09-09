classdef ViewFocus < handle
%VIEWFOCUS  The channel and bin the analyst last looked at.
%
%   One instance lives on the application for the length of the session.
%   When a new plot tab is opened, AlakazamPlotter captures the selection
%   from the tab that was current and applies it to the new view, so
%   stepping through the workspace tree keeps showing the same electrode
%   rather than resetting to the first one every time.
%
%   LABELS, NOT INDICES, and this is the whole design. Two datasets in one
%   workspace routinely have different channel counts and different orders:
%   a re-referenced set has lost its reference channel, an interpolated one
%   has a different montage, a spectral result carries only the channels it
%   measured. Channel 12 is therefore a different electrode in each of
%   them, and remembering the number would silently show the wrong
%   electrode while looking as though it had worked. The label is the only
%   thing that means the same in both. The same argument holds for bins,
%   whose order follows whatever DefineBins produced.
%
%   A LABEL THAT IS NOT THERE IS NOT AN ERROR. Moving from a 64-channel
%   recording to an ICA result that has no "Cz" is ordinary, and the view
%   simply keeps its own default. Nothing is reported, because there is
%   nothing the analyst would do about it.
%
%   NOTHING IS PERSISTED. This is a within-session convenience, not a
%   setting: it is not written to the workspace file, and a new session
%   starts with no memory. Persisting it would make a saved workspace
%   reopen on whatever electrode happened to be showing when it was saved,
%   which is not a property of the analysis.
%
%   HOW A VIEW TAKES PART. Any view may implement either or both of:
%
%       focus = currentFocus(this)   % a struct with .Channel and/or .Bin
%       applyFocus(this, focus)      % adopt what it recognises, ignore rest
%
%   Views that implement neither are skipped, which is why ReportView and
%   SignalView need no changes. The methods are asked for with ismethod
%   rather than declared on AlakazamView: that base class documents its own
%   reason for staying minimal, and a focus is genuinely not something
%   every view has.
%
%   See also ALAKAZAMPLOTTER, AVERAGEVIEW, SCALPDISTRIBUTIONVIEW.

    properties (SetAccess = private)
        ChannelLabel = ''   % last channel label seen, '' for none yet
        BinLabel     = ''   % last bin label seen, '' for none yet
    end

    methods
        function capture(this, view)
        %CAPTURE  Remember what VIEW is currently showing.
        %   A view reports only what it has, so a bin-only view leaves the
        %   remembered channel alone and vice versa. That matters when
        %   moving through a mix of view kinds: looking at a scalp map does
        %   not erase which electrode the waveform views were on.
            if isempty(view) || ~isvalid(view) || ~ismethod(view, 'currentFocus')
                return;
            end
            focus = view.currentFocus();
            if ~isstruct(focus)
                return;
            end
            if isfield(focus, 'Channel') && ~isempty(strtrim(char(string(focus.Channel))))
                this.ChannelLabel = char(string(focus.Channel));
            end
            if isfield(focus, 'Bin') && ~isempty(strtrim(char(string(focus.Bin))))
                this.BinLabel = char(string(focus.Bin));
            end
        end

        function apply(this, view)
        %APPLY  Ask VIEW to show what was last looked at.
            if isempty(view) || ~isvalid(view) || ~ismethod(view, 'applyFocus')
                return;
            end
            if isempty(this.ChannelLabel) && isempty(this.BinLabel)
                return;
            end
            view.applyFocus(struct('Channel', this.ChannelLabel, 'Bin', this.BinLabel));
        end

        function clear(this)
        %CLEAR  Forget both, so the next view opens on its own default.
            this.ChannelLabel = '';
            this.BinLabel = '';
        end
    end

    methods (Static)
        function idx = indexOfLabel(labels, wanted)
        %INDEXOFLABEL  Where WANTED sits in LABELS, or [] when it is absent.
        %   Case-insensitive and whitespace-trimmed, because channel labels
        %   arrive from several recording systems and "CZ", "Cz" and "Cz "
        %   are the same electrode to everyone except strcmp.
            idx = [];
            if isempty(wanted) || isempty(labels)
                return;
            end
            wanted = strtrim(char(string(wanted)));
            for k = 1:numel(labels)
                if strcmpi(strtrim(char(string(labels{k}))), wanted)
                    idx = k;
                    return;
                end
            end
        end
    end
end
