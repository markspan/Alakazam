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
%       parameters for the Fourier transformation such as:
%       - Resolution : Resolution mode ('Max' or 'Other').
%       - Output : Output format ('Volt', 'Power', 'VoltDens', 'PowerDens') --
%         these exact strings, taken from FourierGui.fig's OutPutRadio button
%         group Tags (get(handles.OutPutRadio,'SelectedObject')'s Tag), not
%         the longer on-screen labels ("Voltage [uV]" etc.) shown next to them.
%       - Interval : Frequency interval for transformation.
%       - Window : Windowing function used ('Hanning', 'Hamming', etc.).
%       - Window_Length : Length of the windowing function in percentage.
%       - ResVal : Resolution value for custom mode.
%       - Complex, FullSpectrum, Normalize, Compression, CompRes : captured
%         from the dialog but currently only FullSpectrum is actually read by
%         this function (fs = 2 below); the others are stored in the returned
%         options (and hence replayed) but have no effect on the computed
%         output -- their dialog controls are not yet wired to any behaviour.
%
%   Notes:
%   ------
%   - If 'opts' is not provided, default options are used for transformation.
%   - Supports windowing functions like Hanning, Hamming, Bartlett, etc.
%   - Computes the Fourier transform for each segment of the input data.
%   - Per-segment normalization ('norm' below) always compares the windowed
%     signal's variance against the unwindowed signal's, unconditionally --
%     this is not what options.Normalize controls (see above).
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

if (nargin == 1)
    options = [];
    options.Name            = 'Fourier';
    options.Resolution      = 'Max';
    options.Output          = 'Volt';
    options.Complex         = 'On';
    options.FullSpectrum    = 'On';
    options.Normalize       = 'On';
    options.Interval        = [0.5 125];
    options.Window          = 'Hanning';
    options.Window_Length   = 100;
    options.Compression     = 'On';
    options.CompRes         = 10;
    options.ResVal          = .333;
    % Seed from the last time Fourier ran in the current workspace
    % (TransformSettings), field by field, so a schema field that a
    % previously-stored value predates still falls back to the literal
    % default above rather than being left missing.
    stored = TransformSettings.get('Fourier');
    if ~isempty(stored)
        storedFields = fieldnames(stored);
        for si = 1:numel(storedFields)
            options.(storedFields{si}) = stored.(storedFields{si});
        end
    end
    options = FourierGui(options);
    TransformSettings.set('Fourier', options);
elseif (nargin == 2)
    options = varargin{2};
end

input = varargin{1};
output = input;

output.DataType = 'FrequencyDomain';
[nchan,nsamp,nseg] = size(input.data);

%% use full spectrum: power * 2;
fs = 1;
if strcmpi(options.FullSpectrum, 'On')
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
        
        if strcmpi(options.Output, 'Volt') % BVA CORRECT
            data(:,:,seg) = fs*(abs(fft((corrwin.*input.data(:,:,seg))',NFFT)/(nsamp)))';
        end
        if strcmpi(options.Output, 'Power')% BVA CORRECT
            data(:,:,seg) = fs*(abs(fft((corrwin.*input.data(:,:,seg))',NFFT)/(nsamp)))' .^2;
        end
        if strcmpi(options.Output, 'VoltDens')% BVA CORRECT
            data(:,:,seg) = fs*(abs(fft((corrwin.*input.data(:,:,seg))',NFFT)/(nsamp)))' ./ (input.srate/NFFT);
        end
        if strcmpi(options.Output, 'PowerDens')% BVA CORRECT
            data(:,:,seg) = fs*((abs(fft((corrwin.*input.data(:,:,seg))',NFFT)/(nsamp)))' .^2) ./ (input.srate/NFFT);
        end
end

output.data = gather(data(:,1:NFFT/2+1,:));
output.pnts = NFFT/2+1;

