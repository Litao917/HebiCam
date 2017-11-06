classdef ImageConverter < handle
    % A class that simulates various ways to get image data across the
    % MATLAB-Java interface.
    
    properties
        javaConverter = sources.JavaImageConverter();
        matlabImage = [];
        memFile = [];
    end
    
    methods
        
        function [] = setImage(this, imagePath)
            % Sets the underlying image and prepares various formats
            % to later read from.
            
            % Read original file
            this.matlabImage = imread(imagePath);
            
            % Push across Java to convert to various formats. (we need
            % to add the path as well so Java can read the compressed data
            % to create a corresponding BufferedImage. im2java2d is
            % unfortunately part of a toolbox)
            setImage(this.javaConverter, this.matlabImage, imagePath);
            
            % Also prepare shared memory. We could do this from Java, but
            % it doesn't make a difference for the benchmark, as long as
            % the data is there.
            this.createMemoryMappedFile(this.matlabImage);
            
        end
        
        function img = getOriginalImage(this)
           img = this.matlabImage;
        end
        
        function image = getImageFromRawFormat3D(this)
            % Uses the built-in auto-conversion between image and byte[][][]
            %
            % Java 'byte' comes back as 'int8'. Images need to be 'uint8' Unfortunately,
            % uint8() sets all negative values to zero, and typecast() only works
            % on a 1D array. Thus, even though the data is already sized correctly,
            % we need to first do a reshape to 1D, cast, and then reshape back again.
            
            % (1) Get matrix from byte[height][width][channels]
            data = getRawFormat3d(this.javaConverter);
            [height,width,channels] = size(data);
            
            % (2) Reshape matrix to vector
            vector = reshape(data, width * height * channels, 1);
            
            % (3) Cast int8 data to uint8
            vector = typecast(vector, 'uint8');
            
            % (4) Reshape vector back to original shape
            image = reshape(vector, height, width, channels);
            
        end
        
        function image = getImageFromJavaPixelFormat1D(this)
            % Converts by using array data that is arranged in the same
            % order as the internal BufferedImage buffer.
            %
            % Based on https://mathworks.com/matlabcentral/answers/100155-how-can-i-convert-a-java-image-object-into-a-matlab-image-matrix#answer_109503
            %
            % MATLAB stores data in column major format, so we need to
            % 1. cast to uint8
            % 2. select individual colors by reshaping
            % 3. transpose
            % 4. combine colors
            
            % (1) Get data from byte[] and cast to correct type
            data = getJavaPixelFormat1d(this.javaConverter);
            data = typecast(data, 'uint8');
            [h,w,c] = size(this.matlabImage); % get dim info
            
            if c == 3 % rgb
                
                % (2) Reshape matrix for indexing
                pixelsData = reshape(data, 3, w, h);
                
                % (3) Transpose and convert from row major to col major
                % format
                image = cat(3, ...
                    transpose(reshape(pixelsData(3, :, :), w, h)), ...
                    transpose(reshape(pixelsData(2, :, :), w, h)), ...
                    transpose(reshape(pixelsData(1, :, :), w, h)));
                
            elseif c == 1 % grayscale
                pixelsData = reshape(data, w, h);
                image = pixelsData';
            end
            
        end
        
        function image = getImageFromMatlabPixelFormat1D(this)
            % Converts by using array data that is arranged in the same
            % memory order as what MATLAB uses internally. Thus, we can
            % do a simple cast and reshape of the data.
            
            % Memory is already in the correct order, so we only need to
            % cast and reshape
            
            % (1) Get data from byte[] and cast to correct type
            data = getMatlabPixelFormat1d(this.javaConverter);
            [h,w,c] = size(this.matlabImage);  % get dim info
            vector = typecast(data, 'uint8');
            
            % (2) Interpret pre-layed out memory as matrix
            image = reshape(vector,h,w,c);

        end
        
        function image = getImageFromCompressedArray(this)
            % Converts by using array data that was compressed using jpeg
            % in order to reduce the size.
            %
            % Unfortunately, MATLAB doesn't provide an in-memory
            % decompression of jpeg data, so we need to go through a file.
            % (Some Mathworks' libraries do in-memory decompression by
            % calling the Java decompression methods followed by
            % reshaping. Doing this here would defeat the purpose.)
            
            % (1) Get compressed data
            data = getJpegData(this.javaConverter);
            path = 'tmp.jpg';
            
            % (2) Save as jpeg file
            fileID = fopen(path,'w+');
            fwrite(fileID, data, 'int8');
            fclose(fileID);
            
            % (3) Read jpeg file
            image = imread(path);
            
            % (4) Cleanup
            delete(path);

        end
        
        function img = getImageFromSharedMemory(this)
            % Converts by using copying data from shared memory
            %
            % Synchronization is done using Java locks
            
            % Lock memory via handle class that guarantees that destructor
            % always calls unlock, even on interrupt.
            lock = MemoryLock(this.javaConverter);
            
            % Read from shared memory. Note that we need to force a copy of
            % the data because otherwise MATLAB will assume that the data
            % doesn't get modified and optimize to just use a pointer.
            img = this.memFile.Data.pixels * 1;

        end
        
        function [] = createMemoryMappedFile(this, data)
            % Memory maps a temporary file and saves image data
            
            % unmap previous file
            this.memFile = [];
            path = 'memFile.bin';
            delete(path);
            
            % store data
            fileID = fopen(path,'w+');
            fwrite(fileID, data(:), 'uint8');
            fclose(fileID);
            
            % Some versions have problems with mapping HxWx1, so we special
            % case grayscale images.
            pixelFormat = size(data);
            
            % Map memory to data
            this.memFile = memmapfile(path,  ...
                'Format', { 'uint8' pixelFormat 'pixels' }, ...
                'Repeat', 1);
            
        end

        function delete(this)
            % unmap memory
            this.memFile = [];
        end
        
    end
    
end

