/*
  GENERAL SKECTH INFORMATION:
  ACCELEROMETER SENSOR: ADXL335
  SETUP: 
    - NO LCD;
    - NO DHT22 (TO INCLUDE DHT, UNCOMMENT THE READTEMPERATURE LINES;
    - WITH RTC Clock;
  CALIBRATION: MANUAL
*/

///////////////////////////////////////////////////////////////////// INITIAL DECLARATIONS /////////////////////////////////////////////////////////////////////

#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <stdlib.h>
#include <Adafruit_ADS1015.h>
#include "DHT.h"
#include <MemoryFree.h>
#include <uRTCLib.h>

//RTC clock object
uRTCLib rtc(0x68);


//Config controls (button and potentiometer
#define PUSH_BUT 6
#define POT_PIN 1
#define RED_PIN 3
#define OTHER_PIN 7
#define OTHER_PIN2 5

//ADC115 definitions
//soligen's library added variables, for continuos mode
const int alertPin = 2; //////////////////////////////////////////////// YOU NEED TO CONNECT THIS FOR CONTINUOS MODE
volatile bool continuousConversionReady = false;
int adcChannel = 1;
Adafruit_ADS1115 ads(0x48); /* Use this for the 16-bit version */
//Adafruit_ADS1015 ads;     /* Use thiS for the 12-bit version */

//ADXL 335 variables
int16_t adcX, adcY, adcZ;

//Instantiate LCD object
//LiquidCrystal_I2C lcd(0x3F, 2, 1, 0, 4, 5, 6, 7, 3, POSITIVE);

//SD card pin
const int CS = 4;
#define chipSelect 4 //SD card pin
int logIteration = 1; //Variable to allow creation of multiple files in the same voidloop (logfile1.txt, logfile2.txt, etc)
char logFile[16];

//Sampling parameters
int samplingFrequency = 0; //Em Hz. It will be set in void setup().
unsigned long iniTime = 0;
unsigned long endTime = 0;
unsigned long samplingDuration = 0; //Sampling duration in seconds.
unsigned long samplingStartTime = 0; //Variable to know when sampling started, to allow for sampling stop.

//Real experimental setup parameters (EMM-ARM - added on 29/05/2018)
#define sleepDuration 300000 //Sleep or 5 minutes (in milliseconds), after each sampling burst
unsigned long sleepTime = 0; //Will account the time the system started to sleep, to allow counting the 10 minutes sleep

//Calibration parameters
//int mean_ax, mean_ay, mean_az, mean_gx, mean_gy, mean_gz, state = 0;
//int ax_offset, ay_offset, az_offset, gx_offset, gy_offset, gz_offset;
//#define buffersize 1000   //Amount of readings used to average, make it higher to get more precision but sketch will be slower  (default:1000)
//#define acel_deadzone 8   //Acelerometer error allowed, make it lower to get more precision, but sketch may not converge  (default:8)
//#define giro_deadzone 1   //Giro error allowed, make it lower to get more precision, but sketch may not converge  (default:1)

//Error parameters: count how many errors have occurred in the sketch, separated by type.
int SDInitError = 0; //Error related to system unable to perform SD.begin method succesfully.
int accelInitError = 0;  //Error related to system unable to perform accelgyro.testConnection() method succesfully.
int SDFileError = 0; //Error related to system unable to open SD file succesfully.

////DHT 22 Declarations
#define DHTPIN 8    // what digital pin we're connected to
#define DHTTYPE DHT22   // DHT 22  (AM2302), AM2321
DHT dht(DHTPIN, DHTTYPE);
float t = 0;

//Motor pin for concrete version excitation
byte motorPin = 9;
byte motorValue = 255;
byte delayTime = 500;

