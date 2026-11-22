// ImageJ Macro (.ijm)
// Nearest Neighbor Distance (NND) between reference and target maxima,
// detected directly from two images (instead of CSV files), restricted
// to user-defined circular ROIs.
//
// Workflow:
// 1. User picks a REFERENCE image and a TARGET image (must be open already,
//    and spatially aligned/registered to each other).
// 2. ROI Manager must contain square/rectangular ROIs (same as used in the
//    Radial Distance macro) marking the regions of interest.
// 3. For each ROI, a circle of user-defined radius is built around its
//    center. Find Maxima is run inside that circle on BOTH the reference
//    and target images separately.
// 4. For each reference maximum, the nearest target maximum within the
//    SAME ROI is found (nearest-neighbor), and the distance is recorded.

// --------------------
// Settings
// --------------------
sameROIOnly = true;   // only match reference/target points within the same ROI
nearestOnly = true;   // true = keep only nearest target for each reference object

// --------------------
// Check prerequisites
// --------------------
if (nImages < 2) {
    exit("Please open both a reference image and a target image first.");
}
if (roiManager("count") == 0) {
    exit("Please load ROIs into the ROI Manager first (square/rectangular ROIs).");
}

// --------------------
// Pick reference and target images
// --------------------
imageList = getList("image.titles");
Dialog.create("Select Images");
Dialog.addChoice("Reference image:", imageList, imageList[0]);
Dialog.addChoice("Target image:", imageList, imageList[1]);
Dialog.addNumber("Noise Tolerance (Reference):", 10);
Dialog.addNumber("Noise Tolerance (Target):", 10);
Dialog.addNumber("Circle Radius (nm):", 150);
Dialog.addNumber("Maximum NND to keep (nm, 0 = no limit):", 0);
Dialog.show();

refImage = Dialog.getChoice();
tgtImage = Dialog.getChoice();
noiseTolRef = Dialog.getNumber();
noiseTolTgt = Dialog.getNumber();
radiusNm = Dialog.getNumber();
maxNNDNm = Dialog.getNumber();

if (refImage == tgtImage) {
    exit("Reference and target images must be different.");
}

// --------------------
// Get pixel size from reference image (assumes both images share calibration)
// --------------------
selectWindow(refImage);
getPixelSize(unit, pixelWidth, pixelHeight);
if (unit != "nm") {
    showMessage("Warning", "Reference image may not be scaled in nm.\nCurrent unit: " + unit);
}
radiusPx = radiusNm / pixelWidth;

// --------------------
// Store original square ROI info BEFORE any changes
// --------------------
nROIs = roiManager("count");
squareROIs = newArray(nROIs);
for (i = 0; i < nROIs; i++) {
    roiManager("select", i);
    Roi.getBounds(roiX, roiY, roiWidth, roiHeight);
    roiName = Roi.getName();
    squareROIs[i] = "" + roiX + "," + roiY + "," + roiWidth + "," + roiHeight + "," + roiName;
}

clearROIs = getBoolean("Clear existing ROIs and replace with circles?");
if (clearROIs) {
    roiManager("reset");
}

// --------------------
// Helper arrays: per-ROI geometry
// --------------------
circleCenterX = newArray(nROIs);
circleCenterY = newArray(nROIs);
circleROIName = newArray(nROIs);

// --------------------
// Collect REFERENCE maxima per ROI
// --------------------
// Flat arrays across all ROIs combined
refROIIndex = newArray(0);
refX = newArray(0);
refY = newArray(0);
refID = newArray(0);

// --------------------
// Collect TARGET maxima per ROI
// --------------------
tgtROIIndex = newArray(0);
tgtX = newArray(0);
tgtY = newArray(0);
tgtID = newArray(0);

