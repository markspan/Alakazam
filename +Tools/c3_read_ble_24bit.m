% Read BLE files containing Cortrium C3 sensor data (24bit version).
% The file is read as uint8, and then reshaped and typecasted.

% The BLE file contains a sequence of batches.
% Each batch contains up to 4 parts, with 20 bytes in each part.

% Part 1 is mandatory, and is structured like so:
% uint32    serial;     % incremented for every batch. If serial number is 0, then the batch is invalid and all data in the batch are 0.    
% int16     acc_x;
% int16     acc_y;
% int16     acc_z;
% uint16    temp_ambient_object; % temp_ambient and temp_object alternate in every second (modulus 2) batch
% uint8     serial_ADS;
% uint8     eventCounter % incremented when button on C3 is pressed (only since C3 B7 model)
% uint8     bat_level_and_status; % bat_level and bat_status, packed into bitmask
% bit24     resp;       % 24 bit, signed, respiration sample
% int8      leadoff;    % value indicates whether electrodes (leads) have electrical connection or not. leadoff == 0 means all leads are on.
% uint8     conf;       % bitmask indicating gain level, and which (if any) of the RESP, ECG1, ECG2, ECG3 parts appear after Part 1. This configuration never changes within the current BLE file.

% The remaining 3 parts are optional, but if present, each part contains
% a uint16 serial, and 6 samples of 24bit ECG data.

