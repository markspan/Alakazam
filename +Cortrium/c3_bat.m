classdef c3_bat < Cortrium.c3_sensor
    properties
        dates
    end
    methods
        function this = c3_bat(path)
            this.filepath = path;
        end
        
        function load_data(this)
            %% Read in 'bat_adc.txt' and extract date and time of recording
            if exist(fullfile(this.filepath,'bat_adc.txt'), 'file') == 2
                fid = fopen(fullfile(this.filepath,'bat_adc.txt'),'r');
                readout = textscan(fid,'%s','delimiter',';');
                fclose(fid);

                idx = 0;
                for i = 1:3:length(readout{1})
                    idx = idx + 1;
                    this.dates{idx} = readout{1}{i};
                    this.data(idx) = str2double(readout{1}{i+1});
                end                
            else
                this.data = [];
            end
            this.samplenum = length(this.data);            
        end
        
        function datenum_start = find_date(this)
            % Create MATLAB datenum
            % datenums are the number of days since 0/0/0000, expressed as a double
            % (double precision numbers are precise to about 14 usec for contemporary
            % dates).
            if exist(fullfile(this.filepath,'bat_adc.txt'), 'file') == 2
                if ~isempty(this.dates)
                    this.load_data;
                end
                formatIn = 'yyyy-mm-dd HH.MM.SS';
                datenum_start = datenum(this.dates{1}, formatIn);
            else
                % if no bat_adc file exist we will have to get our info elsewhere
                % get the BLE file name
                listBLE = dir([this.filepath '\*.BLE']);
                if size(listBLE,1) == 1
                    [~,filename_wo_extension,~] = fileparts([this.filepath filesep listBLE(1).name]);
                    datenum_start = datenum(datetime(hex2dec(filename_wo_extension), 'ConvertFrom', 'posixtime', 'TimeZone', 'local'));
                else
                    datenum_start = 0;
                end
            end
        end
    end    
end