for (i = 0; i < nROIs; i++) {
    parts = split(squareROIs[i], ",");
    roiX = parseInt(parts[0]);
    roiY = parseInt(parts[1]);
    roiWidth = parseInt(parts[2]);
    roiHeight = parseInt(parts[3]);
    roiName = parts[4];

    centerX = roiX + floor(roiWidth / 2);
    centerY = roiY + floor(roiHeight / 2);

    circleCenterX[i] = centerX;
    circleCenterY[i] = centerY;
    circleROIName[i] = roiName;

    // Add circle ROI to manager (for visual reference / reuse)
    selectWindow(refImage);
    makeOval(centerX - radiusPx, centerY - radiusPx, radiusPx * 2, radiusPx * 2);
    roiManager("add");
    roiManager("select", roiManager("count") - 1);
    roiManager("rename", "Circle_" + (i+1) + "_" + roiName);
    circleROIIndex = roiManager("count") - 1;

    // --- Find maxima on REFERENCE image within this circle ---
    selectWindow(refImage);
    roiManager("select", circleROIIndex);
    run("Find Maxima...", "noise=" + noiseTolRef + " output=[Point Selection]");

    if (selectionType() == 10) {
        getSelectionCoordinates(xr, yr);
        for (k = 0; k < xr.length; k++) {
            refROIIndex = Array.concat(refROIIndex, i);
            refX = Array.concat(refX, xr[k]);
            refY = Array.concat(refY, yr[k]);
            refID = Array.concat(refID, "Ref_ROI" + (i+1) + "_ID" + (k+1));
        }
    }

    // --- Find maxima on TARGET image within the same circle ---
    selectWindow(tgtImage);
    roiManager("select", circleROIIndex);
    run("Find Maxima...", "noise=" + noiseTolTgt + " output=[Point Selection]");

    if (selectionType() == 10) {
        getSelectionCoordinates(xt, yt);
        for (k = 0; k < xt.length; k++) {
            tgtROIIndex = Array.concat(tgtROIIndex, i);
            tgtX = Array.concat(tgtX, xt[k]);
            tgtY = Array.concat(tgtY, yt[k]);
            tgtID = Array.concat(tgtID, "Tgt_ROI" + (i+1) + "_ID" + (k+1));
        }
    }

    run("Select None");
}

refCount = refX.length;
tgtCount = tgtX.length;

// --------------------
// Compute Nearest Neighbor Distances
// --------------------
tableName = "NND_Results";
run("Table...", "name=" + tableName + " width=1400 height=500");
print("[" + tableName + "]", "\\Headings:ROI_Number\tROI_Name\tRef_ID\tRef_X\tRef_Y\tTgt_ID\tTgt_X\tTgt_Y\tDistance_px\tDistance_nm");

keptPairs = 0;
skippedByROI = 0;
skippedByMaxDist = 0;
refsWithNoMatch = 0;

maxNNDPx = -1;
if (maxNNDNm > 0) {
    maxNNDPx = maxNNDNm / pixelWidth;
}

if (nearestOnly == false) {
    // Report ALL ref-target pairs (within same ROI if sameROIOnly)
    for (i = 0; i < refCount; i++) {
        for (j = 0; j < tgtCount; j++) {
            if (sameROIOnly && refROIIndex[i] != tgtROIIndex[j]) {
                skippedByROI++;
                continue;
            }

            dx = refX[i] - tgtX[j];
            dy = refY[i] - tgtY[j];
            d = sqrt(dx * dx + dy * dy);

            if (maxNNDPx > 0 && d > maxNNDPx) {
                skippedByMaxDist++;
                continue;
            }

            dNm = d * pixelWidth;
            roiIdx = refROIIndex[i];
            print("[" + tableName + "]",
                (roiIdx+1) + "\t" + circleROIName[roiIdx] + "\t" +
                refID[i] + "\t" + refX[i] + "\t" + refY[i] + "\t" +
                tgtID[j] + "\t" + tgtX[j] + "\t" + tgtY[j] + "\t" +
                d + "\t" + dNm
            );
            keptPairs++;
        }
    }
} else {
    // Nearest target only, per reference point
    for (i = 0; i < refCount; i++) {
        foundMatch = 0;
        bestD = -1;
        bestJ = -1;

        for (j = 0; j < tgtCount; j++) {
            if (sameROIOnly && refROIIndex[i] != tgtROIIndex[j]) {
                skippedByROI++;
                continue;
            }

            dx = refX[i] - tgtX[j];
            dy = refY[i] - tgtY[j];
            d = sqrt(dx * dx + dy * dy);

            if (maxNNDPx > 0 && d > maxNNDPx) {
                continue;
            }

            if (foundMatch == 0 || d < bestD) {
                bestD = d;
                bestJ = j;
                foundMatch = 1;
            }
        }

        if (foundMatch == 1) {
            dNm = bestD * pixelWidth;
            roiIdx = refROIIndex[i];
            print("[" + tableName + "]",
                (roiIdx+1) + "\t" + circleROIName[roiIdx] + "\t" +
                refID[i] + "\t" + refX[i] + "\t" + refY[i] + "\t" +
                tgtID[bestJ] + "\t" + tgtX[bestJ] + "\t" + tgtY[bestJ] + "\t" +
                bestD + "\t" + dNm
            );
            keptPairs++;
        } else {
            refsWithNoMatch++;
        }
    }
}