///////////////////////////////////////////////////////////////////// SETUP /////////////////////////////////////////////////////////////////////
void setup() {

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //GENERAL DECLARATIONS
  //---------------------------------------------------------------------------------------------------------------------------------------------
  pinMode(PUSH_BUT, INPUT); //Configure button
  pinMode(RED_PIN, OUTPUT); //Configure led pin
  pinMode(OTHER_PIN, OUTPUT); //Configure led pin
  pinMode(OTHER_PIN2, OUTPUT); //Configure led pin
  pinMode(motorPin, OUTPUT); //Motor pin for excitation in concrete version
  //Initiate LCD
  //lcd.begin (16, 2);
  //lcd.setBacklight(HIGH);
  //No sense in checking LCD connection... There will be nothing to print the error on!
  //writeLCD("Iniciando", "Aguarde", 0);
  blinkLED(RED_PIN, 500, 4);
  blinkLED(OTHER_PIN, 500, 4);

  //--------------------------------------------------------------------------------------------
  // ADS1115 CONFIGURATION
  //--------------------------------------------------------------------------------------------

  // The ADC input range (or gain) can be changed via the following
  // functions, but be careful never to exceed VDD +0.3V max, or to
  // exceed the upper and lower limits if you adjust the input range!
  // Setting these values incorrectly may destroy your ADC!
  //                                                                ADS1015  ADS1115
  //                                                                -------  -------
  // ads.setGain(GAIN_TWOTHIRDS);  // 2/3x gain +/- 6.144V  1 bit = 3mV      0.1875mV (default)
  ads.setGain(GAIN_ONE);           // 1x gain   +/- 4.096V  1 bit = 2mV      0.125mV
  // ads.setGain(GAIN_TWO);        // 2x gain   +/- 2.048V  1 bit = 1mV      0.0625mV
  // ads.setGain(GAIN_FOUR);       // 4x gain   +/- 1.024V  1 bit = 0.5mV    0.03125mV
  // ads.setGain(GAIN_EIGHT);      // 8x gain   +/- 0.512V  1 bit = 0.25mV   0.015625mV
  // ads.setGain(GAIN_SIXTEEN);    // 16x gain  +/- 0.256V  1 bit = 0.125mV  0.0078125mV

  ads.begin();
  ads.setSPS(ADS1115_DR_860SPS);
  ads.readADC_Differential_0_1(); // in case chip was previously in contuous mode, take out of continuous
  ads.waitForConversion(); // delay to ensure any last remaining conversion completes
  // needed becasue if formerly was in continuous, 2 conversions need to complete

  //Set I2C clock to 400kHz to improve sampling rate.
  //Wire.setClock(400000);

  //Start ADS1115 in continuos mode only in ADC channel: the sampling frequency will be the one set by .setSPS method
  ads.startContinuous_SingleEnded(adcChannel);

  pinMode(alertPin, INPUT);
  attachInterrupt(digitalPinToInterrupt(alertPin), continuousAlert, FALLING);

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //INITIATE I2C AND SERIAL CONNECTIONS
  //---------------------------------------------------------------------------------------------------------------------------------------------
  /*Nothing to check here: Wire.h (I2C communication) does not have a method for connection checking because it does not makes sense - the
    actual connection checking is done with the sensor itself.
    Also, Serial.begin will not be checked since in the real experiment, there will be not serial connection (up to now - 20/05/2018)*/
  Wire.begin();      // join I2C bus
  //  Serial.begin(250000);    //  initialize serial communication

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //MPU6050 CONFIGURATION:
  //Initiate sensor, check connection, set configurarion modes, calibration
  //---------------------------------------------------------------------------------------------------------------------------------------------
  /*Initiate accelerometer. Check if it is connected, and if not, try again, registering how many connection errors have occurred
    in accelInitError variable, printing it in the LCD. */
  //  blinkLED(RED_PIN, 2000, 1);
  //  accelgyro.initialize();
  //  while (!accelgyro.testConnection()) {
  //    blinkLED(RED_PIN, 500, 1);
  //    accelgyro.initialize();
  //    accelInitError ++;
  //    delay(500);
  //    //writeLCD("", "", 2); /*When third argument is non-null, writeLCD writes specif message. See function for details.*/
  //  }

  /*Set acceleration sensivity range and applied filters.*/
  //  accelgyro.setFullScaleAccelRange(MPU6050_ACCEL_FS_2);//Set accelerometer scale to 2g range.
  //accelgyro.setDLPFMode(MPU6050_DLPF_BW_20);//Apply DLPF cutting all frequencies above 20Hz.
  //accelgyro.setDHPFMode(MPU6050_DHPF_5);//Apply DHPF cutting all frequencies below 5Hz.

  //TODO: Automatic calibration process:
  //writeLCD("Calibrando", "acelerometro", 0);
  //  digitalWrite(RED_PIN, HIGH); //turn led on
  //  digitalWrite(OTHER_PIN, HIGH); //turn led on
  //  delay(1000);
  //Manual calibration:
  //manualCalibMPU6050(-4284, 1395, 663, 48, -15, -13);
  //  digitalWrite(RED_PIN, LOW); //turn led off
  //  digitalWrite(OTHER_PIN, LOW); //turn led on
  //  delay(1000);

  //--------------------------------------------------------------------------------------------
  //DHT 22 CONFIGURATION
  dht.begin();

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //CONFIGURE SD CARD:
  //---------------------------------------------------------------------------------------------------------------------------------------------
  //See if the sd card is present and can be initialized. If not, try again. For later reuse in sketch, this part was transformed into a function.
  initializeSD();

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //USER INPUT: SAMPLING FREQUENCY AND TOTAL SAMPLING TIME
  //---------------------------------------------------------------------------------------------------------------------------------------------
  /*User set the sampling frequency manually using the potentiometer and confirming with push button.*/
  //samplingFrequency = configFrequency(POT_PIN, PUSH_BUT); /IN EMM-ARM, sampling frequency will not be set by user, but pre-configured to deal with possible system restarts...
  samplingFrequency = 500; //Value in Hz. High values induces large files. 500 Hz is used by Granja in preliminary tests.
  /*User set the sampling time*/
  //samplingDuration = configSampTime(POT_PIN, PUSH_BUT); //IN EMM-ARM, sampling duration will not be set by user, but pre-configured to deal with possible system restarts...
  samplingDuration = 90; //Samplig duration in seconds. Not too big so elastic modulus does not significantly change DURING the measurement.

  /*Wait until user presses button to continue to loop*/
  //writeLCD("Aperte botao p/", "continuar", 0); //IN EMM-ARM, NOTHING CAN DEPEND ON USER INPUT TO DEAL WITH POSSIBLE SYSTEM RESTARTS...
  //waitButton(PUSH_BUT); //Wait until the button connected to PUSH_BUT pin is pressed.

}

