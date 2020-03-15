/*  //<>// //<>//
 * Test
 * http://processing.org/reference/PVector.html
 * https://code.google.com/p/processing/source/browse/trunk/processing/core/src/processing/core/PVector.java
 */
 
import papaya.*;

static int sampleSize = 1;
static int memorySize = 2; // minimum 2
static final int maxSampleSize = 10;
static final int maxMemorySize = 2;
int fixedRotation = 137; // degrees
int currentDirectionAngle = 0; // degrees
int previousDirectionAngle = 0; // degrees

int randomSeedNumber = 1;

int canvasWidth = 1000;
int canvasHeight = 1000;
int shapeWidth = 6;
int shapeHeight = 6;
boolean stopExecSeq = false;

PVector[]  prey = new PVector[2]; //prey[1] is not used
PVector[]  hunter = new PVector[2];
PVector[]  probe = new PVector[3]; // not used in running median algorithm
PVector[]  guess = new PVector[2];
PVector    waypoint = new PVector();

int pixels_per_meter = 10;
float cycle_duration = 0.5; // sec (matches the RSS broadcast interval)
int preyStep = 5; // pixels
int hunterStep = 10; // pixels
int probeStep = 10; // pixels (not used in running median algorithm)
final int maxPreyStep = preyStep; // pixels
//int preyStep = round((prey_speed*1000/3600)*frame_duration*pixels_per_meter);
//int hunterStep = round((hunter_speed*1000/3600)*frame_duration*pixels_per_meter);
float prey_speed = (preyStep*3600)/(1000*cycle_duration*pixels_per_meter); // km/h
float hunter_speed = (hunterStep*3600)/(1000*cycle_duration*pixels_per_meter); // km/h

float TX_dBm = 0; // 1mW
float RXsens_dBm = -94; // RX sensitivity
float stand_dev_Xg = 0; // The standard deviation of the Guassian random variable with mean zero (Xg) in dB, that corresponds to flat fading (shadowing)
float TXantGain_dBm = 0;
float RXantGain_dBm = 2;
float freq_MHz = 2400;
float pathLossExponent = 2.8;
int stopThreshold_meters = 3;
float stopThreshold_dBm = TX_dBm -((pathLossExponent/2)*20*log(stopThreshold_meters)/log(10) + (pathLossExponent/2)*20*log(freq_MHz*1000000)/log(10) - (pathLossExponent/2)*147.55 - TXantGain_dBm - RXantGain_dBm); // frequency should not be weighted by the pathLossExponent. Just should use 2.

float[] distance = new float[2]; // pixels
float[] RSS = new float[sampleSize]; // dBm
float[] medianRSS = new float[memorySize]; // dBm
int sampleCounter = 0;
int memoryCounter = 0;

boolean inRange = false;
boolean inStep = false;
float range = pow(10, (-(pathLossExponent/2)*20*log(freq_MHz*1000000)/log(10) + (pathLossExponent/2)*147.55 + TXantGain_dBm + RXantGain_dBm + (TX_dBm-RXsens_dBm))/((pathLossExponent/2)*20)) * pixels_per_meter; // pixels

float percentError = 0;

int counter = 0;
int counterEnd = 2000;
int cycleRangeOut = counterEnd;
int counterInRange = 0;

float totalDistance = 0;
float totalDistanceGuess = 0;
float totalRelativeError = 0;
int counterInStep = 0;
int counterHalted = 0;
boolean halted = false;
final static boolean haltInSampleReadings = false; // Option to stay still while taking sample RSS readings
boolean sample_halt = false;

int waypointPeriod = 100;
int preyBiasX = 90;
int preyBiasY = 50;

PrintWriter output;
PrintWriter statsOutput;

void preyAppears() {
  prey[0].set( (int) (canvasWidth/2), (int) (canvasHeight/2), 0);

  fill(255, 0, 0);
  ellipse(prey[0].x, prey[0].y, shapeWidth, shapeHeight);

  randomSeed(randomSeedNumber);

  inRange = false;
  inStep = false;
  cycleRangeOut = counterEnd;
  counterInRange = 0;

  counter = 0;

  totalDistance = 0;
  totalDistanceGuess = 0;
  totalRelativeError = 0;
  counterInStep = 0;
  counterHalted = 0;

  // We assume that estimated distance has the same effect as estimated RSS (used instead).
  distance[0] = -1; // Previous estimated distance between Hunter and Prey
  distance[1] = -1; // Current estimated distance between Hunter and Prey
  
  RSS = new float[sampleSize]; // dBm
  medianRSS = new float[memorySize]; // dBm
  sampleCounter = 0;
  memoryCounter = 0;
}