print("Done.");
print("Reference image: " + refImage + " (noise tolerance " + noiseTolRef + ")");
print("Target image: " + tgtImage + " (noise tolerance " + noiseTolTgt + ")");
print("Circle radius: " + radiusNm + " nm (" + radiusPx + " px)");
if (maxNNDNm > 0) {
    print("Maximum NND kept: " + maxNNDNm + " nm");
}
print("ROIs processed: " + nROIs);
print("Reference maxima found: " + refCount);
print("Target maxima found: " + tgtCount);
print("Same ROI only: " + sameROIOnly);
print("Nearest only: " + nearestOnly);
print("Rows written: " + keptPairs);
print("Skipped (different ROI): " + skippedByROI);
if (maxNNDNm > 0) {
    print("Skipped (exceeded max NND): " + skippedByMaxDist);
}
print("Reference objects with no valid target match: " + refsWithNoMatch);

// --------------------
// Save results
// --------------------
saveResults = getBoolean("Do you want to save the NND results table?");
if (saveResults) {
    selectWindow(tableName);
    saveAs("Results");
}

// ============================================================
// RANDOMIZATION CONTROL (TARGET)
// Mirrors the Radial Distance macro's randomization logic:
// 1. User draws a restricted rectangle on the target image.
// 2. Find Maxima is run ONCE on that whole rectangle to get the
//    TRUE total target maxima count in the field (not just the
//    sum found inside individual ROI circles).
// 3. For each iteration, that many random points are scattered
//    across the rectangle (optionally saved as a red-dot PNG),
//    and NND is computed from each REAL reference point to the
//    nearest RANDOM target point within the same ROI circle.
// ============================================================
doRandomization = getBoolean("Also run randomization control on the TARGET channel?");