///////////////////////////////////////////////////////////////////// LOOP /////////////////////////////////////////////////////////////////////

void loop() {
  //writeLCD("Iniciando ciclo", "de amostragem", 0);
  blinkLED(OTHER_PIN, 250, 5);
  delay(1000);
  digitalWrite(RED_PIN, HIGH);
  //---------------------------------------------------------------------------------------------------------------------------------------------
  //INITIALIZING LOG FILE
  //Checking SD card for next available name, create file, open file for data writing, check if file could be open.
  //The log file is a .txt, formatted as the following: a header with sampling general information, a column with sensor readings and a column
  //with sampling time value. Each row is separated by a carriage return and newline character and, in each line, the columns are separeted by
  //a comma.
  //---------------------------------------------------------------------------------------------------------------------------------------------
  /*Scan for the next available file name in SD. File names will follow simple algebraic sequence: 00000001.txt, 000000002.txt, so on, always with
     a header with 8 digits, left-paded with zeroes, which is the maximum allowed by "SD.h" library.
     The function scanSDforAvailableFileNames() will return the next available number for the file name header.
  */
  logIteration = scanSDforAvailableFileNames();
  sprintf(logFile, "%08d.txt", logIteration); /*Constructs logFile character with sprintf function */

  /*Creates the file and opens it*/
  File dataFile = SD.open(logFile, FILE_WRITE);
  delay(3000);
  SDFileError = 0;
  /*Check if the file created wass successfully opened for data writing. If not, try to open again. Save how many errors have occurred. */
  while (!dataFile) { /*will enter IF if dataFile could not be opened.*/
    //writeLCD("", "", 4);
    blinkLED(OTHER_PIN, 500, 1);
    blinkLED(RED_PIN, 500, 1);
    File dataFile = SD.open(logFile, FILE_WRITE);
    delay(3000);
    SDFileError ++;
  }

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //CREATING LOG FILE HEADER
  //---------------------------------------------------------------------------------------------------------------------------------------------
  dataFile.println(F("EMM-ARM"));
  dataFile.print(F("Result # "));
  dataFile.print(logIteration);
  dataFile.println(F(" of the present session."));
  dataFile.print(F("Temperature: "));
  // UNCOMMENT LINES BELOW TO INCORPORATE DHT
//  t = dht.readTemperature();
//  while (isnan(t) || t == 0) {
//    blinkLED(OTHER_PIN2, 250, 1);
//    t = dht.readTemperature();
//  }
//  dataFile.print(t);
  dataFile.print(F(" *C Time: "));
  dataFile.print(millis() / 60000);
  dataFile.print(F(" @:"));
  dataFile.print(samplingFrequency);
  dataFile.print(F("Hz SpD:"));
  dataFile.print(samplingDuration);
  dataFile.print(F(" s Sleep:"));
  dataFile.print(sleepTime / 60000);
  dataFile.print(F(" s Sampling instant:"));
  rtc.refresh();
  dataFile.print(rtc.hour());
  dataFile.print(F(":"));
  dataFile.print(rtc.minute());
  dataFile.print(F(":"));
  dataFile.println(rtc.second());
  dataFile.println(F("-------"));
  dataFile.println(F("Results"));
  dataFile.println(F("Raw Accel \t Sampling interval"));

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //SAMPLING PROCESS
  //---------------------------------------------------------------------------------------------------------------------------------------------
  /*Sample and save to SD for the duration indicated on variable samplingDuration*/

  //writeLCD("","",1); /*When third argument is non-null, writeLCD writes specif message. See function for details.*/
  digitalWrite(RED_PIN, LOW); //turn led on, sampling is starting

  samplingStartTime = millis(); //Save when sampling has started.
  iniTime = micros(); //Allows for sampling duration measurement.

  analogWrite(motorPin, motorValue);
  delay(delayTime);
  while (millis() - samplingStartTime < samplingDuration * 1000) {
    //Read values from ADC only when interrupt pin says conversion is ready
    analogWrite(motorPin, 0);
    if (continuousConversionReady) {
      adcX = ads.getLastConversionResults();
      continuousConversionReady = false;
      dataFile.print(adcX);
      dataFile.print(F(","));
      endTime = micros();
      dataFile.println(endTime - iniTime); //Save the sampling time
      iniTime = endTime; //So the next sampTime will calculate the time taken from this point to the next loop, and so on.
    }
  }

  //---------------------------------------------------------------------------------------------------------------------------------------------
  //END SAMPLING PROCESS AND SLEEPS UNTIL NEXT SAMPLING
  //---------------------------------------------------------------------------------------------------------------------------------------------
  digitalWrite(RED_PIN, HIGH); //turn led on, sampling is starting
  dataFile.close();

  sleepTime = millis();

  while (millis() - sleepTime < sleepDuration) {
    //writeLCD("", "", 5);
    delay(1000);
    if (removingSD(PUSH_BUT)) {
      //writeLCD("Criando", "ERROR LOG", 0);
      /*Creates and saves an ERROR LOG FILE, to register any monitored errors occurred during execution. */
      sprintf(logFile, "LOGERROR.txt"); /*Constructs logFile character with sprintf function */
      /*Creates the file and opens it*/
      File dataFile = SD.open(logFile, FILE_WRITE);
      while (!dataFile) { /*will enter IF if dataFile could not be opened.*/
        //writeLCD("", "", 4);
        blinkLED(OTHER_PIN, 500, 1);
        blinkLED(RED_PIN, 500, 1);
        File dataFile = SD.open(logFile, FILE_WRITE);
        delay(2000);
        SDFileError ++;
      }
      /*Save the log error file*/
      dataFile.println(F("LOG ERROR FILE"));
      dataFile.print(F("SDInitError:"));
      dataFile.println(SDInitError);
      dataFile.print(F("AccelInitError:"));
      dataFile.println(accelInitError);
      dataFile.print(F("SDFileError:"));
      dataFile.println(SDFileError);
      dataFile.close();

      /*Allow user to remove SD card since LOG ERROR file creation has endeed */
      //writeLCD("SD a ser", "removido", 0);
      digitalWrite(OTHER_PIN, HIGH); //turn led on, SD can be removed
      delay(3000);
      while (!removingSD(PUSH_BUT)) {
        //writeLCD("Insira SD e", "pressione botao", 0);
        blinkLED(RED_PIN, 500, 1);
        delay(1000);
        //Waits until PUSH_BUT is pressed again, which will make sketch go out of this while loop.
      }
      //Initialize SD again.
      digitalWrite(OTHER_PIN, LOW);
      initializeSD();
    }
  }

}


