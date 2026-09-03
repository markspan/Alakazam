function [ output, options ] = Fourier( varargin )
%FOURIER Computes Fourier transform of input data with customizable options.
%   [ output, options ] = Fourier( input, opts ) computes the Fourier
%   transform of the input data using various options specified in 'opts'.
%   The function supports several output formats such as voltage, power,
%   voltage density, and power density.
%
%   Input Arguments:
%   ----------------
%   varargin : Can be one of the following:
%       - input : Struct containing data to be transformed.
%       - input, opts : Structs specifying options for transformation.
%
%   Output Arguments:
%   -----------------
%   output : Struct
%       Struct containing the Fourier transformed data.
%       Fields include:
%       - DataType : Type of data (always 'FrequencyDomain').
%       - trials : Number of segments processed.
%       - freqs : Frequencies corresponding to the Fourier transform.
%       - data : Transformed data in the specified format (volt, power, etc.).
%       - pnts : Number of points in the transformed data.
%
%   options : Struct
%       Updated options struct after processing input arguments. Contains
%       the parameters for the Fourier transformation (only these fields are
%       read by the compute; the app-styled TransformOptionsDialog collects
%       exactly this set):
%       - Output : Output format ('Volt', 'Power', 'VoltDens', 'PowerDens').
%       - FullSpectrum : logical; when true the (one-sided) magnitude is
%         doubled (fs = 2 below) to account for the folded negative half.
%       - Window : Windowing function used ('Hanning', 'Hamming', etc.; see
%         TransTools.WindowByName for the full list).
%       - Window_Length : Length of the windowing function in percentage.
%       - Resolution : Resolution mode ('Max' or 'Other').
%       - ResVal : Resolution value (Hz) for the 'Other' mode.
%
%   Notes:
%   ------
%   - If 'opts' is not provided, the dialog is shown to collect them.
%   - Supports windowing functions like Hanning, Hamming, Bartlett, etc.
%   - Computes the Fourier transform for each segment of the input data.
%   - Per-segment normalization ('norm' below) always compares the windowed
%     signal's variance against the unwindowed signal's, unconditionally.
%
%   Example:
%   --------
%   % Create a sample EEG structure
%   EEG.data = randn(4, 100); % 4 channels of random data
%   EEG.srate = 250; % Sampling rate
%
%   % Compute Fourier transform with default options
%   [output, options] = Fourier(EEG);
%
%   See also: fft, TransTools.progressbar
%
%   Author: M.M.Span
%
%   Version: 1.0
%   License: GPLv2 or Newer
%
%   Contact: m.m.span@rug.nl