function [serialNumber, conf, serial_ADS, eventCounter, leadoff, acc, temp, resp, ecg, ecg_serials] = c3_read_ble_24bit(ble_fullpath)
    hTic = tic;
    verbose = false;

    serialNumber = []; conf = []; serial_ADS = []; eventCounter = []; leadoff = [];
    acc = []; temp = []; resp = []; ecg = []; ecg1 = []; ecg2 = []; ecg3 = [];
    ecg_serials = []; ecg1_serial = []; ecg2_serial = []; ecg3_serial = [];

    fid = fopen(ble_fullpath,'r');
    fileInfo = dir(ble_fullpath);
    
    fseek(fid, 0, 'bof');
    bleDescription = fread(fid, 6, '*char')';
    idx7Char = fread(fid, 1, '*char')';
    if strcmp('BLE-C3',bleDescription) && char(idx7Char) == char(0)
        hasHeader = true;
    else
        hasHeader = false;
    end
    
    if hasHeader
        fileFormatVersion = fread(fid, 2, '*char')';
        if strcmp('BLE-C3',bleDescription) && strcmp('01',fileFormatVersion)
            fseek(fid, 10, 'bof');
            deviceID = fread(fid, 15, '*char')';
            fseek(fid, 26, 'bof');
            fwVersion = fread(fid, 12, '*char')';
            fseek(fid, 39, 'bof');
            hwVersion = fread(fid, 7, '*char')';
            fseek(fid, 47, 'bof');
            companySpecific = fread(fid, 1, '*uint8')';
            miscOffset = 48;
        elseif strcmp('BLE-C3',bleDescription) && strcmp('02',fileFormatVersion)
            fseek(fid, 10, 'bof');
            deviceID = fread(fid, 15, '*char')';
            fseek(fid, 26, 'bof');
            fwVersion = fread(fid, 12, '*char')';
            fseek(fid, 39, 'bof');
            hwVersion = fread(fid, 7, '*char')';
            fseek(fid, 47, 'bof');
            confFromHeader = fread(fid, 1, '*uint8');
            fseek(fid, 51, 'bof');
            recordingLengthConf = fread(fid, 1, '*uint32');
            fseek(fid, 55, 'bof');
            companySpecific = fread(fid, 1, '*uint8')';
            miscOffset = 56;
        end
        if cast(companySpecific,'logical')
            errordlg('This BLE-file is encrypted! Unable to read.','Error Reading File','modal');
            return;
        end
    else
        miscOffset = 0;
    end
    
    fseek(fid, miscOffset, 'bof');
    % FIND THE FIRST VALID SERIAL AND CONF, i.e. serialNumber is NOT zero
    while ~feof(fid)
        tempSerialNumber = fread(fid, 1, '*uint32');
        % if the 4 bytes just read, is a number > 0 
        % it is assumed that a valid serial number was found
        if tempSerialNumber > 0
            % now get the conf
            fseek(fid, 15, 'cof'); % go to  position for a possible conf
            posForValidConf = ftell(fid);
            conf = fread(fid, 1, '*uint8');
            first_valid_serial = tempSerialNumber;
            break;
        end
        % Go to next position for a possible serial number.
        % (We just read 4 bytes. Now move an additional 16 bytes forward, for a total of 20 bytes)
        fseek(fid, 16, 'cof');
    end
    
    if tempSerialNumber == 0
        return;
    end

    % determine which parts are available in this file
    conf_bin = dec2bin(conf,8); % conf, in binary form
    respAvailable = (conf_bin(end) == '1');
    ecg1Available = (conf_bin(end-1) == '1');
    ecg2Available = (conf_bin(end-2) == '1');
    ecg3Available = (conf_bin(end-3) == '1');
    % dec2hex for debugging purposes
    conf_hex = dec2hex(conf);
    
    numBatches = Inf; % Batches to read. 'Inf' = read all batches
    batchSize = 20 + ((ecg1Available + ecg2Available + ecg3Available) * 20); % how many bytes a batch contains, depends on how many sensor signals were included
    fileSizeMinusHeader = fileInfo.bytes - miscOffset;
    batchesInFile = fileSizeMinusHeader/batchSize;

    if verbose
        % Display info about recording start time and duration, output to console
        [~,ble_name,ble_ext] = fileparts(ble_fullpath);
        LengthOfRecondingInSeconds = batchesInFile/(250/6);
        [h,m,s] = hms(seconds(LengthOfRecondingInSeconds));
        fprintf('\n=================================================================\n');
        fprintf('File: %s\nSize: %d bytes, (%f megabytes)\n', [ble_name,ble_ext], fileInfo.bytes, fileInfo.bytes/1024/1024);
        fprintf('Duration: %02d:%02d:%02.0f (hours:mins:secs)\n',h, m, s);
        fprintf('valid conf assumed at file pos: %d bytes\n',posForValidConf);
        fprintf('Conf DEC: %d     Conf BIN: %s    Conf HEX: %s\n',conf,conf_bin,conf_hex);
        if hasHeader
            fprintf('Header: ');
            fprintf('%s, ',bleDescription);
            fprintf('file ver: %s, ',fileFormatVersion);
            fprintf('deviceID: %s, ',deviceID);
            fprintf('FW ver: %s, ',deblank(fwVersion));
            fprintf('HW ver: %s, ',deblank(hwVersion));
            fprintf('comp. specific: %d\n',companySpecific);
            if strcmp('BLE-C3',bleDescription) && strcmp('02',fileFormatVersion)
                fprintf('confFromHeader DEC: %d     BIN: %s     HEX: %s\n',confFromHeader,dec2bin(confFromHeader,8),dec2hex(confFromHeader));
                fprintf('recordingLengthConf: %d\n',recordingLengthConf);
            end
        end
        fprintf('=================================================================\n');
    end

    % All data (except the header) as UINT8
    filePos = miscOffset;
    fseek(fid, filePos, 'bof');
    uint8data = fread(fid, numBatches, '*uint8');

    % PART 1, MISC, MANDATORY PAYLOAD
    idx = 1;
    % Serial Number for each batch
    serialNumber = zeros(batchesInFile*4,1,'uint8');
    serialNumber(1:4:end) = uint8data(idx:batchSize:end);
    serialNumber(2:4:end) = uint8data(idx+1:batchSize:end);
    serialNumber(3:4:end) = uint8data(idx+2:batchSize:end);
    serialNumber(4:4:end) = uint8data(idx+3:batchSize:end);
    serialNumber = typecast(serialNumber,'uint32');
    % Acceleration
    % Acc X
    acc = zeros(batchesInFile*8,3,'uint8');
    acc(7:8:end,1) = uint8data(idx+4:batchSize:end);
    acc(8:8:end,1) = uint8data(idx+5:batchSize:end);
    % Acc Y
    acc(7:8:end,2) = uint8data(idx+6:batchSize:end);
    acc(8:8:end,2) = uint8data(idx+7:batchSize:end);
    % Acc Z
    acc(7:8:end,3) = uint8data(idx+8:batchSize:end);
    acc(8:8:end,3) = uint8data(idx+9:batchSize:end);
    acc = typecast(reshape(acc,[],1),'int64');
    acc = bitshift(acc,-48);
    acc = reshape(acc,[],3);
    acc = double(acc);
    % Temp
    temp_amb_obj = zeros(batchesInFile*4,1,'uint8');
    temp_amb_obj(1:4:end) =  uint8data(idx+10:batchSize:end);
    temp_amb_obj(2:4:end) =  uint8data(idx+11:batchSize:end);
    temp_amb_obj = typecast(temp_amb_obj,'uint32');
    temp_amb_obj = single(temp_amb_obj);
    % Serial_ADS
    serial_ADS = uint8data(idx+12:batchSize:end);
    % Event counter
    eventCounter = uint8data(idx+13:batchSize:end);
    % Battery level and status (NOT RETURNED IN OUTPUT ARGUMENTS)
