classdef ECG < handle
    
    properties (SetAccess = private)       
        %General
        name 
        BPMglobal {isnumeric}
        BPMlocal {isnumeric}
        len {isnumeric}
        Fs {isnumeric}
        signal {ismatrix}        
        %Numerics
        SDNN {isnumeric}
        rmsRR {isnumeric}
        NN50 {isnumeric}
        pNN50 {isnumeric}
        IBImean {isnumeric}
        IBIrange {ismatrix}
        %Poincare Map
        SD1 {isnumeric}
        SD2 {isnumeric}
        S_area {isnumeric}
        %Power Values
        lfPower {isnumeric}
        hfPower {isnumeric}
        lowFreqHighFreqRatio {isnumeric}
        TotPower {isnumeric}
        LFperc {isnumeric}
        HFperc {isnumeric}
        %Segments
        SegmentCount {isnumeric}
        SegmentLength {isnumeric}
        Segments {ismatrix}
    end
    
    properties (Access = private)
        %General
        timeVal {ismatrix}
        pks {ismatrix}
        locs {ismatrix}
        %HRV
        rr {ismatrix}
        pkTimes {ismatrix}
        rrA {ismatrix} %Backup
        pkTimesA {ismatrix} %Backup
        reject {ismatrix}
        HRV_R {ismatrix} %Resampled RR
        tHRV {ismatrix}
        LHRV {isnumeric}
        FsHRV {isnumeric}
        %Freq Analysis
        fftHRV {ismatrix}
        p1 {ismatrix}
        %Freq Bands Analsysis
        hf {ismatrix}
        p1HF {ismatrix}
        lf {ismatrix}
        p1LF {ismatrix}
        %Segments
        segmentBoundaries {ismatrix}
    end
    
    methods 
        %% General Calculation
        function obj = ECG(ECGSignal,SamplingFrequency,Name)
            %Constructor, (Supply Signal and Initial Sampling Frequency)
            %Creates ECG class with many methods for analysis
            
            if nargin >= 2
                obj.signal=ECGSignal;
                obj.Fs=SamplingFrequency;
                
                obj.len = length(obj.signal);
                T = 1/obj.Fs;
                obj.timeVal = (0:obj.len-1)'*T;
                
                obj.name='ECG';
            end
            
            if nargin == 3
                obj.name = Name;
            end

        end
        
        function init(obj,varargin)
            % Eliminates Offset, Detrends, Detects Peaks, Gets RR data and
            % filters it
            % Paramters are:
            % Disabling sections: 'offSetElim', 'deTrend'
            % Rejection: 'rejectPlot', 'STDscalar'
            % Peak Detect: 'MinPeakProminence','MinPeakHeight','MinPeakDistance'
            % Detrending: 'ORD', 'FL'
            
            p = inputParser;
            p.KeepUnmatched = true;
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            addParameter(p,'offSetElim','on',checkPlot)
            addParameter(p,'deTrend','on',checkPlot)
            parse(p,varargin{:});
            
            if strcmpi(p.Results.offSetElim,'on')
                obj.offsetEliminate
            end
            if strcmpi(p.Results.deTrend,'on')
                obj.deTrending(varargin{:})
            end
            obj.peakDetect(varargin{:})
            obj.variabilityReject(varargin{:})
            obj.calculateHRVNumerics
            obj.resampleHRV
            obj.freqAnalysisHRV
        end
        
        function resample(obj,FsR,varargin)
            % Resamples the ECG at a given resampling frequency
            % Parameters are Plot (on/off), ylim, xlim
            TR = 1/FsR;
            p = inputParser;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            addParameter(p,'ResamplePlot','off',checkPlot)
            addParameter(p,'xlim',[0, max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal)*1.2, max(obj.signal)],validLim)
            parse(p,varargin{:});
            
            if (strcmp(p.Results.ResamplePlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','m')
                hold on
            end
            
            obj.signal = resample(obj.signal,FsR,obj.Fs,FsR);
            obj.len = length(obj.signal);
            
            obj.timeVal = (0:obj.len-1)*TR;
            
            if (strcmp(p.Results.ResamplePlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','k')
                legend(['Original ECG, sampled at ',num2str(obj.Fs),' Hz'],...
                       ['Resampled ECG at ',num2str(FsR),' Hz'])
                hold off
                
            end
            
            obj.Fs = FsR;
        end
        
        function trim(obj,range,varargin)
            %Trims ECG signal outside a given range (seconds)
            %Params are TrimPlot, trimColour, sigColour, xlim, ylim
            
            p = inputParser;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmpi(x,'on') || strcmpi(x,'off'));
            addParameter(p,'TrimPlot','off',checkPlot)
            addParameter(p,'trimColour',[0.2471, 0.2627, 0.2784, 0.15])
            addParameter(p,'sigColour',[0, 0.3569, 0.6588])
            addParameter(p,'xlim',[0, max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal)*1.2, max(obj.signal)],validLim)
            parse(p,varargin{:});
            
            
            
            cuttings = find(obj.timeVal > max(range) | obj.timeVal < min(range));
            
            if strcmpi(p.Results.TrimPlot,'on')
                obj.plot('Colour',p.Results.trimColour)
                hold on
            end
            maxT = max(obj.timeVal);
            
            
            obj.signal(cuttings) = [];
            obj.timeVal(cuttings) = [];
            obj.len = length(obj.signal);
            
            if strcmpi(p.Results.TrimPlot,'on')               
                obj.plot('Colour',p.Results.sigColour,'xlim',[0 maxT])
                hold off
            end
            
        end
        
        function resetTimeVal (obj)
            %Resets time values to start at 0s, following trimming or
            %segmentation
            offset = min(obj.timeVal);
            obj.timeVal = obj.timeVal - offset;
            
        end
        
        function offsetEliminate(obj)
            %Eliminates any offsets in ECG signal
            offset = mean(obj.signal);
            obj.signal = obj.signal - offset;
        end
        
        function deTrending(obj,varargin)
            %Removes trend
            %input ORD (order) and FL (Float length)
            p = inputParser;
            p.KeepUnmatched = true;
            addParameter(p,'ORD',3)
            addParameter(p,'FL',9999)
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            addParameter(p,'trendPlot','off',checkPlot)
            addParameter(p,'xlim',[0, max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal), max(obj.signal)],validLim)
            
            parse(p,varargin{:});
            
            if (strcmp(p.Results.trendPlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','m')
                hold on
            end
            
            trend = sgolayfilt(obj.signal, p.Results.ORD, p.Results.FL);
            obj.signal = obj.signal-trend;
            
            if (strcmp(p.Results.trendPlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','b')                
                plot(obj.timeVal,trend,'k')
                xlim(p.Results.xlim)
                ylim(p.Results.ylim)
                hold off
            end
        end
        
        function filter(obj,SecondOrderSection,Gain,varargin)
            % Filters the signal using a supplied SecondOrderSection and
            % Gain
            % Parameters are: FiltPlot,fftPlot, xlim and ylim
            p = inputParser;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            addParameter(p,'filtPlot','off',checkPlot)
            addParameter(p,'fftPlot','off',checkPlot)
            addParameter(p,'xlim',[0, max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal)*1.2, max(obj.signal)],validLim)
            parse(p,varargin{:});
            
            signalTemp = obj.signal;
            
            if (strcmp(p.Results.fftPlot,'on'))
                obj.plotSignalFFT('Colour','m','ylim',p.Results.ylim)
                hold on
            end
            
            if (strcmp(p.Results.filtPlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','m')
                hold on
            end
            
            obj.signal = filtfilt(SecondOrderSection,Gain,obj.signal);
            
            if (strcmp(p.Results.filtPlot,'on'))
                obj.plot('xlim',p.Results.xlim,'ylim',p.Results.ylim,'Colour','k')
                legend('Unfiltered ECG','Filtered ECG')
                hold off
            end  
            
            if (strcmp(p.Results.fftPlot,'on'))
                obj.plotSignalFFT('Colour','k','ylim',p.Results.ylim)
                legend('Unfiltered Signal','Filtered Signal')
                hold off
            end
            
        end
        
        function peakDetect(obj,varargin)
            % Finds Peaks of ECG, enter parameter pair values of
            % MinPeakProminence, MinPeakDistance, MinPeakHeight
            p = inputParser;
            p.KeepUnmatched = true;
            addParameter(p,'MinPeakProminence',0.1)
            addParameter(p,'MinPeakDistance',0.4)
            addParameter(p,'MinPeakHeight',0.5)
            
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            addParameter(p,'peakDetectPlot','off',checkPlot)
            addParameter(p,'xlim',[0, max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal), max(obj.signal)],validLim)
            
            parse(p,varargin{:});
            
            PP=p.Results.MinPeakProminence;
            PD=p.Results.MinPeakDistance;
            PH=p.Results.MinPeakHeight;
            
            [obj.pks,obj.locs] = findpeaks(obj.signal,obj.timeVal,'MinPeakProminence',PP,...
                'MinPeakDistance',PD,'MinPeakHeight',PH);
            
            if (strcmp(p.Results.peakDetectPlot,'on'))
            plot(obj.timeVal,obj.signal,'k',obj.locs,obj.pks,'rd')
            xlim(p.Results.xlim)
            ylim(p.Results.ylim)
            grid on
            end
            
            
            obj.BPMglobal = length(obj.locs)*100*60/obj.len;
            obj.rr = diff(obj.locs);
            obj.pkTimes = obj.locs(1:end-1);
            obj.BPMlocal = 60/mean(obj.rr);
        end
        
        function variabilityReject(obj,varargin)
            % Rejects all noise from RR-Interval data
            % Input args are 'rejectplot','on'/'off' or 'STDscalar',(value)
            
            p = inputParser;
            p.KeepUnmatched = true;
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            checkScalar = @(x) (isnumeric(x) && x > 0 && x < 4);
            addParameter(p,'RejectPlot','off',checkPlot)
            addParameter(p,'STDscalar',1.96,checkScalar)
            addParameter(p,'Reject','on',checkPlot)
            parse(p,varargin{:});
            
            if (strcmp(p.Results.Reject,'on'))
                
                pkMean = mean(obj.rr);
                pk2STD = std(obj.rr) * p.Results.STDscalar;
                rejectMax = pkMean + pk2STD;
                rejectMin = pkMean - pk2STD;
                
                ArrReject = find((obj.rr > rejectMax) | (obj.rr < rejectMin));
                
                if (strcmp(p.Results.RejectPlot,'on'))
                    
                    obj.reject = zeros(length(ArrReject),2);
                    
                    for i = 1:length(ArrReject)
                        obj.reject(i,1) = obj.rr(ArrReject(i));
                        obj.reject(i,2) = obj.pkTimes(ArrReject(i));
                    end
                    
                    plot(obj.pkTimes,obj.rr,'b'), hold on
                    scatter(obj.reject(:,2),obj.reject(:,1),'ro')
                    yline(rejectMax,'--r')
                    yline(rejectMin,'--r')
                    ylabel('RR Intervals(s)')
                    xlabel('Time (s)')
                    title('RR Interval Series Showing Rejected Points')
                    hold off
                    
                end
                
                obj.rrA=obj.rr;
                obj.pkTimesA=obj.pkTimes;
                obj.rr(ArrReject) = [];
                obj.pkTimes(ArrReject) = [];
                
                obj.BPMlocal = 60/mean(obj.rr);
                
            end
        end
        
        function resetRR(obj)
            obj.rr=obj.rrA;
            obj.pkTimes=obj.pkTimesA;
            obj.BPMglobal = mean(obj.rr)*60;
        end
        
        function calculateHRVNumerics(obj)
            % Calculates SDNN, RMSSD, NN50, and pNN50 values
            differences = diff(obj.rr);
            obj.SDNN = std(obj.rr*1000);
            obj.rmsRR = sqrt(mean(differences.^2))*1000;
            
            obj.NN50 = 0;
            
            for i = 1:length(differences)
                if (abs(differences(i)*1000) > 50)
                    obj.NN50 = obj.NN50 + 1;
                end
            end
            
            obj.pNN50 = obj.NN50*100 / length(differences);
            
            % Poincare Map
            
            pmX = obj.rr*1000;
            pmX(end)=[];
            
            pmY = obj.rr*1000;
            pmY(1)=[];
            
            obj.SD1 = std(pmX - pmY);
            obj.SD2 = std(pmX + pmY);
            
            % Beat Interval
            obj.IBImean = mean(obj.rr*1000);
            obj.IBIrange = [max(obj.rr*1000) min(obj.rr*1000)];
        end
        
        function resampleHRV(obj,FsHRV)
            if nargin < 2 || isempty(FsHRV)
                obj.FsHRV = 4;
            else
                obj.FsHRV = FsHRV;
            end
            
            THRV = 1/obj.FsHRV;
            obj.HRV_R = resample(obj.rr,obj.pkTimes,obj.FsHRV);
            obj.LHRV = length(obj.HRV_R);
            obj.tHRV = (0:obj.LHRV-1)'*THRV;
        end
        
        function freqAnalysisHRV(obj)
            % Analyses High, Low and Total Freqeuncy and Power of RR
            % interval series
            warning('off','MATLAB:colon:nonIntegerIndex')
            yF = fft(obj.HRV_R);
            p2 = abs(yF/obj.LHRV);
            obj.p1 = p2(1 : obj.LHRV/2 + 1);
            obj.p1(2 : end-1) = 2 * obj.p1(2 : end-1);
            
            obj.fftHRV = obj.FsHRV * (0 : (obj.LHRV/2)) / obj.LHRV;
            
            % LF
            
            NOTlf = find(obj.fftHRV < 0.04 | obj.fftHRV > 0.15);
            obj.lf = obj.fftHRV;
            obj.lf(NOTlf) = [];
            
            obj.p1LF = obj.p1;
            obj.p1LF(NOTlf) = [];
            
            obj.lfPower = sum(obj.p1LF)*1000;
            % HF
            
            NOThf = find((obj.fftHRV > 0.4) | obj.fftHRV < max(obj.lf)); %| obj.fftHRV < 0.15);
            obj.hf = obj.fftHRV;
            obj.hf(NOThf) = [];
            
            obj.p1HF = obj.p1;
            obj.p1HF(NOThf) = [];
            
            obj.hfPower = sum(obj.p1HF)*1000;
            
            obj.lowFreqHighFreqRatio = obj.lfPower/obj.hfPower;
            obj.TotPower = obj.lfPower + obj.hfPower;
            obj.LFperc = obj.lfPower*100/(obj.lfPower + obj.hfPower);
            obj.HFperc = 100-obj.LFperc;
            warning('on','MATLAB:colon:nonIntegerIndex')
        end
        
        function rename(obj,newName)
            
            obj.name = newName;
        
        end
        
        %% Plots and Data Return
        
        function plot(obj,varargin)
            % Plots signal from 0 to end by default, inputs arguements are
            % ylim, xlim, and color
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            
            addParameter(p,'xlim',[min(obj.timeVal), max(obj.timeVal)],validLim)
            addParameter(p,'ylim',[min(obj.signal), max(obj.signal)],validLim)
            addParameter(p,'Colour','k')
            addParameter(p,'ShowSegments','off',checkPlot)
            parse(p,varargin{:});
            
            plot(obj.timeVal,obj.signal,'Color',p.Results.Colour)
            xlim(p.Results.xlim)
            ylim(p.Results.ylim)
            xlabel('Time (s)')
            ylabel('Amplitude (V)')
            title(['ECG Signal of ',obj.name])
            grid on
            
            if strcmpi(p.Results.ShowSegments,'on')
                obj.plotSegmentTimes
            end
            
        end
        
        function plotRRinterval(obj,varargin)
            % Plots RR interval series of ECG, parameters are:
            % ylim, xlim and Colour
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            addParameter(p,'xlim',[min(obj.pkTimes) max(obj.pkTimes)],validLim)
            addParameter(p,'ylim',[min(obj.rr)-0.02 max(obj.rr)+0.02],validLim)
            addParameter(p,'Colour','b')
            parse(p,varargin{:});
            
            plot(obj.pkTimes,obj.rr,'Color',p.Results.Colour)
            xlim(p.Results.xlim)
            ylim(p.Results.ylim)
            grid on
            xlabel('Time (s)')
            ylabel('RR Interval (s)')
            title(['RR Interval Series of ',obj.name])
            
        end
        
        function plotRRHisto(obj)
            
            histogram(obj.rr)
            xlabel('RR Interval (s)')
            ylabel('Number of RR Intervals')
            title('RR Interval Histogram')
        end
        
        function dispHRVNumerics(obj)
            disp(['Heartrate from Number of Peaks: ',num2str(obj.BPMglobal),' bpm'])
            disp(['Heartrate from RR intervals: ',num2str(obj.BPMlocal),' bpm'])
            disp(['SDNN: ',num2str(obj.SDNN),' ms'])
            disp(['RMSSD: ',num2str(obj.rmsRR),' ms'])
            disp(['NN50: ',num2str(obj.NN50)])
            disp(['pNN50: ',num2str(obj.pNN50),' %'])
            disp(['SD1: ',num2str(obj.SD1),' ms'])
            disp(['SD2: ',num2str(obj.SD2),' ms'])
            disp(['SD1/SD2: ',num2str(obj.SD1/obj.SD2*100),' %'])
        end
        
        function plotSegmentTimes(obj)
            %Plots lines displaying segment boundaries
            
            yCoord = min(obj.signal)*0.75;
            hold on
            for i = 1:length(obj.segmentBoundaries)-1
                xCoord = obj.segmentBoundaries(i);
                
                xline(xCoord,'--r','LineWidth',2);
                
                txt = ['Seg ',num2str(i),'.'];
                text(yCoord,xCoord,txt,'Color','r')
                
            end
            
            hold off
        end
        
        function plotPoincareMap(obj)
            pmX = obj.rr*1000;
            pmX(end)=[];
            
            pmY = obj.rr*1000;
            pmY(1)=[];
            
            figure;
            plot(pmY,pmX,'.k')
            xlim([0 max(pmX)*1.2])
            ylim([0 max(pmY)*1.2])
            xlabel('RR(n) (ms)')
            ylabel('RR(n+1) (ms)')
            title('Poincaré Map of RR Intervals')
            hold on
            % Ellipse 
            x = mean(pmX);
            y = mean(pmY); %center points
            
            dx = mean(diff(pmX));                                 % Find Mean Differece In ‘x’ Values
            dy = gradient(pmY,dx);                                % Calculate Slope Of Data
            
            angle = rad2deg(atan(mean(dy)));
            points = calculateEllipse(x,y,obj.SD1,obj.SD2,angle);
            plot(points(:,1),points(:,2),'b','LineWidth',1.5), axis equal
            
            obj.S_area = polyarea(points(:,1),points(:,2));
            hold off
        end
        
        function plotHRVFFT(obj,varargin)
            % Plots FFT of RR-intervals, parameters are:
            %FFTxlim, FFTylim, Colour, FaceColour, EdgeColour
            
            p = inputParser;
            p.KeepUnmatched = true;
            checkPlot = @(x) (strcmp(x,'on') || strcmp(x,'off'));
            validUnit = @(x) (strcmpi(x,'ms') || strcmpi(x,'s'));
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            
            addParameter(p,'FFTxlim',[0 max(obj.fftHRV)],validLim)
            addParameter(p,'FFTylim',[0 max(obj.p1LF)*1.75],validLim)
            addParameter(p,'Colour','k')
            addParameter(p,'EdgeColour','k')
            addParameter(p,'ShowFreqBands','off',checkPlot)
            addParameter(p,'Unit','ms',validUnit)
            parse(p,varargin{:});
            
            if (strcmpi(p.Results.Unit,'ms'))
                scale = 1000;
            else
                scale = 1;
            end
            
            area(obj.fftHRV,obj.p1*scale,'FaceColor',p.Results.Colour,'EdgeColor',p.Results.Colour)
            title('Single-sided Amplitude Spectrum of RR-Interval Series')
            xlabel('f (Hz)')
            ylabel(['Amplitude (',p.Results.Unit,'^2 / Hz)'])
            xlim(p.Results.FFTxlim)
            ylim(p.Results.FFTylim*scale)
            xline(0.15,'--r')
            xline(0.4,'--r')
            xline(0.04,'--r')
            
            if (strcmp(p.Results.ShowFreqBands,'on'))
                hold on
                colour = [0, 57, 230]/255;
                obj.plotHFLFfft('FFTxlim',p.Results.FFTxlim,...
                    'FFTylim',p.Results.FFTylim,'LFColour',colour,...
                    'HFEdgeColour','r','LFEdgeColour',colour,...
                    'Unit',p.Results.Unit)
                hold off  
                legend off
            end
            
            
        end
        
        function plotHFLFfft(obj,varargin)
            %Plots High and Low frequency bands of HRV Frequency Analysis
            %Parameters are:
            %FFTxlim, FFTylim, LFColour, LFEdgeColour, HFColour, HFEdgeColour
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            validUnit = @(x) (strcmpi(x,'ms') || strcmpi(x,'s'));
            
            addParameter(p,'FFTxlim',[min(obj.lf) max(obj.hf)],validLim)
            addParameter(p,'FFTylim',[0 max(obj.p1LF)*1.25],validLim)
            addParameter(p,'LFColour','#4DBEEE')
            addParameter(p,'LFEdgeColour','k')
            addParameter(p,'HFColour','r')
            addParameter(p,'HFEdgeColour','k')
            addParameter(p,'Unit','ms',validUnit)
            parse(p,varargin{:});
                       
            if (strcmpi(p.Results.Unit,'ms'))
                scale = 1000;
            else
                scale = 1;
            end
            
            % Plotting LF
            area(obj.lf,obj.p1LF*scale,'FaceColor',p.Results.LFColour,...
                'EdgeColor',p.Results.LFEdgeColour,...
                'DisplayName','Low Frequency Band'), hold on
            % Plotting HF
            area(obj.hf,obj.p1HF*scale,'FaceColor',p.Results.HFColour,...
                'EdgeColor',p.Results.HFEdgeColour,...
                'DisplayName','High Frequency Band'), hold off
            
            title('High and Low Frequency Bands of Amplitude Spectrum')
            xlabel('f (Hz)')
            ylabel(['Amplitude (',p.Results.Unit,'^2 / Hz)'])
            xlim(p.Results.FFTxlim)
            xline(0.15,'--r')
            ylim(p.Results.FFTylim*scale)
            legend('Low Frequency Band','High Frequency Band')
            
        end
        
        function dispPower(obj)
            disp(['Total Power: ',num2str(obj.TotPower),' ms^2'])
            disp(['LF Power: ',num2str(obj.lfPower),' ms^2'])
            disp(['HF Power: ',num2str(obj.hfPower),' ms^2'])
            disp(['LF/HF Ratio: ',num2str(obj.lowFreqHighFreqRatio)])
            disp(['LF|HF: ',num2str(obj.LFperc),' %| ',num2str(obj.HFperc),' %'])
        end
        
        function plotSignalFFT(obj,varargin)
            
            
            y = fft(obj.signal);
            p2 = abs(y/obj.len);
            signalp1 = p2(1 : obj.len/2 + 1);
            signalp1(2 : end-1) = 2 * signalp1(2 : end-1);
            
            f = obj.Fs * (0 : (obj.len/2)) / obj.len;
            
            
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            addParameter(p,'xlim',[0, max(f)],validLim)
            addParameter(p,'ylim',[0, max(signalp1)*1.2],validLim)
            addParameter(p,'Colour','k')
            parse(p,varargin{:});
                    
            
            plot(f,signalp1,'Color',p.Results.Colour)
            title(['Single-sided Amplitude Spectrum of ',obj.name])
            xlabel('f (Hz)')
            ylabel('|Amplitude| (s^2 / Hz)')
            xlim(p.Results.xlim)
            ylim(p.Results.ylim)
        end
        
        %% Segmentation
        function segmentECG(obj,varargin)
            %Splits the ECG object into an array of ECG segments
            %Params are SegNum (Number of segments), SegLen (Length in seconds)
            %Default length is 5 min per segment
            
            clear obj.Segments
            
            p = inputParser;
            defaultLen = 300; %300 Seconds
            defaultNum = ceil(obj.len / (defaultLen*obj.Fs));
            addParameter(p,'SegNum',defaultNum,@isnumeric)
            addParameter(p,'SegLen',defaultLen,@isnumeric)
            parse(p,varargin{:});
            
            segLen = p.Results.SegLen*obj.Fs;
            segNum = p.Results.SegNum;
            
            if segLen ~= defaultLen*obj.Fs && segNum ~= defaultNum %Throwing error if both params are changed                
                eMsg = ('ECG.segmentECG:tooManyArguments - Please Enter only one of SegNum or SegLen');
                error(eMsg)
            elseif segLen ~= defaultLen*obj.Fs %If only length is changed
                segNum = ceil(obj.len/segLen); %Length / SegLength in data points
                
            elseif segNum ~= defaultNum %If only number is changed
                segLen = ceil(obj.len/segNum);
            end
            
            obj.SegmentCount = segNum;
            obj.SegmentLength = segLen;
            
            S = cell(1,segNum); %cell of ECGs
            
            for i = 1:segNum
                
                SegName=['Segment ',num2str(i)];
                
                startVal = (i-1)*segLen+1;
                endVal = startVal+segLen;
                
                if endVal > obj.len
                    segSignal = obj.signal(startVal : end);
                    S{i} = ECG(segSignal,obj.Fs,SegName);
                else
                    segSignal = obj.signal(startVal : endVal);
                    S{i} = ECG(segSignal,obj.Fs,SegName);
                end
                
                S{i}.incrementTimeVal((startVal-1)/obj.Fs)
                
            end
            
            obj.Segments=[S{:}];
            
            segmentBoundary = zeros(1,obj.SegmentCount);
            
            for i = 1:obj.SegmentCount
                segmentBoundary(i) = (obj.Segments(i).timeVal(end));
            end
            
            obj.segmentBoundaries = segmentBoundary;
            
        end
        
        function segmentInit(obj,varargin)
            % Eliminates Offset, Detrends, Detects Peaks, Gets RR data and
            % filters each segment
            % Paramters are:
            % Rejection: 'rejectPlot', 'STDscalar'
            % Peak Detect: 'MinPeakProminence','MinPeakHeight','MinPeakDistance'
            % Detrending: 'ORD', 'FL'   
            for i=1:obj.SegmentCount
                obj.Segments(i).init(varargin{:})
            end
            
        end
        
        %% Segment Plots and Data Return

        function segmentPlotRRinterval(obj,varargin)
            % Plots RR interval series of each segment in one, parameters are:
            % range (select which segments), ylim, xlim and Colour
            
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            
            addParameter(p,'range',[1 obj.SegmentCount],validLim)
            
            parse(p,varargin{:});
            
            minR = min(p.Results.range);
            maxR = max(p.Results.range);
                     
            hold on
         
            for i = minR:maxR
                obj.Segments(i).plotRRinterval(varargin{:})
                
            end
            xlim([min(obj.Segments(minR).timeVal) max(obj.Segments(maxR).timeVal)])
            obj.plotSegmentTimes
            
            hold off
        end
        
        function segmentDispHRVNumerics(obj,varargin)
            %Disp Numerics for each segment in given 'range'
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            
            addParameter(p,'range',[1 obj.SegmentCount],validLim)
            
            parse(p,varargin{:});
            
            minR = min(p.Results.range);
            maxR = max(p.Results.range);
            
            
            for i = minR:maxR
                disp(['====== Segment ',num2str(i),' ======'])
                obj.Segments(i).dispHRVNumerics
            end
        end
        
        function segmentDispPower(obj,varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            
            addParameter(p,'range',[1 obj.SegmentCount],validLim)
            
            parse(p,varargin{:});
            
            minR = min(p.Results.range);
            maxR = max(p.Results.range);
            
            for i = minR:maxR
                disp(['====== Segment ',num2str(i),' ======'])
                obj.Segments(i).dispPower
            end
        end
        
        function segmentDispAllValues(obj,varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            validLim = @(x) (ismatrix(x) && length(x) == 2);
            
            addParameter(p,'range',[1 obj.SegmentCount],validLim)
            
            parse(p,varargin{:});
            
            minR = min(p.Results.range);
            maxR = max(p.Results.range);
            
            for i = minR:maxR
                disp(['====== Segment ',num2str(i),' ======'])
                obj.Segments(i).dispHRVNumerics
                obj.Segments(i).dispPower
            end
        end
    end
    
    methods (Access = private)
        %% Private Methods
        
        function incrementTimeVal(obj,increment)
            
            obj.timeVal = obj.timeVal + increment;
            
        end  
        
        function [X,Y] = calculateEllipse(x, y, a, b, angle, steps)
            %# This functions returns points to draw an ellipse
            %#
            %#  @param x     X coordinate
            %#  @param y     Y coordinate
            %#  @param a     Semimajor axis
            %#  @param b     Semiminor axis
            %#  @param angle Angle of the ellipse (in degrees)
            %#
            
            narginchk(5, 6);
            if nargin<6, steps = 36; end
            
            beta = -angle * (pi / 180);
            sinbeta = sin(beta);
            cosbeta = cos(beta);
            
            alpha = linspace(0, 360, steps)' .* (pi / 180);
            sinalpha = sin(alpha);
            cosalpha = cos(alpha);
            
            X = x + (a * cosalpha * cosbeta - b * sinalpha * sinbeta);
            Y = y + (a * cosalpha * sinbeta + b * sinalpha * cosbeta);
            
            if nargout==1, X = [X Y]; end
        end
        
    end
end