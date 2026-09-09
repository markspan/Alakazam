classdef FakeFocusView < AlakazamView
%FAKEFOCUSVIEW  A view that reports a fixed focus, for ViewFocusTest.
%   Only the two focus methods are real and nothing is drawn. It exists so
%   the memory's own merging rules can be tested without opening a figure
%   for each case, which is the slow part of any UI test.
    properties
        Channel = ''
        Bin     = ''
        Applied = []    % the last focus applyFocus was handed, [] if never
    end

    methods
        function this = FakeFocusView(channel, bin)
            this.Channel = channel;
            this.Bin = bin;
        end

        function focus = currentFocus(this)
            focus = struct();
            if ~isempty(this.Channel)
                focus.Channel = this.Channel;
            end
            if ~isempty(this.Bin)
                focus.Bin = this.Bin;
            end
        end

        function applyFocus(this, focus)
            this.Applied = focus;
        end
    end
end
