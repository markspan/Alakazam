classdef (Abstract) AlakazamView < handle
%ALAKAZAMVIEW  What every plot view in the app has in common.
%
%   Each view class (AverageView, EpochView, Brain3DView, ...) owns one
%   plot tab: it builds its own axes, draws its own data, and handles its
%   own interaction. This holds the one piece they genuinely share.
%
%   ACTIVATION, AND WHY IT IS HERE. A view tells the app when the user has
%   interacted with it, so the app can front that tab and treat it as the
%   current one. Every view did this identically:
%
%       ActivatedFcn = function_handle.empty
%       function notifyActivated(this)
%           if ~isempty(this.ActivatedFcn)
%               this.ActivatedFcn();
%           end
%       end
%
%   Ten copies, byte for byte, plus the property in twelve. A view that
%   forgot the empty check would throw on a tab nobody had wired up, and a
%   view that forgot the property would not front at all -- both silent
%   until somebody clicked the right tab. One definition removes the
%   possibility.
%
%   DELIBERATELY SMALL. It is tempting to hoist redraw, onWheel and
%   onBinChanged as well, since most views have them: resist that. Their
%   bodies genuinely differ -- onWheel steps channels in one view, bins in
%   another, and does nothing in a third -- and their signatures are not
%   uniform. Declaring abstract methods that most subclasses implement
%   differently and some do not implement at all would impose a contract
%   the views do not actually share, which is a worse problem than the
%   repetition it would remove. This class asserts only what is true of
%   every view.
%
%   Handle-derived, since a view is an object the app holds and mutates
%   rather than a value it copies.
%
%   See also AVERAGEVIEW, EPOCHVIEW, BRAIN3DVIEW, ALAKAZAMPLOTTER.

    properties
        % Called when the user interacts with this view, so the app can make
        % its tab current. Empty until the app wires it, which is the normal
        % state for a view built but not yet shown.
        ActivatedFcn = function_handle.empty
    end

    methods
        function notifyActivated(this)
        %NOTIFYACTIVATED  Call ActivatedFcn, if set, guarding the usual
        %   empty-function_handle case.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end
end
