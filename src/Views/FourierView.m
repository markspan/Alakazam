classdef FourierView < handle
%FOURIERVIEW  Keyboard-driven view of a frequency-domain dataset.
%
%   FourierView draws one channel's power spectrum at a time, with the
%   frequency bands shaded (from AlakazamSettings.getBands, user-editable on
%   the Settings dialog's own "Frequency bands" tab -- see drawBands), and
%   steps through channels with the up/down arrow keys -- left/right step
%   the trial/bin, for multi-trial data -- the same interaction model
%   EpochView and AverageView already
%   use for time-domain data. Every one of those steps also has a visible,
%   clickable button (see ZoomPanButtons' own header comment), not just a
%   keyboard/wheel shortcut, so the control is discoverable without having
%   to already know the keyboard convention. Replaces the previous
%   grid-of-every-channel-at-once layout with click-to-drill-into-detail,
%   which needed its own rebuild-in-place machinery (captureSlot/
%   buildOuterGrid) that a single persistent axes, redrawn in place like
%   EpochView/AverageView, does not.
%
%   When the dataset carries EEG.bindesc (Fourier run on already-binned/
%   averaged data: Fourier.m's own `output = input;` start means bindesc
%   survives unchanged, still describing EEG.data's 3rd dimension), the
%   3rd-dimension label shows the actual bin name ("Bin: <name>") instead
%   of a bare "Trial N" -- matching SpectralMeasureView's own binLabel
%   convention (its near-twin, see below), rather than the generic
%   trial-numbering label a genuinely trial-wise (un-binned) dataset falls
%   back to.
%
%   X/y zoom are sliders, not buttons (frequency data commonly needs
%   zooming into a specific band, clamped to [0, srate/2] -- something the
%   generic axtoolbar zoom does not do), styled like SignalView's own
%   zoom/pan/mag rows; a zoom level, once set, survives a channel/trial
%   change instead of resetting (see ZoomPanButtons' own header comment on
%   applyYZoom). Pan and the trial/bin-step and channel-step buttons
%   remain alongside the arrow keys -- see ZoomPanButtons, shared with
%   SpectralMeasureView (its near-twin: same interaction model, same
%   button row, stepping bins there instead of trials). The mouse wheel
%   also steps the channel, same direction as the arrow keys, matching
%   SpectralMeasureView's own onWheel.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, AVERAGEVIEW, SPECTRALMEASUREVIEW,
%   ZOOMPANBUTTONS.

    properties
        % Called (no args) when the user clicks this view's axes or presses
        % a zoom/pan/trial button. Wired by AlakazamPlotter to
        % Alakazam.registerTileClick, so keyboard shortcuts route to
        % whichever tile was last clicked while several are visible at once
        % in Grid/Stack mode -- see Alakazam.dispatchKey and migration.md.
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning figure
        EEG             % frequency-domain dataset (channels x freqs x trials)
        Grid            % 4x1 uigridlayout: axes | buttons | x-zoom | y-zoom (built once, never rebuilt)
        Axes            % the single axes the current channel's spectrum is drawn in
        Buttons         % ZoomPanButtons, the zoom/pan/channel/trial-step row + sliders
        Channel = 1     % channel currently shown
        CurrentTrial = 1
    end

    methods
        function this = FourierView(fig, eeg)
        %FOURIERVIEW  Build the frequency-domain view for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;

            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab.
            this.Grid = uigridlayout(fig, [4 1], "RowHeight", {'1x', 30, 24, 24}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();

            stepFcn = [];
            if size(eeg.data, 3) > 1
                stepFcn = @(delta) this.trialStep(delta);
            end
            channelStepFcn = [];
            if size(eeg.data, 1) > 1
                channelStepFcn = @(delta) this.channelStep(delta);
            end
            if isfield(eeg, 'bindesc') && ~isempty(eeg.bindesc)
                stepLabel = 'Bin';
            else
                stepLabel = 'Trial';
            end
            this.Buttons = ZoomPanButtons(this.Grid, [2 3 4], this.Axes, eeg.srate / 2, ...
                @() this.notifyActivated(), stepFcn, channelStepFcn, stepLabel);
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the current channel's spectrum (current trial/bin, for
        %   multi-trial data), with band shading.
            ax = this.Axes;
            delete(allchild(ax));
            freqs    = this.EEG.freqs;
            spectrum = reshape(this.EEG.data(this.Channel, :, this.CurrentTrial), 1, []);

            hold(ax, "on");
            this.drawBands(ax, freqs, spectrum);
            plot(ax, freqs, spectrum, "Color", "k", "LineWidth", 1);
            hold(ax, "off");

            titleStr = sprintf("Channel %i: %s", this.Channel, this.EEG.chanlocs(this.Channel).labels);
            nseg = size(this.EEG.data, 3);
            if nseg > 1
                % "i of N" alongside the label/number, not just the label
                % alone: with only a label, stepping to a same- or similarly-
                % named neighbour (or a stale figure that never redrew) reads
                % as "nothing happened" -- the count makes a real step
                % unambiguous even when the label text does not obviously
                % change.
                if isfield(this.EEG, 'bindesc') && ~isempty(this.EEG.bindesc)
                    titleStr = sprintf('%s   (Bin %i of %i: %s)', titleStr, ...
                        this.CurrentTrial, nseg, binLabel(this.EEG, this.CurrentTrial));
                else
                    titleStr = sprintf('%s   (Trial %i of %i)', titleStr, this.CurrentTrial, nseg);
                end
            end
            title(ax, titleStr);

            % x-limits are owned by this.Buttons (persists zoom/pan across a
            % channel/trial change); y-limits go through applyYZoom so the
            % y-zoom slider's level, not just the absolute range, survives
            % too -- see ZoomPanButtons' own header comment.
            this.Buttons.applyYZoom(max(spectrum, [], "omitnan"));
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the channel; left/right step the
        %   trial/bin (multi-trial data only). Public (not a private
        %   helper): dispatched by Alakazam.dispatchKey for whichever tab
        %   is currently selected -- see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
                case "leftarrow"
                    this.CurrentTrial = max(1, this.CurrentTrial - 1);
                case "rightarrow"
                    this.CurrentTrial = min(size(this.EEG.data, 3), this.CurrentTrial + 1);
                otherwise
                    return;
            end
            this.redraw();
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll the mouse wheel to step the shown channel -- the
        %   same direction convention as the up/down arrow keys, matching
        %   SpectralMeasureView's own onWheel (its near-twin: both views
        %   share the same interaction model, see the class header
        %   comment). Public: dispatched centrally by
        %   Alakazam.dispatchWheel for whichever tab is currently active.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

        function notifyActivated(this)
        %NOTIFYACTIVATED  Call ActivatedFcn, if set, guarding the usual
        %   empty-function_handle case.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
        function drawBands(~, ax, freqs, spectrum)
        %DRAWBANDS  Shade each frequency band (from AlakazamSettings.getBands,
        %   the "Frequency bands" settings tab) under the spectrum in AX.
        %   Read fresh on every redraw, not cached on this view, so editing
        %   the bands in Settings and saving takes effect immediately (see
        %   onSettingsChanged) without any extra wiring here.
            spectrum = reshape(spectrum, 1, []);
            bands = AlakazamSettings.getBands();
            for b = 1:numel(bands)
                lo = bands(b).loFreq;
                hi = bands(b).hiFreq;
                colour = bands(b).color;
                idx = find(freqs > lo & freqs <= hi);
                if isempty(idx)
                    continue;
                end
                % Frequencies are sorted, so the band is a contiguous range;
                % include the leading edge sample for a clean fill.
                sel = max(1, idx(1) - 1):idx(end);
                area(ax, freqs(sel), spectrum(sel), ...
                    "EdgeColor", "k", "EdgeAlpha", 0.33, "FaceColor", colour);
            end
        end

        function trialStep(this, delta)
        %TRIALSTEP  Move to the previous / next trial or bin and redraw.
            nseg = size(this.EEG.data, 3);
            this.CurrentTrial = min(nseg, max(1, this.CurrentTrial + delta));
            this.redraw();
        end

        function channelStep(this, delta)
        %CHANNELSTEP  Move to the previous / next channel and redraw --
        %   the button-row equivalent of the up/down arrow keys (see
        %   onKey), for the "C^"/"Cv" pair ZoomPanButtons builds when given
        %   a non-empty channelStepFcn.
            nchan = size(this.EEG.data, 1);
            this.Channel = min(nchan, max(1, this.Channel - delta));
            this.redraw();
        end
    end
end

function label = binLabel(EEG, b)
%BINLABEL  EEG.bindesc(b)'s own label, or the bare bin number as a
%   fallback -- identical to SpectralMeasureView's own local binLabel
%   (its near-twin, see this file's own header comment), not
%   src/Support/csvBinLabel.m: that helper deliberately skips the
%   char(string(...)) normalisation this one needs for direct use in a
%   plot title (see csvBinLabel's own header comment on why the two are
%   kept separate).
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
        label = char(string(EEG.bindesc(b).label));
    else
        label = num2str(b);
    end
end