if (doRandomization) {

    nIterations = getNumber("Number of randomization iterations:", 1);

    selectWindow(tgtImage);
    imgWidth = getWidth();
    imgHeight = getHeight();

    // --- Step 1: Draw restricted rectangle on target image ---
    run("Select None");
    waitForUser("Draw restricted area", "On the TARGET image, draw a RECTANGLE outlining\nthe region where random target points should be placed.\n\nClick OK when your selection is ready.");

    if (selectionType() != 0) {
        exit("A rectangular selection is required for this randomization method. Please re-run and draw a rectangle.");
    }

    roiManager("add");
    restrictROIIndex = roiManager("count") - 1;
    roiManager("select", restrictROIIndex);
    roiManager("rename", "Randomization_Restricted_Area");
    Roi.getBounds(restrictBoundsX, restrictBoundsY, restrictBoundsW, restrictBoundsH);

    // --- Step 2: Find TRUE total target maxima across the whole rectangle ---
    selectWindow(tgtImage);
    roiManager("select", restrictROIIndex);
    run("Find Maxima...", "noise=" + noiseTolTgt + " output=[Point Selection]");

    trueTotalTgtMaxima = 0;
    if (selectionType() == 10) {
        getSelectionCoordinates(fieldXpoints, fieldYpoints);
        trueTotalTgtMaxima = fieldXpoints.length;
    }
    run("Select None");

    print("True total TARGET maxima found across entire restricted rectangle: " + trueTotalTgtMaxima);
    print("(This count, not the ROI-only sum, is used as the randomization budget per iteration)");

    // --- Choose whether to save images of each randomized iteration ---
    saveImages = getBoolean("Save an image of each randomized target iteration (red dots on black background)?");
    if (saveImages) {
        saveDir = getDirectory("Choose a folder to save randomized target images");
    }

    // --- Results table for randomized NND ---
    titleR1 = "Randomized_NND_Results";
    titleR2 = "["+titleR1+"]";
    fr = titleR2;
    run("Table...", "name="+titleR2+" width=1400 height=500");
    print(fr, "\\Headings:Iteration\tROI_Number\tROI_Name\tRef_ID\tRef_X\tRef_Y\tRandom_Tgt_X\tRandom_Tgt_Y\tDistance_px\tDistance_nm");

    dotRadiusPx = 5; // radius of drawn red circles in saved images, in pixels
    totalRandomNNDRows = 0;
    refsWithNoRandomMatch = 0;

    for (iter = 1; iter <= nIterations; iter++) {

        // Generate all random target points for this iteration
        iterX = newArray(trueTotalTgtMaxima);
        iterY = newArray(trueTotalTgtMaxima);
        for (k = 0; k < trueTotalTgtMaxima; k++) {
            iterX[k] = restrictBoundsX + random() * restrictBoundsW;
            iterY[k] = restrictBoundsY + random() * restrictBoundsH;
        }

        // --- Save this iteration's image, if requested ---
        if (saveImages) {
            newImageTitle = "Randomized_Target_iter" + iter;
            newImage(newImageTitle, "RGB black", restrictBoundsW, restrictBoundsH, 1);
            setColor(255, 0, 0); // red
            for (k = 0; k < trueTotalTgtMaxima; k++) {
                localX = iterX[k] - restrictBoundsX;
                localY = iterY[k] - restrictBoundsY;
                fillOval(localX - dotRadiusPx, localY - dotRadiusPx, dotRadiusPx * 2, dotRadiusPx * 2);
            }
            saveAs("PNG", saveDir + newImageTitle + ".png");
            close(newImageTitle + ".png");
        }

        // --- For each ROI, restrict random target points to that ROI's circle ---
        for (i = 0; i < nROIs; i++) {
            centerX = circleCenterX[i];
            centerY = circleCenterY[i];
            roiName = circleROIName[i];

            // Find which random points fall within this ROI's circle
            roiRandX = newArray(0);
            roiRandY = newArray(0);
            for (k = 0; k < trueTotalTgtMaxima; k++) {
                dx = iterX[k] - centerX;
                dy = iterY[k] - centerY;
                d = sqrt(dx*dx + dy*dy);
                if (d <= radiusPx) {
                    roiRandX = Array.concat(roiRandX, iterX[k]);
                    roiRandY = Array.concat(roiRandY, iterY[k]);
                }
            }

            // For each REAL reference point in this ROI, find nearest random target point
            for (i2 = 0; i2 < refCount; i2++) {
                if (refROIIndex[i2] != i) continue;

                foundMatch = 0;
                bestD = -1;
                bestK = -1;
                for (k = 0; k < roiRandX.length; k++) {
                    dx = refX[i2] - roiRandX[k];
                    dy = refY[i2] - roiRandY[k];
                    d = sqrt(dx*dx + dy*dy);

                    if (maxNNDPx > 0 && d > maxNNDPx) continue;

                    if (foundMatch == 0 || d < bestD) {
                        bestD = d;
                        bestK = k;
                        foundMatch = 1;
                    }
                }

                if (foundMatch == 1) {
                    dNm = bestD * pixelWidth;
                    print(fr, iter + "\t" + (i+1) + "\t" + roiName + "\t" +
                        refID[i2] + "\t" + refX[i2] + "\t" + refY[i2] + "\t" +
                        roiRandX[bestK] + "\t" + roiRandY[bestK] + "\t" +
                        bestD + "\t" + dNm
                    );
                    totalRandomNNDRows++;
                } else {
                    refsWithNoRandomMatch++;
                }
            }
        }
    }

    print("Randomization control complete!");
    print("Iterations run: " + nIterations);
    print("True total target maxima per iteration (randomization budget): " + trueTotalTgtMaxima);
    print("Randomized NND rows written: " + totalRandomNNDRows);
    print("Reference points with no random match (within maxNND, if set): " + refsWithNoRandomMatch);
    print("Restricted rectangle size: " + restrictBoundsW + " x " + restrictBoundsH + " px");
    if (saveImages) {
        print("Randomized target images saved to: " + saveDir);
    }

    saveRandomNND = getBoolean("Do you want to save the randomized NND results table?");
    if (saveRandomNND) {
        selectWindow(titleR1);
        saveAs("Results");
    }
}