% Fourier was, historically, the one transformation with no such check --
% a no-argument call fell through both branches below (options never
% assigned) and only failed later, at `input = varargin{1}`, with a raw
% "index exceeds array bounds" instead of the app's usual friendly
% "Problem in <Name>: ..." message every other transformation gives. Now
% goes through the same TransTools.InitGuard every other transformation
% (that takes options at all) uses.
[options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Fourier', varargin{2:end});

if interactive
    % Literal defaults, then seed field by field from the last Fourier run
    % in this workspace (TransformSettings), so a field a stored value
    % predates still falls back to its default rather than being missing.
    defaults = struct('Output', 'Volt', 'FullSpectrum', true, ...
        'Window', 'Hanning', 'Window_Length', 100, ...
        'Resolution', 'Max', 'ResVal', 0.333);
    seed = defaults;
    stored = TransformSettings.get('Fourier');
    if ~isempty(stored)
        f = fieldnames(defaults);
        for si = 1:numel(f)
            if isfield(stored, f{si}) && ~isempty(stored.(f{si}))
                seed.(f{si}) = stored.(f{si});
            end
        end
    end

    outputs     = {'Volt', 'Power', 'VoltDens', 'PowerDens'};
    windows     = {'No', 'Hanning', 'Hamming', 'Bartlett', 'BlackmanHarris', ...
                   'BohmanWin', 'NuttallWin', 'ParzenWin', 'RectWin', 'Triang'};
    resolutions = {'Max', 'Other'};

    options = TransformOptionsDialog( ...
        'title', 'Fourier options', ...
        'Description', ['Windowed FFT of each segment. Choose the output units, ' ...
            'the taper window and the frequency resolution.'], ...
        'separator', 'Output:', ...
        {'Units'; 'Output'}, TransTools.PutFirst(outputs, seed.Output), ...
        {'Full spectrum (x2)'; 'FullSpectrum'}, toLogical(seed.FullSpectrum), ...
        'separator', 'Window:', ...
        {'Taper'; 'Window'}, TransTools.PutFirst(windows, seed.Window), ...
        {'Length (% of segment)'; 'Window_Length'}, seed.Window_Length, ...
        'separator', 'Resolution:', ...
        {'Mode'; 'Resolution'}, TransTools.PutFirst(resolutions, seed.Resolution), ...
        {'Resolution (Hz, "Other" mode)'; 'ResVal'}, seed.ResVal);
    if isempty(options)
        % Cancelled: nothing to persist (leave the remembered settings
        % untouched) and nothing to run -- Alakazam.onTransformation
        % treats an empty EEG as "cancelled", not an error.
        output = [];
        return;
    end
    options.Name = 'Fourier';
    TransformSettings.set('Fourier', options);
end

input = varargin{1};
output = input;

output.DataType = 'FrequencyDomain';
% WHICH QUANTITY THIS IS, recorded on the dataset rather than only in the
% node's stored options. Averaging a spectrum across trials is only
% meaningful for a power quantity: averaging a voltage one is a COHERENT
% average, which cancels everything not phase-locked and yields a quiet,
% entirely plausible spectrum answering a question nobody asked. Average
% cannot warn about that without knowing what it is holding, and a
% downstream transformation should not have to go and read the provenance
% record to find out.
output.FourierOutput = char(string(options.Output));
[nchan,nsamp,nseg] = size(input.data);

%% use full spectrum: power * 2;
fs = 1;
if toLogical(options.FullSpectrum)
    fs = 2;
end
%--------------------------------------------------------------------------
%
% total length of 'fullwin' must match the datalength
sizeofwin  = floor((options.Window_Length/100) * nsamp);
% this is the number of samples the window is unequal to 1. Both begin and
% end. if it is uneven it mus be made even. This is done by adding one.
if (mod(sizeofwin,2)) 
    sizeofwin=sizeofwin+1; 
end
% the number of samples that are 'unchanged' by the window is 'the rest'
additional = zeros(nsamp - sizeofwin,1)+1;

prev = TransTools.WindowByName(options.Window, sizeofwin);

fullwin = [prev(1:floor(length(prev)/2)); additional; prev(floor(length(prev)/2+1):end)]';
fullwin = fullwin(1:nsamp);

%--------------------------------------------------------------------------
if (strcmpi(options.Resolution, 'Max'))   
    NFFT = 2^nextpow2(nsamp); 
end
if (strcmpi(options.Resolution, 'Other')) 
    NFFT = 2^nextpow2(floor(input.srate/options.ResVal)); 
end

data = zeros(nchan, NFFT, nseg);

output.trials = nseg;

TransTools.progressbar;

output.freqs = input.srate/2*linspace(0,1,NFFT/2+1);

for seg = 1:nseg
        TransTools.progressbar(seg/nseg);
        drawnow;
        
        vunw = var(input.data(:,:,seg));
        vwin = var(fullwin.*input.data(:,:,seg));
        norm = vunw/vwin;
        
        corrwin = repmat(fullwin ./ norm, nchan,1);

        % Volt is the base quantity (BVA CORRECT -- verified against
        % BrainVision Analyzer's own output); Power/VoltDens/PowerDens are
        % all a fixed transform of it, so it is computed once per segment
        % and reshaped per Output rather than the same fft() call repeated
        % under four near-identical if-branches (the four used to each
        % independently recompute it, only one of them ever actually
        % running since options.Output is a single fixed string).
        volt = fs*(abs(fft((corrwin.*input.data(:,:,seg))',NFFT)/(nsamp)))';
        switch lower(options.Output)
            case 'volt'
                data(:,:,seg) = volt;
            case 'power'
                data(:,:,seg) = volt .^ 2;
            case 'voltdens'
                data(:,:,seg) = volt ./ (input.srate/NFFT);
            case 'powerdens'
                data(:,:,seg) = (volt .^ 2) ./ (input.srate/NFFT);
        end
end

output.data = gather(data(:,1:NFFT/2+1,:));
output.pnts = NFFT/2+1;

function tf = toLogical(v)
%TOLOGICAL  Coerce a stored FullSpectrum value to logical, tolerating an
%   older 'On'/'Off' string as well as a logical/numeric.
if islogical(v)
    tf = v;
elseif isnumeric(v)
    tf = v ~= 0;
else
    tf = any(strcmpi(char(string(v)), {'on', 'true', 'yes', '1'}));
end