%     bat_level_and_status = uint8data(idx+14:batchSize:end);
    if respAvailable
        resp = zeros(batchesInFile*8,1,'uint8');
        resp(6:8:end) =  uint8data(idx+15:batchSize:end);
        resp(7:8:end) =  uint8data(idx+16:batchSize:end);
        resp(8:8:end) =  uint8data(idx+17:batchSize:end);
        resp = typecast(resp,'int64');
        resp = bitshift(resp,-40);
        resp = double(resp);
    end
    % Lead off
    leadoff = uint8data(idx+18:batchSize:end);  
    % Valid conf should not change throughout the file (and is already found)
%     fseek(fid, filePos+19, 'bof'); % rewind
%     conf = fread(fid, numBatches, '*uint8', batchSize-1);
    
    % PART 2, ECG_1
    if ecg1Available
        idx = (ecg1Available * 20) + 3;
        % ALL ECG1 samples, pre-allocate memory equivalent to the final representation as type double
        ecg1 = zeros(8,batchesInFile*6,'uint8');
        % First Sample of ECG1 from each batch
        ecg1(6,1:6:end) = uint8data(idx:batchSize:end);
        ecg1(7,1:6:end) = uint8data(idx+1:batchSize:end);
        ecg1(8,1:6:end) = uint8data(idx+2:batchSize:end);
        % Second Sample of ECG1 from each batch
        ecg1(6,2:6:end) = uint8data(idx+3:batchSize:end);
        ecg1(7,2:6:end) = uint8data(idx+4:batchSize:end);
        ecg1(8,2:6:end) = uint8data(idx+5:batchSize:end);
        % Third Sample of ECG1 from each batch
        ecg1(6,3:6:end) = uint8data(idx+6:batchSize:end);
        ecg1(7,3:6:end) = uint8data(idx+7:batchSize:end);
        ecg1(8,3:6:end) = uint8data(idx+8:batchSize:end);
        % Fourth Sample of ECG1 from each batch
        ecg1(6,4:6:end) = uint8data(idx+9:batchSize:end);
        ecg1(7,4:6:end) = uint8data(idx+10:batchSize:end);
        ecg1(8,4:6:end) = uint8data(idx+11:batchSize:end);
        % Fifth Sample of ECG1 from each batch
        ecg1(6,5:6:end) = uint8data(idx+12:batchSize:end);
        ecg1(7,5:6:end) = uint8data(idx+13:batchSize:end);
        ecg1(8,5:6:end) = uint8data(idx+14:batchSize:end);
        % Sixth Sample of ECG1 from each batch
        ecg1(6,6:6:end) = uint8data(idx+15:batchSize:end);
        ecg1(7,6:6:end) = uint8data(idx+16:batchSize:end);
        ecg1(8,6:6:end) = uint8data(idx+17:batchSize:end);
        % Reshape and typecast
        ecg1 = typecast(reshape(ecg1,[],1),'int64');
        % Bit-shift to get the correct value
        ecg1 = bitshift(ecg1,-40);
        ecg1 = double(ecg1);
    end

    % PART 3, ECG_2
    if ecg2Available
        idx = ((ecg1Available + ecg2Available) * 20) + 3;
        % ALL ecg2 samples, pre-allocate memory equivalent to the final representation as type double
        ecg2 = zeros(8,batchesInFile*6,'uint8');
        % First Sample of ecg2 from each batch
        ecg2(6,1:6:end) = uint8data(idx:batchSize:end);
        ecg2(7,1:6:end) = uint8data(idx+1:batchSize:end);
        ecg2(8,1:6:end) = uint8data(idx+2:batchSize:end);
        % Second Sample of ecg2 from each batch
        ecg2(6,2:6:end) = uint8data(idx+3:batchSize:end);
        ecg2(7,2:6:end) = uint8data(idx+4:batchSize:end);
        ecg2(8,2:6:end) = uint8data(idx+5:batchSize:end);
        % Third Sample of ecg2 from each batch
        ecg2(6,3:6:end) = uint8data(idx+6:batchSize:end);
        ecg2(7,3:6:end) = uint8data(idx+7:batchSize:end);
        ecg2(8,3:6:end) = uint8data(idx+8:batchSize:end);
        % Fourth Sample of ecg2 from each batch
        ecg2(6,4:6:end) = uint8data(idx+9:batchSize:end);
        ecg2(7,4:6:end) = uint8data(idx+10:batchSize:end);
        ecg2(8,4:6:end) = uint8data(idx+11:batchSize:end);
        % Fifth Sample of ecg2 from each batch
        ecg2(6,5:6:end) = uint8data(idx+12:batchSize:end);
        ecg2(7,5:6:end) = uint8data(idx+13:batchSize:end);
        ecg2(8,5:6:end) = uint8data(idx+14:batchSize:end);
        % Sixth Sample of ecg2 from each batch
        ecg2(6,6:6:end) = uint8data(idx+15:batchSize:end);
        ecg2(7,6:6:end) = uint8data(idx+16:batchSize:end);
        ecg2(8,6:6:end) = uint8data(idx+17:batchSize:end);
        % Reshape and typecast
        ecg2 = typecast(reshape(ecg2,[],1),'int64');
        % Bit-shift
        ecg2 = bitshift(ecg2,-40);
        ecg2 = double(ecg2);
    end

    % PART 4, ECG_3
    if ecg3Available
        idx = ((ecg1Available + ecg2Available + ecg3Available) * 20) + 3;
        % ALL ecg3 samples, pre-allocate memory equivalent to the final representation as type double
        ecg3 = zeros(8,batchesInFile*6,'uint8');
        % First Sample of ecg3 from each batch
        ecg3(6,1:6:end) = uint8data(idx:batchSize:end);
        ecg3(7,1:6:end) = uint8data(idx+1:batchSize:end);
        ecg3(8,1:6:end) = uint8data(idx+2:batchSize:end);
        % Second Sample of ecg3 from each batch
        ecg3(6,2:6:end) = uint8data(idx+3:batchSize:end);
        ecg3(7,2:6:end) = uint8data(idx+4:batchSize:end);
        ecg3(8,2:6:end) = uint8data(idx+5:batchSize:end);
        % Third Sample of ecg3 from each batch
        ecg3(6,3:6:end) = uint8data(idx+6:batchSize:end);
        ecg3(7,3:6:end) = uint8data(idx+7:batchSize:end);
        ecg3(8,3:6:end) = uint8data(idx+8:batchSize:end);
        % Fourth Sample of ecg3 from each batch
        ecg3(6,4:6:end) = uint8data(idx+9:batchSize:end);
        ecg3(7,4:6:end) = uint8data(idx+10:batchSize:end);
        ecg3(8,4:6:end) = uint8data(idx+11:batchSize:end);
        % Fifth Sample of ecg3 from each batch
        ecg3(6,5:6:end) = uint8data(idx+12:batchSize:end);
        ecg3(7,5:6:end) = uint8data(idx+13:batchSize:end);
        ecg3(8,5:6:end) = uint8data(idx+14:batchSize:end);
        % Sixth Sample of ecg3 from each batch
        ecg3(6,6:6:end) = uint8data(idx+15:batchSize:end);
        ecg3(7,6:6:end) = uint8data(idx+16:batchSize:end);
        ecg3(8,6:6:end) = uint8data(idx+17:batchSize:end);
        % Reshape and typecast
        ecg3 = typecast(reshape(ecg3,[],1),'int64');
        % Bit-shift
        ecg3 = bitshift(ecg3,-40);
        ecg3 = double(ecg3);
    end
    ecg = [ecg1, ecg2, ecg3];

    fclose(fid);
    
    % Scale accel to g-force
    acc = acc * 0.00006103515625;
