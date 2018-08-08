/**
 * Image Filtering
 * This sketch will help us to adjust the filter values to optimize blob detection
 * 
 * Persistence algorithm by Daniel Shifmann:
 * http://shiffman.net/2011/04/26/opencv-matching-faces-over-time/
 *
 * @author: Jordi Tost (@jorditost)
 * @url: https://github.com/jorditost/ImageFiltering/tree/master/ImageFilteringWithBlobPersistence
 *
 * University of Applied Sciences Potsdam, 2014
 *
 * It requires the ControlP5 Processing library:
 * http://www.sojamo.de/libraries/controlP5/
 */

import gab.opencv.*;
import java.awt.Rectangle;
import processing.serial.*;

String myString = null;
Serial myPort;  // The serial port

float[] temps = new float[768];
String splitString[] = new String[1000];
float maxTemp = 0;
float minTemp = 500;
float scaleValue = 2;

OpenCV opencv;
PImage src, preProcessedImage, processedImage, contoursImage;

ArrayList<Contour> contours;

// List of detected contours parsed as blobs (every frame)
ArrayList<Contour> newBlobContours;

// List of my blob objects (persistent)
ArrayList<Blob> blobList;


// Number of blobs detected over all time. Used to set IDs.
int blobCount = 0;

float contrast = 1.35;
int brightness = 0;
int threshold = 75;
boolean useAdaptiveThreshold = true; // use basic thresholding
int thresholdBlockSize = 500;
int thresholdConstant = -20; // -20
int blobSizeThreshold = 10;
int blurSize = 8;
float lowTempThreshold = 20;
float highTempThreshold = 36;

PImage srcColour;
PImage srcGrey;

// Control vars
//ControlP5 cp5;
//int buttonColor;
//int buttonBgColor;

void setup() {
  //fullScreen();
  frameRate(15);
  //video = new Capture(this, 640, 480);
  //video = new Capture(this, 640, 480, "USB2.0 PC CAMERA");
  //video.start();


  // --------- heat code ---------
  // Print a list of connected serial devices in the console
  printArray(Serial.list());
  // Depending on where your sensor falls on this list, you
  // may need to change Serial.list()[0] to a different number
  myPort = new Serial(this, Serial.list()[0], 115200);
  myPort.clear();
  // Throw out the first chunk in case we caught it in the 
  // middle of a frame
  myString = myPort.readStringUntil(13);
  myString = null;
  // change to HSB color mode, this will make it easier to color
  // code the temperature data
  colorMode(HSB, 360, 100, 100);


  // --------- blob code --------- 
  opencv = new OpenCV(this, 640, 480);
  contours = new ArrayList<Contour>();

  // Blobs list
  blobList = new ArrayList<Blob>();

  //size(840, 480);
  size(1280, 960);
  

  // Init Controls
  //cp5 = new ControlP5(this);
  //initControls();

  // Set thresholding
  //toggleAdaptiveThreshold(useAdaptiveThreshold);
}

void getImage() {
  // Create a blank image, 
  srcColour = createImage(32,24, HSB);
  srcGrey = createImage(32,24, HSB);
  srcColour.loadPixels();
  srcGrey.loadPixels();
   
  // When there is a sizeable amount of data on the serial port
  // read everything up to the first linefeed
  if (myPort.available() > 5000) {
    myString = myPort.readStringUntil(13);

    // Limit the size of this array so that it doesn't throw
    // OutOfBounds later when calling "splitTokens"
    if (myString.length() > 4608) {
      myString = myString.substring(0, 4608);                                                                                                                                                                                                                                                                                                                                                            
    }

    // generate an array of strings that contains each of the comma
    // separated values
    splitString = splitTokens(myString, ",");

    // Reset our min and max temperatures per frame
    maxTemp = 0;
    minTemp = 500;

    if (splitString.length < 768) return;
    // For each floating point value, double check that we've acquired a number,
    // then determine the min and max temperature values for this frame
    for (int q = 0; q < 768; q++) {

      if (!Float.isNaN(float(splitString[q])) && float(splitString[q]) > maxTemp) {
        maxTemp = float(splitString[q]);
      } else if (!Float.isNaN(float(splitString[q])) && float(splitString[q]) < minTemp) {
        minTemp = float(splitString[q]);
      }
    }  

    // for each of the 768 values, map the temperatures between min and max
    // to the blue through red portion of the color space
    for (int q = 0; q < 768; q++) {

      if (!Float.isNaN(float(splitString[q]))) {
        temps[q] = constrain(map(float(splitString[q]), minTemp, maxTemp, 180, 360), 160, 360);
      } else {
        temps[q] = 0;
      }
    }
  }

    // Prepare variables needed to draw our heatmap
  int i = 0;
  //background(0);   // Clear the screen with a black background
  
    for (int y = 0; y < 24; y++) {
      for (int x = 0; x < 32; x++) {
      srcColour.set(x, y, color(temps[i], 100, map(temps[i], 180, 360, 40, 100)) );
      color c = color(0);
        float temp = map(temps[i], 180, 360, minTemp, maxTemp);
        if ((lowTempThreshold < temp) && (highTempThreshold > temp)) {
        c = color (map(temp, lowTempThreshold, highTempThreshold, 0, 100));
        }
      //srcGrey.set(x,y, color (map(temps[i], 180, 360, 0, 100)));
      srcGrey.set(x,y, c);
      i++;
    }
  }
  srcColour.updatePixels();
  srcColour.resize(640, 480);
  srcGrey.updatePixels();
  srcGrey.resize(640, 480);
}

