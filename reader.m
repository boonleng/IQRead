%    
%   PX-1000 Reader (Requires 64-bit version of Matlab)
%
%   To read a file, execute a Matlab command as follows:
%   output = reader('')
%   Where the file you want to read is placed inside the single quotes:
%   output = reader('PX-20130402-122546-E3.0.iq')
%
%   To access structure of all ch1, ch2, azimuth, and elevation data, use:
%   output.IQ
%
%   Each data matrix can then be extracted as:
%   output.IQ.ch1
%   output.IQ.ch2
%   output.IQ.el_deg
%   output.IQ.az_deg
%   etc...

%
%   WHAT NEEDS TO BE FIXED
%   Latitude and longitude values aren't coming out correctly
%

classdef reader
    properties (Constant)
        PX_MAX_GATES = 4096;
        PXIQ_BUILD_NO = 3;
        MAX_DWELL = 256;
        MAX_PULSES_PER_FILE = 60000;
        PXIQ_MARKER_NULL = dec2hex('0');
        PXIQ_MARKER_SWEEP_MIDDLE = dec2hex('1');
        PXIQ_MARKER_SWEEP_BEGIN = dec2hex('2');
        PXIQ_MARKER_SWEEP_END = dec2hex('4');
    end
    properties
        filename = '';
        fileheader = [];
        IQ = [];
    end
    methods
        function obj = reader(inputFilename)
            obj.filename = inputFilename;
            fid = fopen(obj.filename);
            if (fid < 0)
                error('Unable to open file');
            end
            
            %Figure out size of file
            fseek(fid, 0, 'eof');
            filesize = ftell(fid);
            frewind(fid);
            fprintf('File Size:%d\n', filesize);
            
            %///////////////////////////////////////
            %           PXIQFileHeader
            %///////////////////////////////////////       
            
            fileHeader.build = fread(fid, [1 1], 'uint16');
            fileHeader.radarName = fread(fid,  [1 56], 'char');
            fileHeader.filterSize1 = fread(fid, [1 1], 'uint16');
            fileHeader.filterSize2 = fread(fid, [1 1], 'uint16');
            fileHeader.startGate = fread(fid, [1 1], 'uint16');
            fileHeader.index = fread(fid, [1 1], 'uint16');

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
            
            obj.fileheader = fileHeader;
            
            fseek(fid, 50, 'cof');
            
            %Assign the number of gates to a variable
            numberofgates = fread(fid, [1 1], 'uint16');
            fprintf('ngate:%u\n',numberofgates);
            frewind(fid);
            
            %map the data
            m = memmapfile(obj.filename,                    ...
                           'Offset', 160,                   ...
                           'Format',{                       ...
                           'uint16' [1 1] 'type';           ...
                           'uint16' [1 1] 'size';           ...
                           'uint32' [1 1] 'i';              ...
                           'uint32' [1 1] 'n';              ...
                           'uint16' [1 1] 's';              ...
                           'uint16' [1 1] 'p';              ...
                           'uint16' [1 1] 'vm';             ...
                           'uint16' [1 1] 'pw_n';           ...
                           'uint32' [1 1] 'time_sec';       ...
                           'uint32' [1 1] 'time_usec';      ...
                           'double' [1 1] 'time_d';         ...
                           'uint16' [1 1] 'az';             ...
                           'uint16' [1 1] 'el';             ...
                           'uint16' [1 1] 'prf_hz';         ...
                           'uint16' [1 1] 'prf_idx';        ...
                           'uint16' [1 1] 'ngate';          ...
                           'uint16' [1 1] 'az_bin';         ...
                           'single' [1 1] 'dr_m';            ...
                           'single' [1 1] 'az_deg';          ...
                           'single' [1 1] 'el_deg';          ...
                           'single' [1 1] 'vaz_dps';        ...
                           'single' [1 1] 'vel_dps';        ...
                           'int16' [2 numberofgates 2] 'iq'});
                       
            %turn the map into a matlab array
            DATA = m.Data;
            
            %Size of packet_header (in bytes)
            packet_headersize = 4;
            
            %size of pulse header (in bytes)
            pulse_headersize = 64;
            
            %Full Packet size (in bytes)
            packet_size = packet_headersize + pulse_headersize + 8*numberofgates;
            
            %Size of file header, just the number of bytes
            file_headersize = 160;
            
            %Number of pulses
            num_pulses = (filesize - file_headersize)/packet_size;
            num_pulses = floor(num_pulses);
            %fprintf('packet_size:%d\n', packet_size);
            %fprintf('Estimated to have %d pulse(s).\n', num_pulses);
	
            if num_pulses > reader.MAX_PULSES_PER_FILE
                fprintf('Exceeds maximum of pulses I can handle. Truncate to %d\n', reader.MAX_PULSES_PER_FILE);
            end
            num_pulses = min(num_pulses, reader.MAX_PULSES_PER_FILE);
            
            %Create arrays az,el/azi,eli            
            az = zeros(1,num_pulses,'single');
            el = zeros(1,num_pulses,'single');
            eli = zeros(1,num_pulses,'uint16');
            azi = zeros(1,num_pulses,'uint16');
           
            %Make room for ch1 and ch2 data             
            ch1 = zeros(numberofgates,num_pulses,'single');
            ch2 = zeros(numberofgates,num_pulses,'single');            
          
            %Matlab array index (i)
            idx = 1;
            %Reader's packet count (j)
            jdx = 1;
            
            while (idx <= num_pulses)
                
                switch (char(DATA(idx).type)) 
                    case 'p',
                        
                        if (DATA(idx).vm ~= reader.PXIQ_MARKER_NULL) 
                            
                            %iq data
                            iqdata = single(DATA(idx).iq);
                            
                            %add i and q data
                            ch1(:,jdx) = complex(iqdata(1,:,1),iqdata(2,:,1));
                            ch2(:,jdx) = complex(iqdata(1,:,2),iqdata(2,:,2));
                            
                            %elevation and azimuth (float)
                            az(jdx) = DATA(idx).az_deg;
                            el(jdx) = DATA(idx).el_deg;

                            %elevation and azimuth (int)
                            elev = single(DATA(idx).el);
                            eli(jdx) = (elev * 360.0) / 65536;
                            %fprintf('Elevation:%d \n', eli(idx));
                            
                            azim = single(DATA(idx).az);
                            azi(jdx) = (azim * 360.0) / 65536;
                            %fprintf('Azimuth:%d \n', azi(idx));
                            
                            jdx = jdx + 1;
                        end
                        
                    otherwise
                        fprintf('Ignored packet\n');
                end
                 
                if (((char(DATA(idx).type) == 'p' && idx > num_pulses)) || ((char(DATA(idx).type) == 'p' && DATA(idx).vm == 69)))
                    lastpulse = idx;
                    break;
                end
                
                %pulse index array
                idx = idx + 1;
            end
            
            if ~exist('lastpulse','var')
                lastpulse = num_pulses;
            end    
            
            %Create iq_struct            
            IQSTRUCT.ch1 = ch1(:,1:lastpulse);
            IQSTRUCT.ch2 = ch2(:,1:lastpulse);
            IQSTRUCT.radar = char(obj.fileheader.radarName);
            IQSTRUCT.task = char(obj.fileheader.task);
            IQSTRUCT.waveform = char(obj.fileheader.waveform);
            IQSTRUCT.lat_deg = double(obj.fileheader.latitude);
            IQSTRUCT.lon_deg = double(obj.fileheader.longitude);
            IQSTRUCT.delr_m = double(30.0);
            IQSTRUCT.start_gate = double(obj.fileheader.startGate);
            IQSTRUCT.filter_size1 = double(obj.fileheader.filterSize1);
            IQSTRUCT.filter_size2 = double(obj.fileheader.filterSize2);
            IQSTRUCT.el_deg = el(1,1:lastpulse);
            IQSTRUCT.az_deg = az(1,1:lastpulse);
            IQSTRUCT.el_int = eli(1,1:lastpulse);
            IQSTRUCT.az_int = azi(1,1:lastpulse);
                           
            obj.IQ = IQSTRUCT;
            
            fclose(fid); 
            clear m DATA ch1 ch2;
        end
    end
end