%     acc_x = acc_x * 0.00006103515625;
%     acc_y = acc_y * 0.00006103515625;
%     acc_z = acc_z * 0.00006103515625;
    % Scaling temp to Celsius
    temp_amb_obj(temp_amb_obj ~= 0) = (temp_amb_obj(temp_amb_obj ~= 0) * 0.02) - 273.15;

%     % find indices of missed batches
%     missedBatches = find(serialNumber == 0);
%     % set ecg, resp, accel, and temp data in missed batches to 'NaN'
%     if ~isempty(missedBatches)
%         % set accel, temp, resp, and ecg data to 'NaN' in missed batches (instead of 0, as is their current value)
%         acc_x(missedBatches) = NaN;
%         acc_y(missedBatches) = NaN;
%         acc_z(missedBatches) = NaN;
%         temp_amb_obj(missedBatches) = NaN;
%         % Setting invalid resp samples to NaN may cause trouble in subsequent filtering
% %       if ~isempty(resp)
% %           resp(missedBatches) = NaN;
% %       end
%         % building index numbers for missed samples in resp and ecg (6 times as many as in accel, temp, and resp)
%         startOfMissed_ecg_resp = ((missedBatches-1)*6)+1;
%         endOfMissed_ecg_resp = missedBatches*6;
%         idx = coloncat(startOfMissed_ecg_resp, endOfMissed_ecg_resp);
%         if ~isempty(ecg1)
%             ecg1(idx) = 0; % NaN or -32768 for Comm error
%         end
%         if ~isempty(ecg2)
%             ecg2(idx) = 0; % NaN or -32768 for Comm error
%         end
%         if ~isempty(ecg3)
%             ecg3(idx) = 0; % NaN or -32768 for Comm error
%         end
%     end
    
    % Splitting temp into temp_ambient and tenp_object.
    % temp_ambient is stored in batches where mod(serialNumber,2) == 0.
    batchesBeforeFirstValidSerial = (posForValidConf - 19 - miscOffset) / batchSize;
    serialOfFirstBatch = first_valid_serial - batchesBeforeFirstValidSerial;
    if mod(serialOfFirstBatch,2) == 0
        temp_ambient = temp_amb_obj(2:2:end);
        temp_object = temp_amb_obj(1:2:end);
    else
        temp_ambient = temp_amb_obj(1:2:end);
        temp_object = temp_amb_obj(2:2:end);
    end
    
