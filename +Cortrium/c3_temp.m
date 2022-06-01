classdef c3_temp < Cortrium.c3_sensor
   
    methods
        function this = c3_temp(path)
            % Initialise object
            this.filepath = path;
            this.fs = 25;
        end
        
        function load_data(this)
            % Read in temperature data. Two channels with target and
            % ambient temperature
            % Format is signed 16 bit integer with 25 samples per second
            list1 = dir([this.filepath '\*_temp_*.bin']);
            list2 = dir([this.filepath '\temp.bin']);
            if size(list1,1) == 2
                fid = fopen(fullfile(this.filepath,list1(1).name),'r');
                [tmp_data_1, ~] = fread(fid, [1, inf], 'int16');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list1(2).name),'r');
                [tmp_data_2, ~] = fread(fid, [1, inf], 'int16');
                fclose(fid);
                tmp_data = [tmp_data_1;tmp_data_2];
            elseif size(list2,1) == 1
                fid = fopen(fullfile(this.filepath,'temp.bin'),'r');
                [tmp_data, ~] = fread(fid, [2, inf], 'int16');
                fclose(fid);
            else
                tmp_data = [];
            end
%             fid = fopen(fullfile(this.filepath,'temp.bin'),'r');
%             [tmp_data, tmp_samples] = fread(fid, [2, Inf], 'int16');
%             fclose(fid);
            this.data = tmp_data' * 0.02 - 273.15;
            this.samplenum = length(this.data);
        end
    end
    
end