void waypointAppears() {
  waypoint.y = (int) random(canvasWidth);
  waypoint.x = (int) random(canvasHeight);
  println("WX: "+ waypoint.x + "WY: "+ waypoint.y);
}

void hunterAppears() {
  hunter[0].x = prey[0].x; //(int) random(prey[0].x - range/2, prey[0].x + range/2);
  hunter[0].y = prey[0].y + range/2; //(int) sqrt(range*range/4 - (hunter[0].x - prey[0].x)*(hunter[0].x - prey[0].x));
  /*if (random(10) < 5) {
    hunter[0].y = hunter[0].y + prey[0].y;
  }
  else {
    hunter[0].y = -hunter[0].y + prey[0].y;
  }*/

  fill(0, 255, 0);
  ellipse(hunter[0].x, hunter[0].y, shapeWidth, shapeHeight);
}


void setup() {
  size (800, 800);
  surface.setResizable(true);
  surface.setSize(canvasWidth, canvasHeight);

  prey[0] = new PVector();
  prey[1] = new PVector();

  hunter[0] = new PVector();
  hunter[1] = new PVector();

  probe[0] = new PVector();
  probe[1] = new PVector();
  probe[2] = new PVector();

  guess[0] = new PVector();
  guess[1] = new PVector();
  
  noStroke();
  smooth();

  preyAppears();
  hunterAppears();
  waypointAppears();

  output = createWriter("output.csv");
  statsOutput = createWriter("statsOutput.csv");

  println("Fading Gauss SD, Prey Step, Hunter Step, Probe Step, Average Distance, Average Distance Guess, Number of Cycles, Number of Cycles in Range, Number of Cycles in Step, Number of Cycles in Halt, Mean Relative Error, Prey Speed, Hunter Speed, Cycle Duration, Sample Size, Memory Size");
  statsOutput.println("Fading Gauss SD, Prey Step, Hunter Step, Probe Step, Average Distance, Average Distance Guess, Number of Cycles, Number of Cycles in Range, Number of Cycles in Step, Number of Cycles in Halt, Mean Relative Error, Prey Speed, Hunter Speed, Cycle Duration, Sample Size, Memory Size");
  output.println("Hunter X, Hunter Y, Prey X, Prey Y, Guess X, Guess Y, Distance, Distance Guess, In Range, In Step");
}