void draw() {

  // Read last captured frame
  //if (video.available()) {
  //  video.read();
  //}

  // Load the new frame of our camera in to OpenCV
  //opencv.loadImage(video);
  getImage();
  
  opencv.loadImage(srcGrey); 
  src = opencv.getSnapshot();
  
  ///////////////////////////////
  // <1> PRE-PROCESS IMAGE
  // - Grey channel 
  // - Brightness / Contrast
  ///////////////////////////////
  
  // Gray channel
  opencv.gray();

  //opencv.brightness(brightness);
  opencv.contrast(contrast);

  // Save snapshot for display
  preProcessedImage = opencv.getSnapshot();

  ///////////////////////////////
  // <2> PROCESS IMAGE
  // - Threshold
  // - Noise Supression
  ///////////////////////////////

  // Adaptive threshold - Good when non-uniform illumination
  if (useAdaptiveThreshold) {

    // Block size must be odd and greater than 3
    if (thresholdBlockSize%2 == 0) thresholdBlockSize++;
    if (thresholdBlockSize < 3) thresholdBlockSize = 3;

    opencv.adaptiveThreshold(thresholdBlockSize, thresholdConstant);

    // Basic threshold - range [0, 255]
  } else {
    opencv.threshold(threshold);
  }

  // Invert (black bg, white blobs)
  //opencv.invert();

  // Reduce noise - Dilate and erode to close holes
  opencv.dilate();
  opencv.erode();

  // Blur
  opencv.blur(blurSize);

  // Save snapshot for display
  processedImage = opencv.getSnapshot();

  ///////////////////////////////
  // <3> FIND CONTOURS  
  ///////////////////////////////

  detectBlobs();
  // Passing 'true' sorts them by descending area.
  contours = opencv.findContours(true, true);

  // Save snapshot for display
  contoursImage = opencv.getSnapshot();

  updateBlobs();

// draw stuff
 // image(srcColour, 0, 0 );
/*
  // Generate the legend on the bottom of the screen
  textSize(32);

  // Find the difference between the max and min temperatures in this frame
  float tempDif = maxTemp - minTemp; 
  // Find 5 intervals between the max and min
  int legendInterval = round(tempDif / 5); 
  // Set the first legend key to the min temp
  int legendTemp = round(minTemp);

  // Print each interval temperature in its corresponding heatmap color
  for (int intervals = 0; intervals < 6; intervals++) {
    fill(constrain(map(legendTemp, minTemp, maxTemp, 180, 360), 160, 360), 100, 100);
    text(legendTemp+"°", 70*intervals, 390);
    legendTemp += legendInterval;
  }
*/


  // Display images
  displayImages();





}

///////////////////////
// Display Functions
///////////////////////

void displayImages() {

  
  
  image(srcColour, 0, 0);
  image(preProcessedImage, src.width, 0);
  image(processedImage, 0, src.height);
  image(srcColour, src.width, src.height);

  stroke(255);
  fill(255);
  textSize(22);
  text("Source", 10, 25); 
  text("Skin temperature", width/2 + 10, 25); 
  text("Processed Image", 10, height/2 + 25); 
  text("Tracked People", width/2 + 10, height/2 + 25);
  translate(width/2,height/2);
  // Contours
  displayContours();
  //displayContoursBoundingBoxes();

  // Blobs
  //displayBlobs();
}

