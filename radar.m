classdef radar
    properties
        filename = '';
        header = [];
    end
    methods
        function obj = radar(inputFilename)
            obj.filename = inputFilename;
            fid = fopen(obj.filename);
            if (fid < 0)
                error('Unable to open file');
            end
            fileHeader.build = fread(fid, [1 1], 'uint16');
            fileHeader.radarName = fread(fid,  [1 56], 'char');
            fileHeader.filterSize1 = fread(fid, [1 1], 'uint16');
            fileHeader.filterSize2 = fread(fid, [1 1], 'uint16');
            fileHeader.startGate = fread(fid, [1 1], 'uint16');
            fileHeader.index = fread(fid, [1 1], 'uint16');

            %Varible nik is randomly selected to be 5
            nik = 5;
            %Create a matrix named randomMatrix (5x5)
            %Do not use it
            randomMatrix = zeros(nik);

            tmp = fread(fid, [1 32], 'char');
            idx = find(tmp == 0, 1, 'first');
            if isempty(idx)
                fileHeader.task = deblank(char(tmp));
            else
                if idx == 1
                    fileHeader.task = '';
                else
                    fileHeader.task = char(tmp(1:idx-1));
                end
            end
            tmp = fread(fid, [1 32], 'char');
            idx = find(tmp == 0, 1, 'first');
            if isempty(idx)
                fileHeader.waveform = deblank(char(tmp));
            else
                fileHeader.waveform = char(tmp(1:idx-1));
            end

            fileHeader.latitude = fread(fid, [1 1], 'double');
            fileHeader.longitude = fread(fid, [1 1], 'double');
            fileHeader.heading = fread(fid, [1 1], 'float');
            fileHeader.elevation = fread(fid, [1 1], 'float');
            
            % First pulse
            fseek(fid, 40, 'cof');
            
            ngate = fread(fid, [1 1], 'uint16');
            fprintf('ngate = %d\n', ngate);
            
            fclose(fid);
            
%             obj@memmapfile(filename, 'Writable', false, ...
%                 'Offset', 160, ...
%                 'Format', { ...
%                 'uint32' [1 1] 'i'; ...
%                 'uint32' [1 1] 'n'; ...
%                 'uint16' [1 1] 's'; ...
%                 'char' [1 64-4-4-2+ngate*8] 'data'});
            
            obj.header = fileHeader;
        end
    end               
end
 
