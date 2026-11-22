// ImageJ Macro to find maxima in circular regions and measure distance to center
// Assumes: RGB image (scaled in nm) and ROI Manager with square ROIs
// Also includes a randomization control step: finds the TRUE total number of
// maxima across a user-drawn restricted rectangle, then for each iteration
// scatters that many random points across the rectangle, saves an image of
// each randomized pattern, and measures their distances to each ROI center.

// Check if image is open
if (nImages == 0) {
    exit("Please open an image first");
}

// Check if ROI Manager has ROIs
if (roiManager("count") == 0) {
    exit("Please load ROIs into the ROI Manager first");
}

// Get image title
imageTitle = getTitle();

// Get pixel size (should be in nm if image is scaled)
getPixelSize(unit, pixelWidth, pixelHeight);
if (unit != "nm") {
    showMessage("Warning", "Image may not be scaled in nm.\nCurrent unit: " + unit);
}

// Convert to 8-bit grayscale for maxima detection
run("8-bit");

// Parameters for Find Maxima
Dialog.create("Maxima Detection Settings");
Dialog.addNumber("Noise Tolerance:", 10);
Dialog.addNumber("Circle Radius (nm):", 150);
Dialog.addCheckbox("Also run randomization control?", true);
Dialog.addNumber("Randomization iterations:", 1);
Dialog.show();
noiseTolerance = Dialog.getNumber();
radiusNm = Dialog.getNumber();
doRandomization = Dialog.getCheckbox();
nIterations = Dialog.getNumber();

// Convert radius from nm to pixels
radiusPx = radiusNm / pixelWidth;

// Create results table
title1 = "Distance_Measurements";
title2 = "["+title1+"]";
f = title2;
run("Table...", "name="+title2+" width=600 height=400");
print(f, "\\Headings:ROI_Index\tROI_Name\tMaxima_X\tMaxima_Y\tCenter_X\tCenter_Y\tDistance_px\tDistance_nm");

// Get number of original square ROIs
nROIs = roiManager("count");

// Store original ROI information BEFORE clearing
squareROIs = newArray(nROIs);
for (i = 0; i < nROIs; i++) {
    roiManager("select", i);
    Roi.getBounds(roiX, roiY, roiWidth, roiHeight);
    roiName = Roi.getName();
    squareROIs[i] = "" + roiX + "," + roiY + "," + roiWidth + "," + roiHeight + "," + roiName;
}

// Ask if user wants to clear and replace ROIs or add to existing
clearROIs = getBoolean("Clear existing ROIs and replace with circles and points?");
if (clearROIs) {
    roiManager("reset");
}

// Arrays to remember circle geometry + maxima counts
circleCenterX = newArray(nROIs);
circleCenterY = newArray(nROIs);
circleROIName = newArray(nROIs);
maximaCountPerROI = newArray(nROIs);

// Process each ROI
totalMaxima = 0;
for (i = 0; i < nROIs; i++) {
    // Parse stored ROI info
    parts = split(squareROIs[i], ",");
    roiX = parseInt(parts[0]);
    roiY = parseInt(parts[1]);
    roiWidth = parseInt(parts[2]);
    roiHeight = parseInt(parts[3]);
    roiName = parts[4];
    
    // Calculate center of square ROI (center pixel)
    centerX = roiX + floor(roiWidth / 2);
    centerY = roiY + floor(roiHeight / 2);
    
    // Store geometry for later randomization
    circleCenterX[i] = centerX;
    circleCenterY[i] = centerY;
    circleROIName[i] = roiName;
    
    // Create circular ROI centered at square's center
    makeOval(centerX - radiusPx, centerY - radiusPx, radiusPx * 2, radiusPx * 2);
    roiManager("add");
    roiManager("select", roiManager("count")-1);
    roiManager("rename", "Circle_" + (i+1) + "_" + roiName);
    
    // Find maxima within this circular ROI
    run("Find Maxima...", "noise=" + noiseTolerance + " output=[Point Selection]");
    
    // Check if any points were found
    nPoints = 0;
    if (selectionType() == 10) { // 10 = point selection
        getSelectionCoordinates(xpoints, ypoints);
        nPoints = xpoints.length;
    } else {
        xpoints = newArray(0);
        ypoints = newArray(0);
    }
    
    maximaCountPerROI[i] = nPoints;
    
    // Process each maximum found
    for (j = 0; j < nPoints; j++) {
        x = xpoints[j];
        y = ypoints[j];
        
        // Add point to ROI manager
        makePoint(x, y);
        roiManager("add");
        roiManager("select", roiManager("count")-1);
        roiManager("rename", "Point_ROI" + (i+1) + "_" + (j+1));
        
        // Calculate distance using Pythagorean theorem (in pixels)
        distancePx = sqrt(pow(x - centerX, 2) + pow(y - centerY, 2));
        
        // Convert distance to nm
        distanceNm = distancePx * pixelWidth;
        
        // Print to results table (ROI index starts at 1)
        print(f, (i+1) + "\t" + roiName + "\t" + x + "\t" + y + "\t" + centerX + "\t" + centerY + "\t" + distancePx + "\t" + distanceNm);
        totalMaxima++;
    }
}

// Deselect ROI
run("Select None");

print("Analysis complete!");
print("Total ROIs processed: " + nROIs);
print("Total maxima found (within ROI circles): " + totalMaxima);
print("Pixel size: " + pixelWidth + " " + unit + "/pixel");
print("Circle radius: " + radiusNm + " nm (" + radiusPx + " pixels)");

// Save results dialog
saveResults = getBoolean("Do you want to save the results table?");
if (saveResults) {
    selectWindow(title1);
    saveAs("Results");
}