void hunterTracks() {
   
  //fill(255, 255, 255);
  //ellipse(hunter[0].x, hunter[0].y, shapeWidth, shapeHeight);
  distance[0] = distance[1]; // set latest current value as previous  
  distance[1] = hunter[0].dist(prey[0]);
  RSS[sampleCounter] = TX_dBm -((pathLossExponent/2)*20*log(distance[1]/pixels_per_meter)/log(10) + (pathLossExponent/2)*20*log(freq_MHz*1000000)/log(10) - (pathLossExponent/2)*147.55 - TXantGain_dBm - RXantGain_dBm);
  RSS[sampleCounter] += stand_dev_Xg*(randomGaussian());
  //halted = false;
  previousDirectionAngle = currentDirectionAngle;
      
    // in case of 1st execution we have no previous estimation of distance (i.e. RSS)
    if (distance[0] == -1) {
      distance[0] = distance[1];
      if (sampleCounter == sampleSize - 1){
          if (sampleSize == 1) {
            medianRSS[memoryCounter] = RSS[sampleCounter];
          } else {
            medianRSS[memoryCounter] = Descriptive.mean(RSS); //median(RSS, false);
          }
          sampleCounter = 0;
      } else {
        sampleCounter++;
        sample_halt = true;
      }
    } else { 
      if (RSS[sampleCounter] >= stopThreshold_dBm){
        halted = true;
        counterHalted++;
      
        if (sampleCounter == sampleSize - 1){
          if (sampleSize == 1) {
            medianRSS[memoryCounter] = RSS[sampleCounter];
          } else {
            medianRSS[memoryCounter] = Descriptive.mean(RSS); //median(RSS, false);
          }
          sampleCounter = 0;
          if (memoryCounter == memorySize - 1){
            memoryCounter = 0;
          } else {
              memoryCounter++;
          } 
        } else {
          sampleCounter++;
        }
        return;
      }
      
    if (sampleCounter == sampleSize - 1){
        sampleCounter = 0;
        if (sampleSize == 1) {
          medianRSS[memoryCounter] = RSS[sampleCounter];
        } else {
          medianRSS[memoryCounter] = Descriptive.mean(RSS); //median(RSS, false);
        }
        if (memoryCounter == memorySize - 1){
          memoryCounter = 0;
          int intHotOrCold = 0;
          for (int i=0; i<memorySize-1; i++){
            if (medianRSS[i+1] > medianRSS[i]){
              intHotOrCold += 1;
            } else if (medianRSS[i+1] < medianRSS[i]){
              intHotOrCold -= 1;
            }
          }
          if (intHotOrCold < 0){
            /*
            if (((int) random(0, 2)) == 0){
              fixedRotation = (int) random(135, 181); // random turn 135 to 225 degrees
            } else {
              fixedRotation = (int) random(180, 226); // random turn 135 to 225 degrees
            }
            */
            if (!halted){ // NEW ADDITION: If hunter was halted and now has to move, do not turn!
              currentDirectionAngle = (currentDirectionAngle + fixedRotation)%360;
            }

          } /*else if (intHotOrCold == 0){ // JUST A TEST. REMOVE THIS ELSE IF NEST
            halted = true;
          }*/
        } else {
          memoryCounter++;      
        }
      } else {
        sampleCounter++;
        sample_halt = true;
      }
    }
    halted = false; //NEW ADDITION: If halted is set to true in this cycle, the function has already returned earlier.
  }

  void hunterFollows() {

    //halted = true; // CONTROL SCENARIO: HUNTER DOES NOT FOLLOW AT ALL
    
    if (!halted){
      if (!sample_halt || !haltInSampleReadings){
        hunter[0].x += hunterStep*cos(currentDirectionAngle*TWO_PI/360);
        hunter[0].y += hunterStep*sin(currentDirectionAngle*TWO_PI/360);
      }
    }
    //halted = false;
    sample_halt = false;

    fill(0, 255, 0);
    ellipse(hunter[0].x, hunter[0].y, shapeWidth, shapeHeight);

    text("range (meters): "+ range/pixels_per_meter, 15, 15*2);
    if (counter > 0) {
      text("current RSS: "+ RSS[(sampleSize-1 + sampleCounter) % sampleSize], 15, 15*3);
      text("median RSS: "+ medianRSS[(memorySize-1 + memoryCounter) % memorySize], 15, 15*4);
    }
    if (currentDirectionAngle != previousDirectionAngle){
      text("NEW DIRECTION ANGLE: "+ currentDirectionAngle, 15, 15*6);
    }
    text("Prey Speed (km/h): "+ prey_speed, 15, 15*8);
    text("Hunter Speed (km/h): "+ hunter_speed, 15, 15*9);
    
    text("Sample Size: "+ sampleSize, 15, 15*10);
    text("Memory Size: "+ memorySize, 15, 15*11);
    
    text("stand_dev_Xg: " + stand_dev_Xg, 15, 15 * 20);  
    PFont f = createFont("Courier", 11);
    textFont(f);

  }

  // Named and modeled after the new Hunter Follows method.
  void preyFollows() {
    PVector temp = new PVector();
    temp.set(waypoint);
    temp.sub(prey[0]);
    temp.limit(preyStep); //*random(0, 1));
    prey[0].add(temp); //temp.add(prey[0]);

    //prey[0].set(temp);
  }

  void preyFlees() {

    /* ---------------------------------------------
     // 1st Way: Random Walk with Branching every nth iterations
     int preyBias;  
     //Prey changes direction on the Y axis every nth iterations.
     preyBias = (((int) counter/preyBiasY) % 2) - 1;
     
     prey[0].y = random (prey[0].y+preyStep*preyBias, prey[0].y+preyStep*(preyBias+1));
     
     //Prey changes direction on the X axis every nth iterations.
     preyBias = (((int) counter/preyBiasX) % 2) - 1;
     prey[0].x = random (prey[0].x+preyStep*preyBias, prey[0].x+preyStep*(preyBias+1));
     // ---------------------------------------------
     */
    //2nd Way: Random Walk with new Way Point every nth iterations
    // Prey follows a new way point every nth iterations.
    if ( counter % waypointPeriod == 0 ) {
      waypointAppears();
    }
    preyFollows();
    // ---------------------------------------------

    if (prey[0].x < 0) {
      prey[0].x = -prey[0].x;
    }
    if (prey[0].x > canvasWidth) {
      prey[0].x = canvasWidth - (prey[0].x - canvasWidth);
    } 
    if (prey[0].y < 0) {
      prey[0].y = -prey[0].y;
    }
    if (prey[0].y > canvasHeight) {
      prey[0].y = canvasHeight - (prey[0].y - canvasHeight);
    }

    fill(255, 0, 0);
    ellipse(prey[0].x, prey[0].y, shapeWidth, shapeHeight);
  }

  void draw() {
    background(0, 0, 0);

    if (distance[0]<range) {
      inRange = true;
      counterInRange++;
    } else {
      inRange = false;
      if (cycleRangeOut == counterEnd) {
        cycleRangeOut = counter;
      }
    }

    if (distance[0]<hunterStep) {
      inStep = true;
      counterInStep = counterInStep + 1;
    } else {
      inStep = false;
    }

    if (counter > 0) {
      totalDistance = totalDistance + hunter[0].dist(prey[0]);
      totalDistanceGuess = totalDistanceGuess + hunter[0].dist(guess[0]); // "Guess" is not applicable in Markov algorithm
      totalRelativeError = totalRelativeError + (abs((prey[0].x - guess[0].x)/prey[0].x) + abs((prey[0].y - guess[0].y)/prey[0].y))/2; // "Guess" is not applicable in Markov algorithm
    }

    output.println(hunter[0].x + ", " + hunter[0].y +", " + prey[0].x +", " + prey[0].y + ", " + guess[0].x +", " + guess[0].y +", " + hunter[0].dist(prey[0]) 
      + ", " + hunter[0].dist(guess[0]) + ", " + inRange +", " + inStep);
    preyFlees();
    hunterTracks(); 
    hunterFollows();

    counter++;
    //delay(1000);

    if (counter == counterEnd) {
      println(stand_dev_Xg +", " + preyStep +", " + hunterStep +", " + probeStep + ", " + totalDistance/counterEnd +", " + totalDistanceGuess/counterEnd +", " + counterEnd +", " + counterInRange +", " + counterInStep + ", " + counterHalted +", " + totalRelativeError/counterEnd +", " + prey_speed +", " + hunter_speed +", " + cycle_duration +", " + sampleSize +", " + memorySize);
      statsOutput.println(stand_dev_Xg +", " + preyStep +", " + hunterStep +", " + probeStep + ", " + totalDistance/counterEnd +", " + totalDistanceGuess/counterEnd +", " + counterEnd +", " + counterInRange +", " + counterInStep + ", " + counterHalted +", " + totalRelativeError/counterEnd +", " + prey_speed +", " + hunter_speed +", " + cycle_duration +", " + sampleSize +", " + memorySize);

      //terminate condition
      //if (round(percentError*100) == 60) {stopExecSeq = true;}
      //if (preyStep == maxPreyStep) {
      //if (stand_dev_Xg == 3){
      if (randomSeedNumber == 5){
        if (memorySize == maxMemorySize){  
          if (sampleSize == maxSampleSize){
            stopExecSeq = true;
          }
        }
      }
      /*
      if (round(stand_dev_Xg*100) == 300) {
        stopExecSeq = true;
      }
      */

      if (stopExecSeq) {
        output.flush(); // Writes the remaining data to the file
        output.close(); // Finishes the file
        statsOutput.flush(); // Writes the remaining data to the file
        statsOutput.close(); // Finishes the file    
        exit();
      } else {
        //percentError = percentError + 0.01;
        //preyStep += 1;
        //stand_dev_Xg += 0.1;
        if (sampleSize < maxSampleSize){
          sampleSize++;
        } else if (memorySize < maxMemorySize){
          sampleSize = 1;
          memorySize++;
        } else {
          sampleSize = 1;
          memorySize = 2;
          //stand_dev_Xg++;
          randomSeedNumber++;
        }
        
        preyAppears();
        hunterAppears();  
        waypointAppears();
      }
    }
  }