void displayBlobs() {

  for (Blob b : blobList) {
    strokeWeight(1);
    b.displayTemp();
  }
}

void displayContours() {

  // Contours
  for (int i=0; i<contours.size(); i++) {

    Contour contour = contours.get(i);

    noFill();
    stroke(0, 255, 0);
    strokeWeight(3);
    contour.draw();
  }
}

void displayContoursBoundingBoxes() {

  for (int i=0; i<contours.size(); i++) {

    Contour contour = contours.get(i);
    Rectangle r = contour.getBoundingBox();

    if (//(contour.area() > 0.9 * src.width * src.height) ||
      (r.width < blobSizeThreshold || r.height < blobSizeThreshold))
      continue;

    stroke(255, 0, 0);
    fill(255, 0, 0, 150);
    strokeWeight(2);
    rect(r.x, r.y, r.width, r.height);
  }
}

////////////////////
// Blob Detection
////////////////////

void detectBlobs() {

  // Contours detected in this frame
  // Passing 'true' sorts them by descending area.
  contours = opencv.findContours(true, true);

  newBlobContours = getBlobsFromContours(contours);

  //println(contours.length);

  // Check if the detected blobs already exist are new or some has disappeared. 

  // SCENARIO 1 
  // blobList is empty
  if (blobList.isEmpty()) {
    // Just make a Blob object for every face Rectangle
    for (int i = 0; i < newBlobContours.size(); i++) {
      println("+++ New blob detected with ID: " + blobCount);
      blobList.add(new Blob(this, blobCount, newBlobContours.get(i)));
      blobCount++;
    }

    // SCENARIO 2 
    // We have fewer Blob objects than face Rectangles found from OpenCV in this frame
  } else if (blobList.size() <= newBlobContours.size()) {
    boolean[] used = new boolean[newBlobContours.size()];
    // Match existing Blob objects with a Rectangle
    for (Blob b : blobList) {
      // Find the new blob newBlobContours.get(index) that is closest to blob b
      // set used[index] to true so that it can't be used twice
      float record = 50000;
      int index = -1;
      for (int i = 0; i < newBlobContours.size(); i++) {
        float d = dist(newBlobContours.get(i).getBoundingBox().x, newBlobContours.get(i).getBoundingBox().y, b.getBoundingBox().x, b.getBoundingBox().y);
        //float d = dist(blobs[i].x, blobs[i].y, b.r.x, b.r.y);
        if (d < record && !used[i]) {
          record = d;
          index = i;
        }
      }
      // Update Blob object location
      used[index] = true;
      b.update(newBlobContours.get(index));
    }
    // Add any unused blobs
    for (int i = 0; i < newBlobContours.size(); i++) {
      if (!used[i]) {
        println("+++ New blob detected with ID: " + blobCount);
        blobList.add(new Blob(this, blobCount, newBlobContours.get(i)));
        //blobList.add(new Blob(blobCount, blobs[i].x, blobs[i].y, blobs[i].width, blobs[i].height));
        blobCount++;
      }
    }

    // SCENARIO 3 
    // We have more Blob objects than blob Rectangles found from OpenCV in this frame
  } else {
    // All Blob objects start out as available
    for (Blob b : blobList) {
      b.available = true;
    } 
    // Match Rectangle with a Blob object
    for (int i = 0; i < newBlobContours.size(); i++) {
      // Find blob object closest to the newBlobContours.get(i) Contour
      // set available to false
      float record = 50000;
      int index = -1;
      for (int j = 0; j < blobList.size(); j++) {
        Blob b = blobList.get(j);
        float d = dist(newBlobContours.get(i).getBoundingBox().x, newBlobContours.get(i).getBoundingBox().y, b.getBoundingBox().x, b.getBoundingBox().y);
        //float d = dist(blobs[i].x, blobs[i].y, b.r.x, b.r.y);
        if (d < record && b.available) {
          record = d;
          index = j;
        }
      }
      // Update Blob object location
      Blob b = blobList.get(index);
      b.available = false;
      b.update(newBlobContours.get(i));
    } 
    // Start to kill any left over Blob objects
    for (Blob b : blobList) {
      if (b.available) {
        b.countDown();
        if (b.dead()) {
          b.delete = true;
        }
      }
    }
    
    
    
    
  }

  // Delete any blob that should be deleted
  for (int i = blobList.size()-1; i >= 0; i--) {
    Blob b = blobList.get(i);
    if (b.delete) {
      blobList.remove(i);
    }
  }
}

