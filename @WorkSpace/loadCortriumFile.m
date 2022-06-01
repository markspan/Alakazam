function loadCortriumFile(this, WS, name)
%%
%
% http://www.mathworks.com/matlabcentral/fileexchange/45840-complete-pan-tompkins-implementation-ecg-qrs-detector
% https://nl.mathworks.com/help/wavelet/ug/r-wave-detection-in-the-ecg.html
% https://nl.mathworks.com/matlabcentral/fileexchange/67805-biosigkit-a-toolkit-for-bio-signal-analysis?s_tid=prof_contriblnk
% https://nl.mathworks.com/matlabcentral/fileexchange/45404-an-online-algorithm-for-r-s-and-t-wave-detection
%%

import matlab.ui.internal.toolstrip.*
[~,id,~] = fileparts(name);

% add the (semi)rootnode:
pathName = WS.CacheDirectory;
matfilename = strcat(WS.CacheDirectory, id, '.mat');
cortriumfilename = strcat(WS.RawDirectory, name);

if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    Cortriumfile = dir(cortriumfilename);
    if Cortriumfile.datenum > matfile.datenum
        % if the raw file is newer then the Mat file reread it
        EEG = readRawCortrium([WS.RawDirectory name], id);
        EEG.File = matfilename;
        save(matfilename, 'EEG');
        this.EEG=EEG;
    else
        % else read the rawfile
        a=load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    EEG = readRawCortrium([WS.RawDirectory name], id);
    EEG.File = matfilename;
    save(matfilename, 'EEG');
    this.EEG=EEG;
end

tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
setIcon(tn,this.RawFileIcon);
%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);


    function EEG = readRawCortrium(fname, id)
        full_path = [fname];
        fileFormat = 'BLE 24bit';
        eventMarkers = struct([]);
        
        loadAndFormatData();
 
        data = [sum(C3.ecg.dataRaw,2) C3.ecg.dataRaw resample([C3.accel.dataRaw C3.accelmag.dataRaw C3.resp.dataRaw double(C3.eventCounter) double(C3.serialNumber)],6,1)];
        
        EEG        = Tools.eeg_emptyset();
        EEG.data   = data';
        EEG.srate  = C3.ecg.fs;
        EEG.pnts   = size(data,1);
        EEG.times = (((1:EEG.pnts)-1)/EEG.srate);
        
%         RTopIndices = detectIbi(data(:,2), EEG.srate);
%         
%         global Events
%         Events = cell(length(RTopIndices), 3);
%         i=1;
%         for EventLatency = RTopIndices
%             Events{i,1} = 'RTop'; % type
%             Events{i,2} = EventLatency/EEG.srate; % latency
%             Events{i,3} = 1; %code
%             i = i + 1;
%         end
        
%        EEG.event = importevent( 'Events', [], EEG.srate);
        
        EEG.nbchan = size(data,2);
        channelNameList = {'ECG','Ecg 1','Ecg 2','Ecg 3','Acc X','Acc Y', 'Acc Z','Acc Magnitude',...
            'Resp','EventCounter','SerialNumber'};
        for n = 1:length(channelNameList)
            EEG.chanlocs(n).theta = 0;
            EEG.chanlocs(n).labels = channelNameList{n};
        end
        EEG.chanlocs = EEG.chanlocs';
        EEG.setname = fname;
        EEG.Originalfilename = fname;
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';
        EEG.id = id;
        EEG.trials = 1;
        EEG.xmin = min(EEG.times);
        EEG.xmax = max(EEG.times);
        EEG = Tools.eeg_checkset(EEG);
    end


%function called when loading new sensor data. Fills jsondata.events into eventMarkers.
    function eventMarkers = initializeEventMarkersFromBLE(C3,eventMarkers,sampleRateFactor)
        eventIndices = find(diff(C3.eventCounter) > 0);
        eventIndices = trimEvents(eventIndices, sampleRateFactor);
        idxOffset = length(eventMarkers);
        for ii=1:length(eventIndices)
            eventMarkers(ii+idxOffset).index = ii+idxOffset;
            eventMarkers(ii+idxOffset).serial = eventIndices(ii);
            eventMarkers(ii+idxOffset).description = ['C3 button press #' num2str(ii)];
            eventMarkers(ii+idxOffset).eventid = 'BLE'; %char(java.util.UUID.randomUUID);
        end
    end
    