///////////////////////////////////////////////////////////////////// FUNCTIONS /////////////////////////////////////////////////////////////////////

void initializeSD () {
  blinkLED(OTHER_PIN, 2000, 2);
  delay(1000);
  while (!SD.begin(chipSelect)) {
    SDInitError++;
    //If not, turn White led on
    //digitalWrite(WHITE_LED, HIGH);
    blinkLED(OTHER_PIN, 500, 1);
    //writeLCD("", "", 3); /*When third argument is non-null, writeLCD writes specif message. See function for details.*/
    delay(500);
    //writeLCD("Iniciando", "cartao SD", 0);
    //delay(2000);
  }
  //writeLCD("Sistema", "inicializado", 0);
  delay(2000);
}

int scanSDforAvailableFileNames() {
  /*Code snippet based on: https://forum.arduino.cc/index.php?topic=57460.0 */
  char fileName[16];                // SDcard uses 8.3 names so 16 bytes is enough. Note room for the '\0' char is needed!
  unsigned int index = 1;
  while (index != 0) {
    /* Detailment about sprinf function arguments: [http://www.cplusplus.com/reference/cstdio/printf/]
       A format specifier follows this prototype:
       %[flags][width][.precision][length]specifier
       In the case below:
        - "%" initiates the format specifier
        - "0" indicates "left-pads the number with zeroes (0) instead of spaces when padding is specified (see width sub-specifier)".
        - "8" indicates the width of the number: if it is equal to 8, a "index" equal to 1 would produce a "filename" equal to "00000001.txt",
          since we have left-pade with zeroes (previous specifier equal to "0") and width equal to "8".
       The "SD.h" library only supports file names with maximum of 8.3 characters, i.e. 8 for file header + a dot to introduce file extension +
       3 characters for file extensions (e.g. txt). Therefore, the maximum amount of samples due to "SD.h" library limitation is 99999999, which
       will produce files ranging from "00000000.txt" to "99999999.txt".
    */
    sprintf(fileName, "%08d.txt", index);
    if (SD.exists(fileName) == false) break; /*If name does not exist is SD, exit while loop and save index*/
    index++;
  }
  /* if index is higher than 99999999, there are no available file names left */
  if (index > 99999999) {
    index = 0;
  }
  /*Return index, which will be the file name of next sample */
  return index;
}