%     acc = [acc_y, -acc_x, acc_z]; % yes, acc_x = acc_y, and yes, acc_y = -acc_x

    % if we have one less temp_ambient or temp_object sample (because of
    % odd munber of batches), extend with a copy of last sample.
    if (length(temp_object) - length(temp_ambient)) == 1
        % extend temp_ambient with one sample equal to the final sample
        temp_ambient(end+1) = temp_ambient(end);
    elseif (length(temp_ambient) - length(temp_object)) == 1
        % extend temp_object with one sample equal to the final sample
        temp_object(end+1) = temp_object(end);
    end
    
    temp = [temp_ambient, temp_object];
    ecg_serials = [ecg1_serial, ecg2_serial, ecg3_serial];
    fprintf('c3_read_ble_24bit_uint8: %.2f seconds\n',toc(hTic));
end

function idx = coloncat(start, stop)
    % COLONCAT Concatenate colon expressions
    %    idx = COLONCAT(START,STOP) returns a vector containing the values
    %    [START(1):STOP(1) START(2):STOP(2) START(END):STOP(END)].

    % Based on Peter Acklam's code for run length decoding.
    len = stop - start + 1;

    % keep only sequences whose length is positive
    pos = len > 0;
    start = start(pos);
    stop = stop(pos);
    len = len(pos);
    if isempty(len)
        idx = [];
        return;
    end

    % expand out the colon expressions
    endlocs = cumsum(len);  
    incr = ones(1, endlocs(end));  
    jumps = start(2:end) - stop(1:end-1);  
    incr(endlocs(1:end-1)+1) = jumps;
    incr(1) = start(1);
    idx = cumsum(incr);
end