%function called when loading new sensor data. Fills jsondata.events into eventMarkers.
    function eventMarkers = initializeEventMarkersFromJson(jsondata,eventMarkers)
        if isfield(jsondata,'events') && ~isempty(jsondata.events)
            idxOffset = length(eventMarkers);
            for ii=1:size(jsondata.events,2)
                eventMarkers(ii+idxOffset).index = ii+idxOffset;
                eventMarkers(ii+idxOffset).serial = jsondata.events{1,ii}.serial;
                eventMarkers(ii+idxOffset).description = jsondata.events{1,ii}.eventname;
                eventMarkers(ii+idxOffset).eventid = jsondata.events{1,ii}.eventid;
            end
        end
    end
%function for trimming number of events displayed from the BLE-file (only 24bit)
    function eventIndices = trimEvents(eventIndices, sampleRateFactor)
        if ~isempty(eventIndices)
            % Minimum difference between events, in seconds
            minDiffSecs = 3;
            % First event should always be accepted, hence the '[true;' part, which
            % also makes the length of the diff array match the length of the array being diff'ed.
            eventIndices = eventIndices([true; diff(eventIndices) > (250/sampleRateFactor.ECG)*minDiffSecs]);
        end
    end

    function dataLoaded = loadAndFormatData()
        hTic_loadAndFormatData = tic;
        % load JSON file, if any
        json_fullpath = '';
        jsondata_class_fullpath = '';
        classification_fullpath = '';
        jsondata = struct([]);
        jsondata_class_segment = struct([]);
        switch fileFormat
            case 'BIN (folder)'
                listjson = dir([pathName filesep '*.JSON']);
                % if only one JSON file exist in this directory, load it
                if size(listjson,1) == 1
                    json_fullpath = [pathName filesep listjson(1).name];
                    jsondata = loadjson(json_fullpath);
                    % else,if more than 1 JSON file is present, warn
                elseif size(listjson,1) > 1
                    warndlg(sprintf('More than one JSON file present in folder!\nAuto-loading of JSON was skipped.'));
                end
            otherwise
                [~,filename_wo_extension,~] = fileparts(name);
                if exist([pathName filename_wo_extension '.JSON'], 'file') == 2
                    json_fullpath = [pathName filename_wo_extension '.JSON'];
                    jsondata = loadjson(json_fullpath);
                end
        end
        % Set samplingRateFactor. The base frequency is assumed to be that of the Accelerometer signal.
        switch fileFormat
            case 'BLE 24bit'
                sampleRateFactor.ECG = 6;
                sampleRateFactor.Resp = 1;
                sampleRateFactor.Accel = 1;
                sampleRateFactor.Temp = 0.5;
            otherwise
                sampleRateFactor.ECG = 10;
                sampleRateFactor.Resp = 10;
                sampleRateFactor.Accel = 1;
                sampleRateFactor.Temp = 1;
        end
        % Now load BLE or a folder of BIN's
        dataLoaded = false;
        % Create a new C3 object
        C3 = Cortrium.cortrium_c3(pathName);
        switch fileFormat
            % if selected file format is BLE 24bit
            case 'BLE 24bit'
                hTic_readFile = tic;
                % Initialise components
                C3.initializeForBLE24bit;
                % load and assign data from .BLE file, 24bit version
                [C3.serialNumber, conf, serial_ADS, C3.eventCounter, C3.leadoff, C3.accel.dataRaw, C3.temp.dataRaw,  C3.resp.dataRaw, C3.ecg.dataRaw, ecg_serials] = Cortrium.c3_read_ble_24bit(full_path);
                C3.accel.samplenum = length(C3.accel.dataRaw);
                C3.temp.samplenum = length(C3.temp.dataRaw);
                C3.resp.samplenum = length(C3.resp.dataRaw);
                C3.ecg.samplenum = length(C3.ecg.dataRaw);
                [~,ble_filename_wo_extension,~] = fileparts([pathName filesep name]);
                % if there's jsondata available and there's a 'start' field, then that is prioritised to indicate start of recording
                if ~isempty(jsondata) && isfield(jsondata,'start') && ~isempty(jsondata.start)
                    C3.date_start = datenum(datetime(jsondata.start,'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSXXX','TimeZone','local'));
                    % if no jsondata, then try using the filename to indicate start of recording, with the assumption that the filename is a HEX posixtime value
                elseif all(ismember(ble_filename_wo_extension, '1234567890abcdefABCDEF')) && length(ble_filename_wo_extension) < 9
                    C3.date_start = datenum(datetime(hex2dec(ble_filename_wo_extension), 'ConvertFrom', 'posixtime', 'TimeZone', 'local'));
                    % if none of the above were an option, then set the start time as follows
                else
                    C3.date_start = datenum(datetime('0001-01-01T00:00:00.000+0000','InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSXXX','TimeZone','local'));
                end
                %                 if isempty(jsondata)
                %                     [jsondata, Cancelled] = createNewJSON(C3,full_path,fileFormat);
                %                     if ~Cancelled
                %                         json_fullpath = [pathName filename_wo_extension '.json'];
                %                     end
                %                     pause(0.1);
                %                 end
                C3.date_end = addtodate(C3.date_start, C3.ecg.samplenum*1000/C3.ecg.fs, 'millisecond');
                C3.missingSerials = find(C3.serialNumber == 0);
                % initialize event markers for events found in the BLE-file (only 24bit version)
                eventMarkers = initializeEventMarkersFromBLE(C3,eventMarkers,sampleRateFactor);
                dataLoaded = true;
                fprintf('GUI, read BLE 24bit file and initialize event markers: %f seconds\n',toc(hTic_readFile));
                % if selected file format is BLE 16bit
            case 'BLE 16bit'
                hTic_readFile = tic;
                % Initialise components
                C3.initializeForBLE16bit;
                % load and assign data from .BLE file, 16bit version
                [C3.serialNumber, C3.leadoff, C3.accel.dataRaw, C3.temp.dataRaw, C3.resp.dataRaw, C3.ecg.dataRaw] = c3_read_ble(full_path);
                conf = [];
                C3.accel.samplenum = length(C3.accel.dataRaw);
                C3.temp.samplenum = length(C3.temp.dataRaw);
                C3.resp.samplenum = length(C3.resp.dataRaw);
                C3.ecg.samplenum = length(C3.ecg.dataRaw);
                [~,ble_filename_wo_extension,~] = fileparts([pathName filesep name]);
                % if there's jsondata available and there's a 'start' field, then that is prioritised to indicate start of recording
                if ~isempty(jsondata) && isfield(jsondata,'start') && ~isempty(jsondata.start)
                    C3.date_start = datenum(datetime(jsondata.start,'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSXXX','TimeZone','local'));
                    % if no jsondata, then try using the filename to indicate start of recording, with the assumption that the filename is a HEX posixtime value
                elseif all(ismember(ble_filename_wo_extension, '1234567890abcdefABCDEF')) && length(ble_filename_wo_extension) < 9
                    C3.date_start = datenum(datetime(hex2dec(ble_filename_wo_extension), 'ConvertFrom', 'posixtime', 'TimeZone', 'local'));
                    % if none of the above were an option, then set the start time as follows
                else
                    C3.date_start = datenum(datetime('0001-01-01T00:00:00.000+0000','InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSXXX','TimeZone','local'));
                end
                if isempty(jsondata)
                    [jsondata, Cancelled] = createNewJSON(C3,full_path,fileFormat);
                    if ~Cancelled
                        json_fullpath = [pathName filename_wo_extension '.json'];
                    end
                    pause(0.1);
                end
                C3.date_end = addtodate(C3.date_start, C3.ecg.samplenum*1000/C3.ecg.fs, 'millisecond');
                C3.missingSerials = find(C3.serialNumber == 0);
                dataLoaded = true;
                fprintf('Read BLE 16bit file: %f seconds\n',toc(hTic_readFile));
                % if selected file format is BIN
            otherwise
                if ~isempty(dir([pathName '\*.bin']))
                    hTic_readFile = tic;
                    % Initialise components and load data from .bin files
                    C3.initialize;
                    conf = [];
                    C3.leadoff = zeros(1, C3.temp.samplenum);
                    name = '*.bin';
                    C3.ecg.dataRaw = C3.ecg.data;
                    C3.accel.dataRaw = C3.accel.data;
                    C3.resp.dataRaw = C3.resp.data;
                    C3.temp.dataRaw = C3.temp.data;
                    dataLoaded = true;
                    fprintf('Read BIN files: %f seconds\n',toc(hTic_readFile));
                else
                    warndlg('No .bin files in this directory!');
                    return;
                end
        end
        % Warn about sample count mismatch (which often occur in .bin files from python script used to convert BLE's)
        switch fileFormat
            % if selected file format is BLE 24bit
            case 'BLE 24bit'
                if (C3.ecg.samplenum ~= C3.accel.samplenum*sampleRateFactor.ECG) && (abs(C3.accel.samplenum - 2*C3.temp.samplenum) <= 1)
                    warndlg(sprintf('Sample count mismatch!\nECG should be x6 the sample count of Accel.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                elseif (abs(C3.accel.samplenum - 2*C3.temp.samplenum) > 1) && (C3.ecg.samplenum == C3.accel.samplenum*sampleRateFactor.ECG)
                    warndlg(sprintf('Sample count mismatch!\nAccel should be x2 the sample count of Temp.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                elseif (C3.accel.samplenum ~= C3.resp.samplenum) && (C3.resp.samplenum ~= 0)
                    warndlg(sprintf('Sample count mismatch!\nAccel and Resp sample count should be identical.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                end
            otherwise
                if (C3.ecg.samplenum ~= C3.accel.samplenum*sampleRateFactor.ECG) && (C3.accel.samplenum == C3.temp.samplenum)
                    warndlg(sprintf('Sample count mismatch!\nECG and Resp should be x10 the sample count of Accel and Temp.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                elseif (C3.accel.samplenum ~= C3.temp.samplenum) && (C3.ecg.samplenum == C3.accel.samplenum*sampleRateFactor.ECG)
                    warndlg(sprintf('Sample count mismatch!\nAccel and Temp sample count should be identical.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                elseif (C3.accel.samplenum ~= C3.temp.samplenum) && (C3.ecg.samplenum ~= C3.accel.samplenum*sampleRateFactor.ECG)
                    warndlg(sprintf('Sample count mismatch!\nECG and Resp should be x10 the sample count of Accel and Temp,\nand Accel and Temp sample count should be identical.\n\nECG: %d\nResp: %d\nAccel: %d\nTemp: %d',C3.ecg.samplenum, C3.resp.samplenum, C3.accel.samplenum, C3.temp.samplenum));
                end
        end
        % calculate Accel magnitude
        C3.accelmag.dataRaw = sqrt(sum(C3.accel.dataRaw.^2,2));
        
        % Prepare lead-off for GUI view
        C3.ecg.leadoff = double(C3.leadoff);
        C3.ecg.leadoff(C3.ecg.leadoff == 0) = NaN;
        C3.ecg.leadoff = (C3.ecg.leadoff-10000);
        % "upsample" to match ecg signal with 10 ecg samples per packet
        C3.ecg.leadoff = reshape(repmat(C3.ecg.leadoff', round(C3.ecg.fs/C3.accel.fs), 1), [], 1);
    end
% create new C3 object, empty until a sensor data directory has been selected
C3 = Cortrium.cortrium_c3('');
jsondata = struct([]);
jsondata_class_segment = struct([]);
eventMarkers = struct([]);
pathName = '';
name = '';
full_path = '';
json_fullpath = '';
jsondata_class_fullpath = '';
classification_fullpath = '';
conf = [];
fileFormat = '';
end
