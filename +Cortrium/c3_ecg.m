classdef c3_ecg < Cortrium.c3_sensor
    properties
        nbchan
        leadoff
    end
    
    methods
        function this = c3_ecg(path)
            this.filepath = path;
            this.fs = 250;
        end
        
        function load_data(this)
            this.data = [];
            list1 = dir([this.filepath '\*ecg*.bin']);
            list2 = dir([this.filepath '\ecg*_raw.bin']);
            % Read data
            if size(list2,1) == 3
                fid = fopen(fullfile(this.filepath,list2(1).name),'r');
                [tmp_data_1, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list2(2).name),'r');
                [tmp_data_2, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list2(3).name),'r');
                [tmp_data_3, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                tmp_data = [tmp_data_1,tmp_data_2,tmp_data_3];
            elseif size(list1,1) == 3
                fid = fopen(fullfile(this.filepath,list1(1).name),'r');
                [tmp_data_1, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list1(2).name),'r');
                [tmp_data_2, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list1(3).name),'r');
                [tmp_data_3, ~] = fread(fid, Inf, 'int16', 0, 'native');
                fclose(fid);
                tmp_data = [tmp_data_1,tmp_data_2,tmp_data_3];
            else
                return;
            end
            this.data = tmp_data;
            %this.data(abs(this.data) > 32764) = NaN;
            this.samplenum = length(this.data);
        end 
    end
end