classdef c3_accel < Cortrium.c3_sensor
    
    methods
        function this = c3_accel(path)
            % Initialise object
            this.filepath = path;
            this.fs = 25;
        end
        
        function load_data(this)
            % Read in accelerometer data
            % format is 16 bit signed with 25 samples per second on each axis
            list1 = dir([this.filepath '\*_acc_*.bin']);
            list2 = dir([this.filepath '\accel.bin']);
            if size(list1,1) == 3
                fid = fopen(fullfile(this.filepath,list1(1).name),'r');
                [tmp_data_x, ~] = fread(fid, [1, inf], 'int16'); % NOT FLOAT, IF BIN CAME FROM read_ble.py
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list1(2).name),'r');
                [tmp_data_y, ~] = fread(fid, [1, inf], 'int16');
                fclose(fid);
                fid = fopen(fullfile(this.filepath,list1(3).name),'r');
                [tmp_data_z, ~] = fread(fid, [1, inf], 'int16');
                fclose(fid);
                this.data = [tmp_data_x',tmp_data_y',tmp_data_z'];
                % converting from int16 to float for g-force
                this.data = double(this.data) .* 0.00006103515625;
            elseif size(list2,1) == 1
                fid = fopen(fullfile(this.filepath,'accel.bin'),'r');
                [tmp_data, ~] = fread(fid, [3, inf], 'float');
                fclose(fid);
                this.data = tmp_data';
            end            
            % this.data = tmp_data' * x - y;
            this.samplenum = length(this.data);
        end
    end
    
end