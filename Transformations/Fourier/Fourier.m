function [ output, options ] = Fourier( varargin )
%FOURIER Transform input to fourier
%   Detailed explanation goes here


if (nargin == 1)
    options = [];
    options.Name            = 'Fourier';
    options.Resolution      = 'Max';
    options.Output          = 'Voltage';
    options.Complex         = 'On';
    options.FullSpectrum    = 'On';
    options.Normalize       = 'On';
    options.Interval        = [0.5 125];
    options.Window          = 'Hanning';
    options.Window_Length   = 100;
    options.Compression     = 'On';
    options.CompRes         = 10;
    options.ResVal          = .333;
    options = FourierGui(options);
elseif (nargin == 2)
    options = varargin{2};
end

input = varargin{1};
%input.data = gpuArray(double(input.data));
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

if (strcmpi(options.Window, 'No'))
    prev = zeros(sizeofwin,1)+1;
end
if (strcmpi(options.Window, 'Hanning'))
    prev = hanning(sizeofwin);
end
if (strcmpi(options.Window, 'Hamming'))
    prev = hamming(sizeofwin);
end
if (strcmpi(options.Window, 'Bartlett' ))
    prev = bartlett(sizeofwin);
end
if (strcmpi(options.Window, 'BlackmanHarris' ))
    prev = blackmanharris(sizeofwin);
end
if (strcmpi(options.Window, 'BohmanWin' ))
    prev = bohmanwin(sizeofwin);
end
if (strcmpi(options.Window, 'NuttallWin' ))
    prev = nuttallwin(sizeofwin);
end
if (strcmpi(options.Window, 'ParzenWin' ))
    prev = parzenwin(sizeofwin);
end
if (strcmpi(options.Window, 'RectWin' ))
    prev = rectwin(sizeofwin);
end
if (strcmpi(options.Window, 'Triang' ))
    prev = triang(sizeofwin);
end

fullwin = [prev(1:floor(length(prev)/2)); additional; prev(floor(length(prev)/2+1):end)]';
fullwin = fullwin(1:nsamp);

%ERROR!
norm=1;
% the correct way is to define "norm" as the fraction of the *variance* of
% the windowed signal compared to the unwindowed signal
% SO I might need to do this in the loop???

%fullwin = repmat(fullwin ./ norm, nchan,1); 


%--------------------------------------------------------------------------
if (strcmpi(options.Resolution, 'Max'))   
    NFFT = 2^nextpow2(nsamp); 
end
if (strcmpi(options.Resolution, 'Other')) 
    NFFT = 2^nextpow2(floor(input.srate/options.ResVal)); 
end

%data = gpuArray(zeros(nchan, NFFT, nseg));
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

%output.data(chan,:,seg) = gather(output.data(chan,:,seg));
output.data = gather(data(:,1:NFFT/2+1,:));
output.pnts = NFFT/2+1;

