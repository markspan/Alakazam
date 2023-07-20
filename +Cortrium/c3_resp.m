classdef c3_resp < Cortrium.c3_sensor
    properties
        rate
        smoothened = false;
    end

    properties(Access = private)
        mintab
        maxtab
    end

    methods
        function this = c3_resp(path)
            this.filepath = path;
            this.fs = 250;
        end

        function load_data(this)
            % Read data
            list1 = dir([this.filepath '\*_resp.bin']);
            list2 = dir([this.filepath '\*resp_raw.bin']);
            if size(list1,1) == 1
                fid = fopen(fullfile(this.filepath,list1(1).name),'r');
                [this.data, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
            elseif size(list2,1) == 1
                fid = fopen(fullfile(this.filepath,list2(1).name),'r');
                [this.data, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
            else
                this.data = [];
            end
            this.data(abs(this.data)>32676) = 0;

            this.samplenum = length(this.data);
        end

        function smoothen(this)
            % Filter

            h = fdesign.lowpass('N,Fp,Fst',256,0.5,0.8,this.fs);
            d = design(h,'equiripple');
            %            fvtool(d)
            if ~this.smoothened
                data_raw = this.data; %#ok<NASGU>
            end
            this.data = filtfilt(d.Numerator,1, this.data); %zero-phase filtering


            this.smoothened = true;
        end

        function [maxtab, mintab] = find_peaks(this, section)
            % Find local minima and maxima. Make sure to filter the data
            % beforehand
            [maxtab, mintab] = peakdet(this.data(section), 20);
            this.maxtab = maxtab;
            this.mintab = mintab;
        end

        function calc_rate(this, section, subject_no, manual_count, reading)
            % Calculate breathing rate from peaks in the signal
            if nargin < 2
                section = 1:this.samplenum;
                fprintf('Section not defined, using full length\n');
            end

            data_orig = this.data(section);
            x = 1:length(section);


            %%

            data_medfilt = medfilt1(data_orig); % remove impulse noise

            % Fp = 0.1 Hz (6 bpm) = 0.62831853 rad/sample
            % Fst = 0.7 Hz (42 bpm) = 4.39822971 rad/sample
            h = fdesign.lowpass('N,Fp,Fst',256,1,1.5,this.fs);
            d = design(h,'equiripple');
            %data_lowpass = filtfilt(d.Numerator,1, data);

            data_medfilt_lowpass = filtfilt(d.Numerator,1, data_medfilt);

            Fstop1 = 0.01;  % First Stopband Frequency
            Fpass1 = 0.1;   % First Passband Frequency
            Fpass2 = 0.7;   % Second Passband Frequency
            Fstop2 = 0.9;  % Second Stopband Frequency
            Astop1 = 60;    % First Stopband Attenuation (dB)
            Apass  = 1;     % Passband Ripple (dB)
            Astop2 = 60;    % Second Stopband Attenuation (dB)

            h_bo = fdesign.bandpass('fst1,fp1,fp2,fst2,ast1,ap,ast2', Fstop1, Fpass1, ...
                Fpass2, Fstop2, Astop1, Apass, Astop2);
            Hd_bp = design(h_bo, 'equiripple');
            data_bp = filtfilt(Hd_bp.Numerator ,1, data_medfilt);


            close all;
            figure(1); hold on;
            plot(x,data_orig,':',x,data_medfilt,'-.',x,data_medfilt_lowpass,x,data_bp);
            legend('raw data','medfilt','medfilt + lowpass', 'medfilt bandpass');

            data = data_medfilt_lowpass;

            [psor,lsor] = findpeaks(data,'MinPeakHeight',25,...
                'MinPeakDistance',(1.5 * this.fs));
            %[psorinv,lsorinv] = findpeaks(-data,'MinPeakHeight',25,...
            %    'MinPeakDistance',(1.5 * this.fs));

            this.rate = length(lsor)...
                / (length(section)/this.fs/60);


            [obj.maxtab, obj.mintab] = peakdet(data, 20);
            rate_peakdet = round(mean([length(obj.maxtab), length(obj.mintab)]))...
                / (length(data)/this.fs/60);

            plot(obj.mintab(:,1), obj.mintab(:,2)-20,'r^')
            plot(obj.maxtab(:,1), obj.maxtab(:,2)+20,'rv')
            text(obj.maxtab(:,1)-10,obj.maxtab(:,2)+40,num2str((1:numel(obj.maxtab(:,2)))'));


            plot(lsor, psor,'bh')
            text(lsor,psor-20,num2str((1:numel(psor))'),'EdgeColor', 'blue')
            %text(lsorinv+.02,-psorinv,num2str((1:numel(psorinv))'),'EdgeColor', 'red')

            title(sprintf('Respiration subject: %d, Datetime: %s\n Detected rate (findpeaks): %2.1f, (peakdet): %2.1f, manually counted rate: %d', subject_no, reading, this.rate, rate_peakdet, manual_count));
            xlabel(sprintf('Samples (time: %d seconds)', round(length(section)/this.fs)));
            ylabel('Conductivity');
            %%
            saveas(1, sprintf('plots2/resp_%d_%s_rate_%i_man_%i_%d_secs.png', subject_no, reading, round(this.rate), manual_count, round(length(section)/this.fs)), 'png')







            %             while (this.rate > 100)
            %                 this.smoothen;
            %                 this.calc_rate(section, subject_no, reading);
            %                 return;
            %             end

            %fprintf('Subject: %d, Datetime: %s, Respiration rate: %2.1f \n', subject_no, reading, this.rate);
            fprintf('%2.1f,', this.rate);
        end

        function calc_0_xing(this, section, ~, ~)
            % Calculate breathing rate from peaks in the signal
            if nargin < 2
                section = 1:this.samplenum;
                fprintf('Section not defined, using full length\n');
            end

            Hzerocross = dsp.ZeroCrossingDetector;
            data_normalized = this.data(section)-median(this.data(section));
            figure; plot(data_normalized);
            NumZeroCross = step(Hzerocross,data_normalized);
            this.rate = NumZeroCross...
                / (length(section)/this.fs/60)/2;
            fprintf('%2.1f,', this.rate);

        end


        function show_peaks(this, section, subject_no, manual_count, reading)
            if nargin < 2
                section = 1:this.samplenum;
                fprintf('Section not defined, using full length\n');
            end

            % Find peaks for section of data
            this.find_peaks(section);

            %Plot
            close all;
            figure(1), hold on
            title(sprintf('Respiration subject: %d, Datetime: %s\n Detected rate: %2.1f, manually counted rate: %d', subject_no, reading, this.rate, manual_count));
            plot(this.data(section));
            plot(this.mintab(:,1), this.mintab(:,2),'r*')
            plot(this.maxtab(:,1), this.maxtab(:,2),'r*')
            xlabel(sprintf('Samples (time: %d seconds)', round(length(section)/this.fs)));
            ylabel('Conductivity');
            saveas(1, sprintf('plots/resp_%d_%s_rate_%i_man_%i_%d_secs.png', subject_no, reading, round(this.rate), manual_count, round(length(section)/this.fs)), 'png')

        end
    end
end