void blinkLED(int ledPin, int millisInterval, int numTimes) {
  //Function that blinks a LED connect to ledPin, with a interval of millisInterval (in millisseconds)
  //and for a number of times defined in numTimes
  for (int i = 0; i < numTimes; i++) {
    digitalWrite(ledPin, HIGH);
    delay(millisInterval);
    digitalWrite(ledPin, LOW);
    delay(millisInterval);
  }
}

bool removingSD(int buttonPin) {
  //  //Sometimes one needs to take the SD card out to transfer partial data.
  //  //This function makes Arduino waits until SD card is put back in the system:
  //  //When button is pressed, removingSD function returns true and the sketch
  //  //enters in a loop waiting for the button to be pressed again, i.e. for
  //  //another use of removingSD returns true.
  bool continueCode = false;
  int buttonState = 0;
  buttonState = digitalRead(buttonPin);
  if (buttonState == HIGH) {
    //The button has been pressed: return True
    continueCode = true;
  }
  return continueCode;
}

void continuousAlert() {
  // Do not call getLastConversionResults from ISR because it uses I2C library that needs interrupts
  // to make it work, interrupts would need to be re-enabled in the ISR, which is not a very good practice.
  continuousConversionReady = true;
}

//float getTemperature() {
//  float t = dht.readTemperature();
//  float h = dht.readHumidity();
//  if (isnan(t)) {
//    t = 0;
//    return;
//  }
//  return t;
//}

