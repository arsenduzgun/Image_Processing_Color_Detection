function image = loadImage(imagePath)
    % Load an image from the specified file, convert to double precision for further processing
    image = im2double(imread(imagePath));
    % Optionally display the image (uncomment to view)
    % imshow(image);
end

function [sortedCircleLocations, destinationPoints] = findCircles(image)
    % Convert the image to grayscale
    grayImage = rgb2gray(image);
    % Apply Gaussian blur to reduce noise and detail in the image
    filteredImage = imgaussfilt(grayImage, 2);
    % Detect edges using the Canny algorithm
    edges = edge(filteredImage, 'canny', [0.1, 0.9]);
    % Close small holes in the edges to better define regions
    seClose = strel('disk', 1);
    closedEdges = imclose(edges, seClose);
    % Fill holes within regions to solidify detected shapes
    filledEdges = imfill(closedEdges, 'holes');
    % Remove objects at the border to isolate only internal objects
    clearEdges = imclearborder(filledEdges);
    % Label distinct objects in the image for further analysis
    [labeledImage, ~] = bwlabel(clearEdges);
    % Measure properties of these objects to filter for circles based on shape and size
    stats = regionprops(labeledImage, 'Centroid', 'Eccentricity', 'MajorAxisLength', 'MinorAxisLength', 'Area');
    % Define maximum allowable dimensions and area for detected circles
    maxAxisLength = 70;
    maxArea = 5000;
    filteredStats = stats([stats.MajorAxisLength] < maxAxisLength & [stats.MinorAxisLength] < maxAxisLength & [stats.Area] < maxArea);
    circleLocations = cat(1, filteredStats.Centroid);
    numCircles = size(circleLocations, 1);
    % Error handling if the number of detected circles is not exactly four
    if numCircles ~= 4
        fprintf('\n');
        error('Expected 4 circles, but found %d.\n', numCircles);
    end
    % Set destination points for geometric transformation based on image size
    [height, width, ~] = size(image);
    destinationPoints = [1, 1; width + 1, 1; 1, height + 1; width + 1, height + 1];
    sortedCircleLocations = zeros(numCircles, 2);
    usedCircles = false(numCircles, 1);
    % Sort circle locations based on proximity to predefined destination points
    for i = 1:numCircles
        minDistance = inf;
        minIndex = 0;
        for j = 1:numCircles
            if ~usedCircles(j)
                currentDistance = norm(destinationPoints(i,:) - circleLocations(j, :));
                if currentDistance < minDistance
                    minDistance = currentDistance;
                    minIndex = j;
                end
            end
        end
        sortedCircleLocations(i, :) = circleLocations(minIndex, :);
        usedCircles(minIndex) = true;
    end
end

function correctedImage = correctImage(circleLocations, destinationPoints, image)
    % Compute a projective transformation based on sorted circle locations and destination points
    tform = fitgeotrans(circleLocations, destinationPoints, 'projective');
    warpedImage = imwarp(image, tform, 'OutputView', imref2d(size(image)));
    % Convert the warped image to grayscale and detect edges for further processing
    grayImage = rgb2gray(warpedImage);
    filteredImage = imgaussfilt(grayImage, 2);
    edges = edge(filteredImage, 'canny');
    % Dilate the edges to make them more prominent
    seDilate = strel('square', 3);
    dilatedEdges = imdilate(edges, seDilate);
    filledEdges = imfill(dilatedEdges, 'holes');
    % Find the largest bounding box to focus on the main object
    props = regionprops(filledEdges, 'BoundingBox');
    bboxArea = 0;
    bbox = [];
    for k = 1:numel(props)
        if props(k).BoundingBox(3) * props(k).BoundingBox(4) > bboxArea
            bbox = props(k).BoundingBox;
            bboxArea = props(k).BoundingBox(3) * props(k).BoundingBox(4);
        end
    end
    % Define the cropping area with a margin, ensuring it stays within image bounds
    margin = -10;
    cropRect = [bbox(1)-margin, bbox(2)-margin, bbox(3)+2*margin, bbox(4)+2*margin];
    cropRect = max(cropRect, [1, 1, 1, 1]);
    cropRect(3:4) = min([cropRect(3) cropRect(4)], [size(warpedImage, 2) - cropRect(1), size(warpedImage, 1) - cropRect(2)]);
    correctedImage = imcrop(warpedImage, cropRect);
    % Optionally display the corrected image (uncomment to view)
    imshow(correctedImage);
end

function colors = getColors(image)
    % Convert the image from RGB to Lab color space to separate lightness from color components
    borderFraction = 0.1; % Set border exclusion factor
    cform = makecform('srgb2lab');
    labImage = applycform(image, cform);
    % Divide the image into blocks to analyze each section
    [rows, cols, ~] = size(labImage);
    blockRows = floor(rows / 4);
    blockCols = floor(cols / 4);
    colors = strings(4, 4);
    % Analyze each block and determine the dominant color based on average Lab values
    for i = 1:4
        for j = 1:4
            rowStart = (i-1) * blockRows + 1 + floor(blockRows * borderFraction);
            rowEnd = i * blockRows - floor(blockRows * borderFraction);
            colStart = (j-1) * blockCols + 1 + floor(blockCols * borderFraction);
            colEnd = j * blockCols - floor(blockCols * borderFraction);
            block = labImage(rowStart:rowEnd, colStart:colEnd, :);
            avgLab = mean(mean(block, 1), 2);
            % Optionally print each block's color values (uncomment to debug)
            % fprintf('Block (%d, %d): L=%f, a=%f, b=%f\n', i, j, avgLab(1), avgLab(2), avgLab(3));
            % Determine color based on the Lab values
            if avgLab(2) < -45
                colors(i, j) = 'green';
            elseif avgLab(3) > -30 && avgLab(3) < 20
                colors(i, j) = 'white';
            elseif avgLab(2) < 0
                colors(i, j) = 'yellow';
            elseif avgLab(3) > 20
                colors(i, j) = 'red';
            elseif avgLab(1) > 40
                colors(i, j) = 'purple';
            elseif avgLab(1) > 20 && avgLab(1) < 45 && avgLab(2) > 35 && avgLab(2) < 80 && avgLab(3) < -70
                colors(i, j) = 'blue';
            else
                colors(i, j) = 'other';
            end
        end
    end
end

function colors = findColors(imagePath)
    % Main function that uses the helper functions to process an image and find colors
    image = loadImage(imagePath);
    [circleLocations, destinationPoints] = findCircles(image);
    correctedImage = correctImage(circleLocations, destinationPoints, image);
    colors = getColors(correctedImage);
end

imagePath = 'images/rot_5.png';
colors = findColors(imagePath);
fprintf('\n');
disp(colors);