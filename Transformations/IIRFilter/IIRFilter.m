function [output, options] = IIRFilter(varargin)
%%
%
% Filter with interface
%
%%

GUICALL = ['IIRFilterApp(varargin{1});'];
varargin{1}.srate = round(varargin{1}.srate);
if (nargin == 1)
    options = TransTools.CheckOptions(GUICALL,'Alakazam:IIRFilter', varargin{1});
else
    options = varargin{2};
end
input = varargin{1};
%input.data = gpuArray(double(input.data));
input.data = double(input.data);
output = input;

%%
%   Generic Filter:
%
%
%%
if strcmp(options.useTable, 'Off')
    %%
    %   Global Filter: Low CutOff
    %
    %%
    if options.LCenabled
        [b,a] = TransTools.CreateFilter('low', input.srate, options.LCF, options.LCslope);
        [nchan,~, nseg] = size(input.data);
        TransTools.progressbar;
        for seg = 1:nseg
            for chan = 1:nchan
                TransTools.progressbar(chan/nchan);
                drawnow;
                output.data(chan,:,seg)=Tools.filtfilt(b,a,output.data(chan,:,seg));
            end
        end
    end
    %%
    %   Global Filter: High CutOff
    %
    %
    %%
    if options.HCenabled
        [b,a] = TransTools.CreateFilter('high', input.srate, options.HCF, options.HCslope);
        [nchan,~, nseg] = size(input.data);
        TransTools.progressbar;
        for seg = 1:nseg
            for chan = 1:nchan
                TransTools.progressbar(chan/nchan);
                drawnow;
                output.data(chan,:,seg)=Tools.filtfilt(b,a,output.data(chan,:,seg));
            end
        end
    end
    %%
    % Global Filter: Notch (TODO)
    %
    %%
else % Individual channel Setting:
    %%
    %  Individual: Low Cutoff
    %
    %%
    [nchan,~, nseg] = size(input.data);
    TransTools.progressbar;
    for seg = 1:nseg
        for chan = 1:nchan
            if options.TableData.LCSelected(chan)
                [b,a] = TransTools.CreateFilter('low', input.srate, options.TableData.LCFreqValues(chan), str2double(char(options.TableData.LCSlopeValues(chan))));
                TransTools.progressbar(chan/nchan);
                drawnow;
                output.data(chan,:,seg)=Tools.filtfilt(b,a,output.data(chan,:,seg));
            end
            if options.TableData.HCSelected(chan)
                [b,a] = TransTools.CreateFilter('high', input.srate, options.TableData.HCFreqValues(chan), str2double(char(options.TableData.HCSlopeValues(chan))));
                TransTools.progressbar(chan/nchan);
                drawnow;
                output.data(chan,:,seg)=Tools.filtfilt(b,a,output.data(chan,:,seg));
            end
        end
    end
end

output.data = gather(output.data);

%%
%   do the same on the Polardata if availeable
%
%
%%
if isfield(input, 'Polarchannels')
    output.Polarchannels.data = double(output.Polarchannels.data)
    sr = (output.times(end)- output.times(1) / length(output.Polarchannels.times));
    if strcmp(options.useTable, 'Off')
        %%
        %   Global Filter: Low CutOff
        %
        %%
        if options.LCenabled
            [b,a] = TransTools.CreateFilter('low', 130, options.LCF, options.LCslope);
            [nchan,~, nseg] = size(input.Polarchannels.data);
            TransTools.progressbar;
            for seg = 1:nseg
                for chan = 1:nchan
                    TransTools.progressbar(chan/nchan);
                    drawnow;
                    output.Polarchannels.data(chan,:,seg)=Tools.filtfilt(b,a,output.Polarchannels.data(chan,:,seg));
                end
            end
        end
        %%
        %   Global Filter: High CutOff
        %
        %
        %%
        if options.HCenabled
            [b,a] = TransTools.CreateFilter('high', 130, options.HCF, options.HCslope);
            [nchan,~, nseg] = size(input.Polarchannels.data);
            TransTools.progressbar;
            for seg = 1:nseg
                for chan = 1:nchan
                    TransTools.progressbar(chan/nchan);
                    drawnow;
                    output.Polarchannels.data(chan,:,seg)=Tools.filtfilt(b,a,output.Polarchannels.data(chan,:,seg));
                end
            end
        end
        %%
        % Global Filter: Notch (TODO)
        %
        %%
    else % Individual channel Setting:
        %%
        %  Individual: Low Cutoff
        %
        %%
        [nchan,~, nseg] = size(input.data);
        TransTools.progressbar;
        for seg = 1:nseg
            for chan = 1:nchan
                if options.TableData.LCSelected(chan)
                    [b,a] = TransTools.CreateFilter('low', 130, options.TableData.LCFreqValues(chan), str2double(char(options.TableData.LCSlopeValues(chan))));
                    TransTools.progressbar(chan/nchan);
                    drawnow;
                    output.Polarchannels.data(chan,:,seg)=Tools.filtfilt(b,a,output.Polarchannels.data(chan,:,seg));
                end
                if options.TableData.HCSelected(chan)
                    [b,a] = TransTools.CreateFilter('high', 130, options.TableData.HCFreqValues(chan), str2double(char(options.TableData.HCSlopeValues(chan))));
                    TransTools.progressbar(chan/nchan);
                    drawnow;
                    output.Polarchannels.data(chan,:,seg)=Tools.filtfilt(b,a,output.Polarchannels.data(chan,:,seg));
                end
            end
        end
    end
    output.Polarchannels.data = gather(output.Polarchannels.data);
end