void updateBlobs() {
  for (int i = blobList.size()-1; i >= 0; i--) {
    Blob b = blobList.get(i);
    if (!b.delete) {
      updateBlobTemp(b);
    }
  }
  
}

void updateBlobTemp(Blob b) {
          // update temps for blobs
        Rectangle r = b.contour.getBoundingBox();
        int x = round( r.x + (r.width/2)); 
        int y = round (r.y + (r.height/2));
        //println("x = " + x + " y = " + y);
        color c = get(x,y);
        b.temp = round(map(hue(c), 160,360, minTemp, maxTemp));
}

ArrayList<Contour> getBlobsFromContours(ArrayList<Contour> newContours) {

  ArrayList<Contour> newBlobs = new ArrayList<Contour>();

  // Which of these contours are blobs?
  for (int i=0; i<newContours.size(); i++) {

    Contour contour = newContours.get(i);
    Rectangle r = contour.getBoundingBox();

    if (//(contour.area() > 0.9 * src.width * src.height) ||
      (r.width < blobSizeThreshold || r.height < blobSizeThreshold))
      continue;

    newBlobs.add(contour);
  }

  return newBlobs;
}

//////////////////////////
// CONTROL P5 Functions
//////////////////////////

/*
void initControls() {
  // Slider for contrast
  cp5.addSlider("contrast")
    .setLabel("contrast")
    .setPosition(20, 50)
    .setRange(0.0, 6.0)
    ;

  // Slider for threshold
  cp5.addSlider("threshold")
    .setLabel("threshold")
    .setPosition(20, 110)
    .setRange(0, 255)
    ;

  // Toggle to activae adaptive threshold
  cp5.addToggle("toggleAdaptiveThreshold")
    .setLabel("use adaptive threshold")
    .setSize(10, 10)
    .setPosition(20, 144)
    ;

  // Slider for adaptive threshold block size
  cp5.addSlider("thresholdBlockSize")
    .setLabel("a.t. block size")
    .setPosition(20, 180)
    .setRange(1, 700)
    ;

  // Slider for adaptive threshold constant
  cp5.addSlider("thresholdConstant")
    .setLabel("a.t. constant")
    .setPosition(20, 200)
    .setRange(-100, 100)
    ;

  // Slider for blur size
  cp5.addSlider("blurSize")
    .setLabel("blur size")
    .setPosition(20, 260)
    .setRange(1, 20)
    ;

  // Slider for minimum blob size
  cp5.addSlider("blobSizeThreshold")
    .setLabel("min blob size")
    .setPosition(20, 290)
    .setRange(0, 60)
    ;

  // Store the default background color, we gonna need it later
  buttonColor = cp5.getController("contrast").getColor().getForeground();
  buttonBgColor = cp5.getController("contrast").getColor().getBackground();
}
*/

/*void toggleAdaptiveThreshold(boolean theFlag) {

  useAdaptiveThreshold = theFlag;

  if (useAdaptiveThreshold) {

    // Lock basic threshold
    setLock(cp5.getController("threshold"), true);

    // Unlock adaptive threshold
    setLock(cp5.getController("thresholdBlockSize"), false);
    setLock(cp5.getController("thresholdConstant"), false);
  } else {

    // Unlock basic threshold
    setLock(cp5.getController("threshold"), false);

    // Lock adaptive threshold
    setLock(cp5.getController("thresholdBlockSize"), true);
    setLock(cp5.getController("thresholdConstant"), true);
  }
}*/

/*void setLock(Controller theController, boolean theValue) {

  theController.setLock(theValue);

  if (theValue) {
    theController.setColorBackground(color(150, 150));
    theController.setColorForeground(color(100, 100));
  } else {
    theController.setColorBackground(color(buttonBgColor));
    theController.setColorForeground(color(buttonColor));
  }
}*/