//void writeLCD(char phrase1[16], char phrase2[16], int specialCase) {
//  /*Function to write two sentences to 16x2 LCD screen*/
//  lcd.clear();
//  lcd.setCursor(0, 0);
//  int minutes = 0;
//  int seconds = 0;
//
//  switch (specialCase) {
//    case 1:
//      /*refers to the special case where the LCD needs to print sampling information
//        while the sensor is sampling.*/
//      lcd.print("Em amostragem:");
//      lcd.setCursor(0, 1);
//      lcd.print(samplingFrequency);
//      lcd.print(" Hz| ");
//      lcd.print(samplingDuration);
//      lcd.print(" s");
//      break;
//
//    case 2:
//      /*Sensor error */
//      lcd.print("ERR: Sensor nao");
//      lcd.setCursor(0, 1);
//      lcd.print("iniciado. #:");
//      lcd.print(accelInitError);
//      break;
//
//    case 3:
//      /*SD initialization error */
//      lcd.print("ERR: SD nao ini");
//      lcd.setCursor(0, 1);
//      lcd.print("ciado. #:");
//      lcd.print(SDInitError);
//      break;
//
//    case 4:
//      /*Log file initialization error*/
//      lcd.print("ERR: Arquivo nao");
//      lcd.setCursor(0, 1);
//      lcd.print("aberto. #:");
//      lcd.print(SDFileError);
//      break;
//
//    case 5:
//      /*System sleeping message*/
//      minutes = (millis() - sleepTime) / (60000);
//      seconds = (millis() - sleepTime) / (1000) - minutes * 60;
//      char time_char[7];
//      sprintf(time_char, "%02d:%02d", minutes, seconds); //Format the string indicating time
//      lcd.print("Sleep");
//      lcd.setCursor(0, 1);
//      lcd.print(time_char);//Print minutes elapsed since sleep start
//      break;
//
//    default:
//      /*Default case*/
//      lcd.print(phrase1);
//      lcd.setCursor(0, 1);
//      lcd.print(phrase2);
//      break;
//  }
//}

//void manualCalibMPU6050(int ax_off, int ay_off, int az_off, int gx_off, int gy_off, int gz_off) {
//  //Function for manual calibration of MPU 6050. It requires that calibration sketch
//  //is run before and its results are manually configurated here.
//  accelgyro.setXAccelOffset(ax_off);
//  accelgyro.setYAccelOffset(ay_off);
//  accelgyro.setZAccelOffset(az_off);
//  accelgyro.setXGyroOffset(gx_off);
//  accelgyro.setYGyroOffset(gy_off);
//  accelgyro.setZGyroOffset(gz_off);
//}

