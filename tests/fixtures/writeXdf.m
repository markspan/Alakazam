function writeXdf(file, streams)
%WRITEXDF  A minimal XDF 1.0 file, for tests that read one.
%
%   writeXdf(FILE, STREAMS) writes the file header, each stream's header,
%   its samples (float32, each with its time stamp), its clock offsets and
%   its footer, which lists the clock offsets again, as LabRecorder writes
%   it. STREAMS is a struct array with fields
%     name, type   the stream's name and type ('EEG', 'ECG', ...)
%     labels       a cellstr, one label per channel
%     rate         the nominal sampling rate (Hz)
%     times        1 x N time stamps (s)
%     data         channels x N samples
%     offsets      K x 2 clock offsets, [collection time, offset] (s)
%
%   See also RAWFORMATSTEST.
    fid = fopen(file, 'w', 'l');
    closeFile = onCleanup(@() fclose(fid));
    fwrite(fid, 'XDF:', 'char');
    chunk(fid, 1, uint8('<?xml version="1.0"?><info><version>1.0</version></info>'));
    for s = 1:numel(streams)
        S = streams(s);
        channels = strjoin(cellfun(@(l) sprintf(['<channel><label>%s</label><type>%s</type>' ...
            '<unit>microvolts</unit></channel>'], l, S.type), S.labels, 'UniformOutput', false), '');
        xml = sprintf(['<?xml version="1.0"?><info><name>%s</name><type>%s</type>' ...
            '<channel_count>%d</channel_count><nominal_srate>%g</nominal_srate>' ...
            '<channel_format>float32</channel_format><source_id>%s</source_id>' ...
            '<version>1.1</version><created_at>0</created_at><uid>u%d</uid>' ...
            '<session_id>default</session_id><hostname>test</hostname>' ...
            '<desc><channels>%s</channels></desc></info>'], S.name, S.type, numel(S.labels), ...
            S.rate, S.name, s, channels);
        chunk(fid, 2, [typecast(uint32(s), 'uint8'), uint8(xml)]);
    end
    for s = 1:numel(streams)
        S = streams(s);
        n = numel(S.times);
        channelCount = size(S.data, 1);
        for first = 1:1000:n
            k = first:min(n, first + 999);
            perSample = [repmat(uint8(8), 1, numel(k)); ...
                reshape(typecast(double(S.times(k)), 'uint8'), 8, []); ...
                reshape(typecast(reshape(single(S.data(:, k)), 1, []), 'uint8'), 4 * channelCount, [])];
            chunk(fid, 3, [typecast(uint32(s), 'uint8'), uint8(4), ...
                typecast(uint32(numel(k)), 'uint8'), reshape(perSample, 1, [])]);
        end
        for c = 1:size(S.offsets, 1)
            chunk(fid, 4, [typecast(uint32(s), 'uint8'), typecast(double(S.offsets(c, 1)), 'uint8'), ...
                typecast(double(S.offsets(c, 2)), 'uint8')]);
        end
    end
    for s = 1:numel(streams)
        S = streams(s);
        offsets = strjoin(arrayfun(@(c) sprintf('<offset><time>%.10f</time><value>%.10f</value></offset>', ...
            S.offsets(c, 1), S.offsets(c, 2)), 1:size(S.offsets, 1), 'UniformOutput', false), '');
        xml = sprintf(['<?xml version="1.0"?><info><first_timestamp>%.10f</first_timestamp>' ...
            '<last_timestamp>%.10f</last_timestamp><sample_count>%d</sample_count>' ...
            '<clock_offsets>%s</clock_offsets></info>'], S.times(1), S.times(end), numel(S.times), offsets);
        chunk(fid, 6, [typecast(uint32(s), 'uint8'), uint8(xml)]);
    end
end

% ======================================================================= %
function chunk(fid, tag, content)
%CHUNK  One XDF chunk: its length in 8 bytes, its tag, its content.
    fwrite(fid, uint8(8), 'uint8');
    fwrite(fid, uint64(numel(content) + 2), 'uint64');
    fwrite(fid, uint16(tag), 'uint16');
    fwrite(fid, content, 'uint8');
end