// ============================================================
// RANDOMIZATION CONTROL
// 1. User draws a restricted rectangle on the image.
// 2. Find Maxima is run ONCE on that whole rectangle to get the
//    TRUE total maxima count in the field (not just inside ROIs).
// 3. For each iteration, that many random points are scattered
//    across the rectangle, drawn as red circles on a saved PNG,
//    and checked against each ROI circle for distance measurement.
// ============================================================
if (doRandomization) {

    imgWidth = getWidth();
    imgHeight = getHeight();

    // --- Step 1: Draw restricted rectangle ---
    selectWindow(imageTitle);
    run("Select None");
    waitForUser("Draw restricted area", "Draw a RECTANGLE outlining the region\nwhere random points should be placed\n(e.g. your yellow selected area).\n\nClick OK when your selection is ready.");

    if (selectionType() != 0) {
        exit("A rectangular selection is required for this randomization method. Please re-run and draw a rectangle.");
    }

    roiManager("add");
    restrictROIIndex = roiManager("count") - 1;
    roiManager("select", restrictROIIndex);
    roiManager("rename", "Randomization_Restricted_Area");
    Roi.getBounds(restrictBoundsX, restrictBoundsY, restrictBoundsW, restrictBoundsH);

    // --- Step 2: Find TRUE total maxima across the whole rectangle ---
    selectWindow(imageTitle);
    roiManager("select", restrictROIIndex);
    run("Find Maxima...", "noise=" + noiseTolerance + " output=[Point Selection]");

    trueTotalMaxima = 0;
    if (selectionType() == 10) {
        getSelectionCoordinates(fieldXpoints, fieldYpoints);
        trueTotalMaxima = fieldXpoints.length;
    }
    run("Select None");

    print("True total maxima found across entire restricted rectangle: " + trueTotalMaxima);
    print("(This count, not the ROI-only count, will be used as the randomization budget per iteration)");

    // --- Choose folder to save randomized images ---
    saveImages = getBoolean("Save an image of each randomized iteration (red dots on black background)?");
    if (saveImages) {
        saveDir = getDirectory("Choose a folder to save randomized images");
    }

    // --- Results table for randomized points ---
    titleR1 = "Randomized_Distance_Measurements";
    titleR2 = "["+titleR1+"]";
    fr = titleR2;
    run("Table...", "name="+titleR2+" width=700 height=400");
    print(fr, "\\Headings:Iteration\tRandom_Index\tRandom_X\tRandom_Y\tFalls_In_ROI\tROI_Index\tROI_Name\tCenter_X\tCenter_Y\tDistance_px\tDistance_nm");

    totalRandomPoints = 0;
    totalRandomInROI = 0;
    dotRadiusPx = 5; // radius of drawn red circles in saved images, in pixels

    for (iter = 1; iter <= nIterations; iter++) {

        // Generate all random points for this iteration first (so we can draw + analyze)
        iterX = newArray(trueTotalMaxima);
        iterY = newArray(trueTotalMaxima);
        for (k = 0; k < trueTotalMaxima; k++) {
            iterX[k] = restrictBoundsX + random() * restrictBoundsW;
            iterY[k] = restrictBoundsY + random() * restrictBoundsH;
        }

        // --- Draw and save this iteration's image, if requested ---
        if (saveImages) {
            newImageTitle = "Randomized_iter" + iter;
            newImage(newImageTitle, "RGB black", restrictBoundsW, restrictBoundsH, 1);
            setColor(255, 0, 0); // red
            for (k = 0; k < trueTotalMaxima; k++) {
                // Convert to local coordinates relative to rectangle origin
                localX = iterX[k] - restrictBoundsX;
                localY = iterY[k] - restrictBoundsY;
                fillOval(localX - dotRadiusPx, localY - dotRadiusPx, dotRadiusPx * 2, dotRadiusPx * 2);
            }
            saveAs("PNG", saveDir + newImageTitle + ".png");
            close(newImageTitle + ".png");
        }

        // --- Check ROI membership + measure distances for this iteration ---
        for (k = 0; k < trueTotalMaxima; k++) {
            rx = iterX[k];
            ry = iterY[k];

            foundInROI = false;
            for (i = 0; i < nROIs; i++) {
                centerX = circleCenterX[i];
                centerY = circleCenterY[i];
                roiName = circleROIName[i];

                distancePx = sqrt(pow(rx - centerX, 2) + pow(ry - centerY, 2));

                if (distancePx <= radiusPx) {
                    distanceNm = distancePx * pixelWidth;
                    print(fr, iter + "\t" + k + "\t" + rx + "\t" + ry + "\tYES\t" + (i+1) + "\t" + roiName + "\t" + centerX + "\t" + centerY + "\t" + distancePx + "\t" + distanceNm);
                    totalRandomInROI++;
                    foundInROI = true;
                }
            }

            if (!foundInROI) {
                print(fr, iter + "\t" + k + "\t" + rx + "\t" + ry + "\tNO\t\t\t\t\t\t");
            }

            totalRandomPoints++;
        }
    }

    print("Randomization control complete!");
    print("Iterations run: " + nIterations);
    print("True total maxima per iteration (randomization budget): " + trueTotalMaxima);
    print("Total randomized points generated: " + totalRandomPoints);
    print("Total randomized points falling within any ROI: " + totalRandomInROI);
    print("Restricted rectangle size: " + restrictBoundsW + " x " + restrictBoundsH + " px");
    if (saveImages) {
        print("Randomized images saved to: " + saveDir);
    }

    saveRandom = getBoolean("Do you want to save the randomized results table?");
    if (saveRandom) {
        selectWindow(titleR1);
        saveAs("Results");
    }
}