//  int configFrequency(int potPin, int buttonPin) {
//    //Function that allows setting the sampling frequency using a
//    //potentiometer as input.
//    bool continueCode = false;
//    int buttonState = 0;
//    int samplingFrequency = 0;
//
//    lcd.clear();
//    lcd.setCursor(0, 0);
//    lcd.print("Configuracao");
//    lcd.setCursor(0, 1);
//    lcd.print("Freq.(Hz): ");
//    delay(1000);
//
//    while (continueCode == false) {
//      samplingFrequency = analogRead(potPin) / 50;
//      samplingFrequency = samplingFrequency * 50;
//      if (samplingFrequency > 1000) {
//        samplingFrequency = 1000; //Maximum accelerometer (MPPU6050) sampling frequency is 1kHz.
//        lcd.setCursor(11, 1);
//        lcd.print(" ");
//        lcd.setCursor(11, 1);
//        lcd.print(samplingFrequency);
//      } else {
//        lcd.setCursor(11, 1);
//        lcd.print(" ");
//        lcd.setCursor(11, 1);
//        lcd.print(samplingFrequency);
//      }
//      buttonState = digitalRead(buttonPin);
//      if (buttonState == HIGH) {
//        //The button has been pressed: return True
//        continueCode = true;
//      }
//      delay(500);
//    }
//    return samplingFrequency;
//  }

//  int configSampTime(int potPin, int buttonPin) {
//    //Function that allows setting the sampling frequency using a
//    //potentiometer as input.
//    bool continueCode = false;
//    int buttonState = 0;
//    int samplingTime = 0;
//
//    lcd.clear();
//    lcd.setCursor(0, 0);
//    lcd.print("--Configuracao--");
//    lcd.setCursor(0, 1);
//    lcd.print("Time (s): ");
//    delay(1000);
//
//    while (continueCode == false) {
//      samplingTime = analogRead(potPin) / 10;
//      samplingTime = samplingTime * 10;
//      lcd.setCursor(10, 1);
//      lcd.print("      ");
//      lcd.setCursor(10, 1);
//      lcd.print(samplingTime);
//      buttonState = digitalRead(buttonPin);
//      if (buttonState == HIGH) {
//        //The button has been pressed: return True
//        continueCode = true;
//      }
//      delay(500);
//    }
//    return samplingTime;
//  }

//  void resetOffsets() {
//    //Set all accelerometers offsets to zero, to start the calibration process.
//    accelgyro.setXAccelOffset(0);
//    accelgyro.setYAccelOffset(0);
//    accelgyro.setZAccelOffset(0);
//    accelgyro.setXGyroOffset(0);
//    accelgyro.setYGyroOffset(0);
//    accelgyro.setZGyroOffset(0);
//  }

//  void calibrateNow () {
//    /*This code snippet is made by Luís Rodenas, available on: https://www.i2cdevlib.com/forums/topic/96-arduino-sketch-to-automatically-calculate-mpu6050-offsets/ */
//    //Function that executes the main calibration process.
//    if (state == 0) {
//      meansensors();//Execute a first
//      state++;
//      delay(1000);
//    }
//    if (state == 1) {
//      calibration();
//      state++;
//      delay(1000);
//    }
//    /*if (state==2) {
//      meansensors();
//      accelgyro.setXAccelOffset(0);
//      accelgyro.setYAccelOffset(0);
//      accelgyro.setZAccelOffset(0);
//      accelgyro.setXGyroOffset(0);
//      accelgyro.setYGyroOffset(0);
//      accelgyro.setZGyroOffset(0);
//      }*/
//  }

//  void calibration() {
//    /*This code snippet is made by Luís Rodenas, available on: https://www.i2cdevlib.com/forums/topic/96-arduino-sketch-to-automatically-calculate-mpu6050-offsets/   */
//    /*Function that runs until calibration precision is achievable.
//      First it set the acceleration offsets as the values previously obtained in the first
//      meansensor() function call. Then, it runs the meansensor() function again and checks if
//      the mean value is within the precision wanted (deadzones). If yes, then the offset values
//      previously configured are adequate, if not, the program calculates new offsets and run
//      meansensor function again, until convergence is achieved.*/
//
//    //RENAN: Why divide for 8 and 4? R.: (16/04/2018) It has to do with accelerometer registers.
//    ax_offset = -mean_ax / 8;
//    ay_offset = -mean_ay / 8;
//    az_offset = (-mean_az) / 8;
//
//    gx_offset = -mean_gx / 4;
//    gy_offset = -mean_gy / 4;
//    gz_offset = -mean_gz / 4;
//
//
//    while (1) {
//      //Sets a new offset based on the previous averaging, and calculates new average
//      //If new average is within the accepted error, for all axis, proceeds to end routine and calibration code
//      //If new average falls off the accepted error, repeat meaning process until it achieves desired precision
//      int ready = 0;
//      accelgyro.setXAccelOffset(ax_offset);
//      accelgyro.setYAccelOffset(ay_offset);
//      accelgyro.setZAccelOffset(az_offset);
//
//      accelgyro.setXGyroOffset(gx_offset);
//      accelgyro.setYGyroOffset(gy_offset);
//      accelgyro.setZGyroOffset(gz_offset);
//
//      meansensors();
//
//      if (abs(mean_ax) <= acel_deadzone) ready++;
//      else ax_offset = ax_offset - mean_ax / acel_deadzone;
//
//      if (abs(mean_ay) <= acel_deadzone) ready++;
//      else ay_offset = ay_offset - mean_ay / acel_deadzone;
//
//      if (abs(mean_az) <= acel_deadzone) ready++;
//      else az_offset = az_offset + (-mean_az) / acel_deadzone;
//
//      if (abs(mean_gx) <= giro_deadzone) ready++;
//      else gx_offset = gx_offset - mean_gx / (giro_deadzone + 1);
//
//      if (abs(mean_gy) <= giro_deadzone) ready++;
//      else gy_offset = gy_offset - mean_gy / (giro_deadzone + 1);
//
//      if (abs(mean_gz) <= giro_deadzone) ready++;
//      else gz_offset = gz_offset - mean_gz / (giro_deadzone + 1);
//
//      if (ready == 6) break;
//    }
//  }

//  void meansensors() {
//    /*This code snippet is made by Luís Rodenas, available on: https://www.i2cdevlib.com/forums/topic/96-arduino-sketch-to-automatically-calculate-mpu6050-offsets/
//      Function that takes 1000 measures and makes a mean value out of them.
//      Used in the calibration process to get new offset values.
//    */
//    long i = 0, buff_ax = 0, buff_ay = 0, buff_az = 0, buff_gx = 0, buff_gy = 0, buff_gz = 0;
//
//    while (i < (buffersize + 101)) {
//      // read raw accel/gyro measurements from device
//      accelgyro.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);
//
//      if (i > 100 && i <= (buffersize + 100)) { //First 100 measures are discarded
//        buff_ax = buff_ax + ax;
//        buff_ay = buff_ay + ay;
//        buff_az = buff_az + az;
//        buff_gx = buff_gx + gx;
//        buff_gy = buff_gy + gy;
//        buff_gz = buff_gz + gz;
//      }
//      if (i == (buffersize + 100)) {
//        mean_ax = buff_ax / buffersize;
//        mean_ay = buff_ay / buffersize;
//        mean_az = buff_az / buffersize;
//        mean_gx = buff_gx / buffersize;
//        mean_gy = buff_gy / buffersize;
//        mean_gz = buff_gz / buffersize;
//      }
//      i++;
//      delay(2); //Needed so we don't get repeated measures
//    }
//  }
