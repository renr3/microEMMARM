/*
  GENERAL SKECTH INFORMATION:
*/

///////////////////////////////////////////////////////////////////// INCLUDING LIBRARIES /////////////////////////////////////////////////////////////////////

//Libraries for I2C communication, external ADC (ADS1115 module), external RTC (DS3231 module), and I2C LCD
#include <Wire.h>
#include "ADS1X15.h"
#include <uRTCLib.h>
#include <LiquidCrystal_I2C.h>

//Libraries for SD card module
#include "SdFat.h"
#include <SPI.h>

//Library for temperature and humidity sensor (DHT22 module)
#include "DHT.h"


///////////////////////////////////////////////////////////////////// DEFINE GLOBAL VARIABLES /////////////////////////////////////////////////////////////////
//Definition of a structure to hold variables for current state of system configuration
typedef struct
{
  byte samplingFrequencyOption; //sysConfig.samplingFrequencyOption mapping: #1-64Hz/#2-128Hz/#3-250Hz/#4-475Hz/#5-860Hz
  byte samplingDurationOption; //sysConfig.samplingDurationOption mapping: #1-1s/#2-10s/#3-60s/#4-90s/#5-120Hz
  byte sleepDurationOption; //sleedDurationOption mapping: #1-1s/#2-60s/#3-300s/#4-500s/#5-600s
  byte numberOfActiveChannelsOption; //sysConfig.numberOfActiveChannelsOption mapping: #1-1/#2-2/#3-3/#4-4
  byte tempHumSensorOption; //sysConfig.tempHumSensorOption mapping: #1-is On/#2-is off
} systemConfiguration;

//Define default state for system configuration
//The codification of system states is defined in the defintion of the systemConfiguration struct
#define samplingFrequencyOption_Default 5
#define samplingDurationOption_Default 4
#define sleepDurationOption_Default 3
#define numberOfActiveChannelsOption_Default 1
#define tempHumSensorOption_Default 1

//Instantiate the systemConfiguration variable "sysConfig" with default values
systemConfiguration sysConfig = {samplingFrequencyOption_Default,
                                 samplingDurationOption_Default,
                                 sleepDurationOption_Default,
                                 numberOfActiveChannelsOption_Default,
                                 tempHumSensorOption_Default
                                }; //Default configuration

//Pins configuration for interface buttons at top pannel
//#define PAUSE_BUTTON 9
//#define MINUS_BUTTON 8
//#define PLUS_BUTTON 4
//#define ARROW_BUTTON 5
#define PAUSE_BUTTON 1
#define MINUS_BUTTON 8
#define PLUS_BUTTON 4
#define ARROW_BUTTON 0
//Pins configuration for analog I/O pins at front pannel
#define AIO_D1 A0
#define AIO_D2 A1
#define AIO_D3 A2
#define AIO_D4 A3

//Define codification for printing messages on LCD screen
#define WELCOME_SCREEN 7
#define INITIALIZING_SD_SCREEN 6
#define SD_INITIALIZED_SCREEN 28
#define SYSCNFGFILE_NOT_OPEN_SCREEN 38

//ADXL335 accelerometer variables
//There is just one variable because only one channel is monitored each time
uint16_t adsLastValue = 0;

//External ADC (ADS1115 module) definitions
//Instantiation of a ADS1115 object
ADS1115 ads(0x48);
//Configuration of parameters and pis for the ADS1115 module
byte currentChannel = 1;
const byte alertPin = 3;
byte saveInSD = 0; //Parameter that 
//==============
//IMPORTANT INFO:
//      For greater performance, the ADS1115 is used with its hardware interrupt pin.
//      Each time a new sample is ready to be read, the ALRT pin indcates for an ATMega interrupt pin that 
//    a new measurement should be performed. This functionality is called Interrupt Service Routine (ISR).
//      Each time an interrupt occurs, the microprocessor interrupts everything being done and executes a section of code (or function).
//      Because things shouldn't be hanging too long, the function to be executed should be as small as possible and ideally not recursive,
//    at the risk of the ISR beng repeatedly called before being completely run and stay stucked within itself.
//      The function samplingAlert() below is the function performed when ADS1115 raises an ISR flag.
//      It was implemented to be as brief as possible, although it is somewhat recursive: it enables interrupts within itself so I2C communication can occur
//    with the external ADC (ADS1115 module), since I2C communication requires ISR. Tests have never indicated the system to remain stucked within this 
//    function, which indicates it is fast enough for the ISR to work reliably without freezing the system.
//==============
void samplingAlert() {
  //==============
  //IMPORTANT INFO:
  //      The structure of this ISR is based on the discussions made on https://forum.arduino.cc/t/using-i2c-inside-an-interrupt/308125/2. A PDF copy of
  //    this thread can be found on Reference 1 of the source code, in case the Arduino Forum is offline or does not keep the original thread.
  //==============
  static bool IAmRunning = false; //Variable that will allow indicating this ISR function is running.
  //==============
  //IMPORTANT INFO:
  //      IAmRunning is a static local variable. The first time samplingAlert() is run, IAmRunning is initialized, but it is never initialized again
  //    and its value is preserved between different calls of samplingAlert().
  //      Check https://techexplorations.com/guides/arduino/programming/static/ for more info on static variables.
  //==============
  if (IAmRunning) return; //This will finish this run of samplingAlert() if it was called on top of other samplingAlert() already runnin,
                          //so to mitigate recursive calls that could freeze the system. 
  IAmRunning = true; //Indicates the system that a samplingAlert() is being run.
  interrupts(); //Enable interrupts so I2C and communication to external ADS (ADS1115 module) can work.
  adsLastValue = ads.getValue(); //Gets the value from ADS1115. Remember that we are here just because ADS1115 raised an ISR flag saying a new value was ready to be read.
  saveInSD = 1; //Signalizes the system that a new measurement has been read and is ready to be saved to log file
  IAmRunning = false; //Indicates the system that the on-going samplingAlert() has finished. 
}

//Instantiate RTC clock object
uRTCLib rtc(0x68);

//Instantiate LCD object
LiquidCrystal_I2C lcd(0x27, 16, 2); // set the LCD address to 0x27 for a 16 chars and 2 line display

//microSD card module pin and variable definitions
#define chipSelect 2 //CS pin from microSD module
unsigned short logOrdinal[4] = {0, 0, 0, 0}; //Variable to store current ordinal for save files associated to each of 4 measurement channels 
char logFile[10]; //Variable to allow constructing the current file log name.
#define sysConfgFileName "SYSCFG.txt"
//Instantiate a SD object
SdFat32 SD;
//Instantiate a file object
File32 currentOpenFile;
//Variable to store the pre-allocation size used to crease files in the microSD card to speed up the process
uint32_t PREALLOCATE_SIZE  =  0;
//Configurations for the microSD module.
//These configurations were taken directly from ExFatLogger example from SDFat.h library
#define SPI_CLOCK SD_SCK_MHZ(50)
//This structure tries to select the best SD card configuration
#if HAS_SDIO_CLASS
#define SD_CONFIG SdioConfig(FIFO_SDIO)
#elif  ENABLE_DEDICATED_SPI
#define SD_CONFIG SdSpiConfig(SD_CS_PIN, DEDICATED_SPI, SPI_CLOCK)
#else  // HAS_SDIO_CLASS
#define SD_CONFIG SdSpiConfig(SD_CS_PIN, SHARED_SPI, SPI_CLOCK)
#endif  // HAS_SDIO_CLASS

//Temperature and humidity sensor definitions
#define DHTPIN 9 //Data pin for DHT22
#define DHTTYPE DHT22   //DHT 22 (AM2302), AM2321
//Instantiate a DHT object
DHT dht(DHTPIN, DHTTYPE);
//Variable to store the measurements taken from the sensor
float dhtValue = 0;

//Definition of parameters associated to sampling on measurement sessions
//They will be populated during runtime accordingly to the configuration of the system
unsigned short samplingFrequency = 0; //Sampling frequency during a measurement session
unsigned long samplingDuration = 0; //Duration of each measurement session
unsigned long sleepDuration = 0; //Duration of sleep session
unsigned long startTime = 0; //Variable to register the start of each loop (measurement and sleep sessions), so they can be timed

///////////////////////////////////////////////////////////////////// CUSTOM CHARACTERS FOR LCD /////////////////////////////////////////////////////////////////
const byte microSymbol_1[8] = {
  //big μ symbol - first quarter
  B11111,
  B00001,
  B00001,
  B10001,
  B10001,
  B10001,
  B10001,
  B10000
};
const byte microSymbol_2[8] = {
  //big μ symbol - second quarter
  B11111,
  B10000,
  B10000,
  B10001,
  B10001,
  B10001,
  B10001,
  B00001
};
const byte microSymbol_3[8] = {
  //big μ symbol - third quarter
  B10000,
  B10001,
  B10001,
  B10001,
  B10001,
  B00001,
  B00001,
  B11111
};
const byte microSymbol_4[8] = {
  //big μ symbol - fourth quarter
  B00001,
  B11100,
  B11100,
  B11111,
  B11111,
  B11111,
  B11111,
  B11111
};
const byte microSymbol_5[8] = {
  //black block
  B11111,
  B11111,
  B11111,
  B11111,
  B11111,
  B11111,
  B11111,
  B11111
};
const byte microSymbol_6[8] = {
  //in line μ (micro) character
  B00000,
  B11010,
  B01010,
  B01010,
  B01110,
  B01001,
  B01000,
  B00000
};
const byte microSymbol_7[8] = {
  B00000,
  B00100,
  B00110,
  B11111,
  B11111,
  B00110,
  B00100,
  B00000
};
const byte pauseButtom_Symbol[8] {
  B00000,
  B11011,
  B11011,
  B11011,
  B11011,
  B11011,
  B11011,
  B00000
};

///////////////////////////////////////////////////////////////////// SETUP LOOP /////////////////////////////////////////////////////////////////
void setup() {
  //Initialize ADC module
  ads.begin();
  //Initialize input/output pins for buttons and analog channels
  pinMode(PAUSE_BUTTON, INPUT);
  pinMode(MINUS_BUTTON, INPUT_PULLUP);
  pinMode(PLUS_BUTTON, INPUT_PULLUP);
  pinMode(ARROW_BUTTON, INPUT_PULLUP);
  //TODO: when use of analog input/output channels is implemented, the pins should be initialized here
  /*
  pinMode(AIO_D1, INPUT);
  pinMode(AIO_D2, INPUT_PULLUP);
  pinMode(AIO_D3, INPUT_PULLUP);
  pinMode(AIO_D4, INPUT_PULLUP);
   */
  //Initialize interrupt pin for ADS1115
  pinMode(alertPin, INPUT_PULLUP);
  
  //Set ALRT pin in ADS1115 and continuous mode. See library for details and examples on these functions
  ads.setComparatorThresholdHigh(0x8000);
  ads.setComparatorThresholdLow(0x0000);
  ads.setComparatorQueConvert(0);
  ads.setMode(0);        // continuous mode
  
  //Initialize LCD screen
  lcd.begin(16, 2);
  lcd.clear();
  declareCustomSymbols(); //Function that initializes the custom characters defined above
  lcd.backlight();
  
  //Print welcome screen on LCD
  writeLCD(WELCOME_SCREEN); 

  //Initialize microSD card module
  initializeSD();

  //Initialize external ADC (ADS1115 module)
  //==============
  //IMPORTANT INFO:
  //      The first configuration is the gain of ADS1115. In the library used, gain is defined by .setGain method accordingly to:
  //        ads.setGain(1);    // 1x gain   +/- 4.096V  1 bit = 0.125mV
  //        ads.setGain(2);    // 2x gain   +/- 2.048V  1 bit = 0.0625mV
  //        ads.setGain(3);    // 4x gain   +/- 1.024V  1 bit = 0.03125mV
  //        ads.setGain(4);    // 8x gain   +/- 0.512V  1 bit = 0.015625mV
  //        ads.setGain(5);    // 16x gain  +/- 0.256V  1 bit = 0.0078125mV
  //
  //      The gain used should be set accordingly to the voltage levels produced by the acquired sensor, in this case, ADXL335 accelerometer/
  //      Accordingly to the ADXL335 datasheet, the sensor has a measurement range typical of +-3.6 g
  //    in each axis, and the zero g is typically at Vs/2 (Vs=Vsupply). Considering the maximum sensitivity of 330 mV/g, accordingly to the datasheet,
  //    and that the breakout board used, GY-61, has a voltage regulator that allows external feed of 5V but converts it to 3.3 V, 
  //    the sensor would typically outputs 1.65 V at 0g and 1.98 V at 1g.
  //      Because of the way the accelerometer is positioned in the specimen, the accelerometer axis that is monitored is aligned to the direction of gravity,
  //    and, thus, when the EMM-ARM specimen is not vibrating (at still), the sensor would output 1.98 V, which corresponds to 1g. Thus, all measurements
  //    will oscillate around 1.98 V.  
  //      The magnitude of acceleration of a typical EMM-ARM experiment under ambient vibration should obvserve very seldon maximums of 0.5g (0.165 V = 0.5g*330mv/g),
  //    so, reaching a maximum of 2.145 V (1.98 V + 0.165 V). This is just a maximum value, as the RMS acceleration lies within the order of 0.010 mg.
  //      Therefore, the system might be compatible with gain 2, (+/- 2.048V). However, most likely it is better to use with gain 1 so to guarantee no saturation.
  //    If another axis, not perpendicular to gravity, is used during the EMM-ARM test, perhaps one can safely use gain 2. But never gain 3 or higher if saturation
  //    of ADC channel is of concern.
  //==============

  ads.setGain(1);           // 1x gain   +/- 4.096V  1 bit = 0.125mV

  //Initialize configuration variables of the system
  //They need to either be read from SD card or be initialized with default values
  //If it exist, read the System Configuration File (sysConfigFile) from SD card and copy the configurations there to sysConfig varibale.
  //If it does not exist, we don't need to do nothing: in the next steps, either the default values are stored in sysConfig, 
  //or new values configured by the user with the user interface of the system.
  readSysConfigFile();

  //Prints a screen allowing for configuring the system.
  for (byte blinky = 0; blinky < 10; blinky++) {
    writeLCD(8);
    delay(500);
    lcd.clear();
    delay(500);
    if (checkButtonLow(ARROW_BUTTON)) {
      configurationScreen();
    } else if (checkButtonLow(PLUS_BUTTON) && checkButtonLow(MINUS_BUTTON)) {
      configurationRTCScreen();
    }
  }
  //Save configurations set by the user in the sysConfigFile
  createSysConfigFile ();

  //Check folder structure since new channels may have been added
  checkFolderStructure();

  /* DEFINE SYSTEM CONFIGURATION ########################################
  */
  switch (sysConfig.samplingFrequencyOption) {
    /*sysConfig.samplingFrequencyOption mapping: #1-64Hz/#2-128Hz/#3-250Hz/#4-475Hz/#5-860Hz
      #define ADS1115_REG_CONFIG_DR_8SPS    (0x0000)  // 8 SPS(Sample per Second), or a sample every 125ms
      #define ADS1115_REG_CONFIG_DR_16SPS    (0x0020)  // 16 SPS, or every 62.5ms
      #define ADS1115_REG_CONFIG_DR_32SPS    (0x0040)  // 32 SPS, or every 31.3ms
      #define ADS1115_REG_CONFIG_DR_64SPS    (0x0060)  // 64 SPS, or every 15.6ms
      #define ADS1115_REG_CONFIG_DR_128SPS   (0x0080)  // 128 SPS, or every 7.8ms  (default)
      #define ADS1115_REG_CONFIG_DR_250SPS   (0x00A0)  // 250 SPS, or every 4ms, note that noise free resolution is reduced to ~14.75-16bits, see table 2 in datasheet
      #define ADS1115_REG_CONFIG_DR_475SPS   (0x00C0)  // 475 SPS, or every 2.1ms, note that noise free resolution is reduced to ~14.3-15.5bits, see table 2 in datasheet
      #define ADS1115_REG_CONFIG_DR_860SPS */
    case 1:
      ads.setDataRate(3);
      samplingFrequency = 64;
      break;
    case 2:
      ads.setDataRate(4);
      samplingFrequency = 128;
      break;
    case 3:
      ads.setDataRate(5);
      samplingFrequency = 250;
      break;
    case 4:
      ads.setDataRate(6);
      samplingFrequency = 475;
      break;
    case 5:
      ads.setDataRate(7);
      samplingFrequency = 860;
      break;
  }
  switch (sysConfig.samplingDurationOption) {
    //sysConfig.samplingDurationOption mapping: #1-1s/#2-10s/#3-60s/#4-90s/#5-120s
    case 1:
      samplingDuration = 1;
      break;
    case 2:
      samplingDuration = 10;
      break;
    case 3:
      samplingDuration = 60;
      break;
    case 4:
      samplingDuration = 90;
      break;
    case 5:
      samplingDuration = 120;
      break;
  }
  switch (sysConfig.sleepDurationOption) {
    //sleedDurationOption mapping: #1-1s/#2-60s/#3-300s/#4-500s/#5-600s
    case 1:
      sleepDuration = 1000;
      break;
    case 2:
      sleepDuration = 60000;
      break;
    case 3:
      sleepDuration = 300000;
      break;
    case 4:
      sleepDuration = 500000;
      break;
    case 5:
      sleepDuration = 600000;
      break;
  }
  //We don't have to make "switch (sysConfig.numberOfActiveChannelsOption)" because this parameter,
  //sysConfig.numberOfActiveChannelsOption, directly encodes the number of active channels, unlike
  //the others for which we need to map from sysConfig parameter to a real valueS
  switch (sysConfig.tempHumSensorOption) {
    //sysConfig.tempHumSensorIsOn mapping: #1-is On/#2-is off
    case 1:
      dht.begin();
      delay(2000);
      break;
  }
  //Preallocate file size basing on sampling frequency and duration
  //2 bytes per acceleration sample
  PREALLOCATE_SIZE  =  (uint32_t)2 * samplingDuration * samplingFrequency;
}

void loop() {
  //Entering EMM-ARM mode
  writeLCD(11);
  //Iterate through each channel
  for (currentChannel = 1; currentChannel <= sysConfig.numberOfActiveChannelsOption; currentChannel++) {
    /*INITIALIZING LOG FILE ########################################
    */
    if (logOrdinal[currentChannel - 1] == 0) {
      //If logOrdinal of current channel is zero, the system is at the first initialization and the next available name needs to be found
      logOrdinal[currentChannel - 1] = scanSDforAvailableFileNames(currentChannel);
    } else {
      //If logOrdinal of current channel has a non-zero value, it will just update to the next one
      logOrdinal[currentChannel - 1] = logOrdinal[currentChannel - 1] + 1;
    }
    initializeToWriteBinaryLogFile(currentChannel, logOrdinal[currentChannel - 1]);
    /*SAMPLING PROCESS ########################################
    */
    //Sample and save to SD for the duration indicated on variable samplingDuration
    char currentChannelChar[2];
    sprintf(currentChannelChar, "%01d", currentChannel);
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(F("Amostrando C"));
    lcd.print(currentChannelChar);
    lcd.print(F(":"));
    lcd.setCursor(0, 1);
    lcd.print(samplingFrequency);
    lcd.print(F(" Hz| "));
    lcd.print(samplingDuration);
    lcd.print(F(" s"));
    //totalSamples = 0;
    startTime = millis(); //Save when sampling has started.
    //ACTIVATE CORRECT CHANNEL ########################################
    ads.requestADC(currentChannel - 1);   // trigger first read
    adsLastValue = 0;
    attachInterrupt(digitalPinToInterrupt(alertPin), samplingAlert, RISING);
    while (millis() - startTime < samplingDuration * 1000) {
      if (saveInSD == 1) {
        saveInSD = 0;
        //samplingStamp=millis();
        currentOpenFile.write((const uint8_t *)&adsLastValue, sizeof(adsLastValue));
        //currentOpenFile.write((const uint8_t *)&samplingStamp, sizeof(samplingStamp));
        //totalSamples = totalSamples + 1;
      }
    }
    detachInterrupt(digitalPinToInterrupt(alertPin));
    //delay(1000); //Delay to calm things down?
    //Serial.println("FREQUÊNCIA");
    //Serial.println(1 / (samplingDuration / totalSamples));
    /*END SAMPLING AND CLOSE THE BINARY LOG FILE ########################################
    */
    currentOpenFile.close();
    /*CREATING TXT LOG FILE (CONVERTS BINARY TO TXT FILE) ########################################
       Here the binary .emm file will be converted to a .txt ASCII file, which is human readable and compatible with
       the post-processing algorithms.
       This txt log file will also have global parameters of the logging.
    */
    initializeToWriteTxtLogFile(currentChannel, logOrdinal[currentChannel - 1]);
    /*CREATING TXT LOG FILE HEADER ########################################
    */
    rtc.refresh();
    currentOpenFile.println(F("ANO|MES|DIA|HORA|MINUTO|SEGUNDO"));//rtc.hour() returns a uint8_t
    currentOpenFile.println(rtc.year());//rtc.hour() returns a uint8_t
    currentOpenFile.println(rtc.month());//rtc.hour() returns a uint8_t
    currentOpenFile.println(rtc.day());//rtc.hour() returns a uint8_t
    currentOpenFile.println(rtc.hour());//rtc.hour() returns a uint8_t
    currentOpenFile.println(rtc.minute());//rtc.minute() returns a uint8_t
    currentOpenFile.println(rtc.second());//rtc.second() returns a uint8_t
    currentOpenFile.println(F("FREQUENCIA_AMOSTRAGEM(HZ)"));//rtc.hour() returns a uint8_t
    currentOpenFile.println(samplingFrequency);
    currentOpenFile.println(F("DURACAO_AMOSTRAGEM_CONFIGURADA(SEGUNDOS)"));//rtc.hour() returns a uint8_t
    currentOpenFile.println(samplingDuration);
    //currentOpenFile.println(F("QUANTIDADE_DE_AMOSTRAS"));//rtc.hour() returns a uint8_t
    //currentOpenFile.println(totalSamples);
    if (sysConfig.tempHumSensorOption == 1) {
      currentOpenFile.println(F("TEMPERATURA(C)|UMIDADE(%)"));//rtc.hour() returns a uint8_t
      //if tempHumSensorOption==1, the sensor is connected to the system.
      //If tempHumSensorOption==2, the sensor is off.
      dhtValue = dht.readTemperature();
      if (isnan(dhtValue)) {
        for (byte blinky = 0; blinky < 3; blinky++) {
          writeLCD(34);
          delay(1000);
        }
        dhtValue = 0;
      }
      currentOpenFile.println(dhtValue);
      dhtValue = dht.readHumidity();
      if (isnan(dhtValue)) {
        for (byte blinky = 0; blinky < 3; blinky++) {
          writeLCD(35);
          delay(1000);
        }
        dhtValue = 0;
      }
      currentOpenFile.println(dhtValue);
    }
    currentOpenFile.close();
  }

  /*SLEEPS UNTIL NEXT MEASUREMENT CYCLE ########################################
  */
  startTime = millis();
  while (millis() - startTime < sleepDuration) {
    writeLCD(5);
    delay(950);
    if (checkButtonHigh(PAUSE_BUTTON)) {
      delay(1000);
      /*Creates and saves an ERROR LOG FILE, to register any monitored errors occurred during execution. */
      /*Creates the file and opens it*/
      //Commented out due to lack of memory in Uno
      //createErrorLogFile();

      /*Allow user to remove SD card since LOG ERROR file creation has endeed */
      writeLCD(15);
      delay(2000);
      writeLCD(16);
      while (!checkButtonHigh(PAUSE_BUTTON)) {
        //Waits until PAUSE_BUTTON is pressed again, which will make sketch go out of this while loop.
        writeLCD(15);
        delay(2000);
        writeLCD(16);
        delay(2000);
      }
      //Initialize SD again.
      initializeSD();

    }
  }
}




///////////////////////////////////////////////////////////////////// FUNCTIONS /////////////////////////////////////////////////////////////////////

void initializeSD () {
  /* This function is used after every time the microSD card is inserted in the system: either when the system is turning on, or after the card is removed during
  //runtime to allow for partial collection of data.
  //This function first checks if the microSD card is present and can be initialized. 
  //If not, printing a message that the system is trying to start the microSD card and keep trying again. 
  //When succesful, print a message saying the microSD card could be opened.
  If the microSD card can't be opened, the system may freeze in this function forever (as there is no point in going forward if microSD card is not available to register data)
  */
  delay(1000);
  while (!SD.begin(chipSelect, SD_SCK_MHZ(50))) {
    //SDInitError++;
    writeLCD(INITIALIZING_SD_SCREEN);
    delay(1000);
  }
  writeLCD(SD_INITIALIZED_SCREEN);
  delay(2000);
}

void checkFolderStructure () {
  char folderName[1];
  //Iterate through all active channels and check if their folder exist
  writeLCD(29);
  delay(1500);
  for (byte currentChannel = 1; currentChannel <= sysConfig.numberOfActiveChannelsOption; currentChannel++) {
    sprintf(folderName, "%01d", currentChannel); /*Constructs folderName variable, which will identify the folder to be inspected, with sprintf function */
    //If folder does not exists, create it
    if (!SD.exists(folderName)) {
      SD.mkdir(folderName);
    }
  }
  writeLCD(30);
  delay(1500);
}

int scanSDforAvailableFileNames(byte currentChannel) {
  //Checking SD card for next available name, create file, open file for data writing, check if file could be open.
  /*Checking SD card for next available name
    /*Code snippet based on: https://forum.arduino.cc/index.php?topic=57460.0 */
  unsigned short index = 1;
  writeLCD(31);
  delay(1000);
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
    sprintf(logFile, "%01d/%04d.emm", currentChannel, index);
    if (SD.exists(logFile) == false) {
      break; /*If name does not exist is SD, exit while loop and save index*/
    }
    index++;
  }
  /* if index is higher than 99999999, there are no available file names left */
  if (index > 9999) {
    index = 0;
  }
  /*Return index, which will be the file name of next sample */
  return index;
}

void initializeToWriteBinaryLogFile (byte currentChannel, unsigned int fileOrdinal) {
  /*The binary log file is a binary file (.emm) saved as a string of 16-bit numbers, that are equivalent to the
     measurements begin taken from the sensor.
     Binary file is used since less data is required to write it, speeding up the saving cycle on SD, and, thus, speeding up
     the data sampling frequency.
     The system receives fileOrdinal to indicate the next available file name in SD.
     File names will follow simple algebraic sequence: 00000001.emm, 000000002.emm, so on, always with
     a name with 8 digits, left-paded with zeroes, which is the maximum allowed by "SD.h" library.
  */
  sprintf(logFile, "%01d/%04d.emm", currentChannel, fileOrdinal); /*Constructs logFile variable, which will name the current log file, with sprintf function */
  /*Creates the file and opens it*/
  currentOpenFile = SD.open(logFile, FILE_WRITE);
  currentOpenFile.preAllocate(PREALLOCATE_SIZE);
  delay(1000);
  /*Check if the file created was successfully opened for data writing. If not, try to open again. Save how many errors have occurred. */
  while (!currentOpenFile) { /*will enter IF if dataFile could not be opened.*/
    writeLCD(12);
    currentOpenFile.close();
    currentOpenFile = SD.open(logFile, FILE_WRITE);
    currentOpenFile.preAllocate(PREALLOCATE_SIZE);
    delay(1000);
    //lcd.setCursor(7, 1);
    //SDFileError ++;
    //lcd.print(SDFileError);
  }
}

void initializeToWriteTxtLogFile (byte currentChannel, unsigned int fileOrdinal) {
  /*The txt log file is a ASCII file (.txt), formatted in the following order
     1) a header with sampling general information separed by a carriage return and a newline character:
        a) year, month, day, hour, minute and seconds of the sample
        b) ambient temperature (if DHT22 is present)
        c) ambient humidity (if DHT22 is present)
        d) sampling frequency configured in the system
        e) sampling duration configured in the system
        f) total samples taken on the previous cycle
     2) sensor readings separated with a carriage return and newline character
     The system receives fileOrdinal to indicate the next available file name in SD.
     File names will follow simple algebraic sequence: 00000001.txt, 000000002.txt, so on, always with
     a name with 8 digits, left-paded with zeroes, which is the maximum allowed by "SD.h" library.
  */
  sprintf(logFile, "%01d/%04d.txt", currentChannel, fileOrdinal); /*Constructs logFile variable, which will name the current log file, with sprintf function */
  /*Creates the file and opens it*/
  currentOpenFile = SD.open(logFile, FILE_WRITE);
  delay(1000);
  /*Check if the file created was successfully opened for data writing. If not, try to open again. Save how many errors have occurred. */
  while (!currentOpenFile) { /*will enter IF if dataFile could not be opened.*/
    writeLCD(36);
    currentOpenFile.close();
    currentOpenFile = SD.open(logFile, FILE_WRITE);
    delay(1000);
    //SDFileError ++;
  }
}

void createSysConfigFile () {
  /* This function creates a System Configuration File.
   * 
   * A System Configuration File is a text file (.txt format) encoded in ASCII structured in lines followed by \n and \r characters (i.e., line feed and carriage return).
   * The second line contains the configuration regarding sampling duration of the system (values from 1 to 5).
   * The third line contains the configuration regarding sleep duration of the system (values from 1 to 5).
   * The fourth line contains the configuration regarding the number of active channels of the system (values from 1 to 4)
   * The fifth line contains the configuration regarding the temperature and humidity sensor of the system (values from 1 to 2).
   * 
   */
  byte temporaryVariable = SD.remove(sysConfgFileName); //Delete the file so a new one can be created. 
  //TODO: the variable temporaryVariable should return a value if the system was succesful in this task, but the error handling is not implemented yet.
  delay(200);
  File sysConfigFile = SD.open(sysConfgFileName, FILE_WRITE); //Create a new System Configuration File
  delay(100);
  while (!sysConfigFile) { 
    //Will enter if the file could not be opened.
    //The system will attempt to open the file repeatedly until it is succesful.
    //Meanwhile, it will print a message in the LCD screen to warn the user about it.
    //The system can stay stucked in this state until the microSD card works!
    sysConfigFile.close();
    writeLCD(SYSCNFGFILE_NOT_OPEN_SCREEN);
    sysConfigFile = SD.open(sysConfgFileName, FILE_WRITE);
    delay(2000);
  }

  //Save the configuration values to the System Configuration File
  sysConfigFile.println(sysConfig.samplingFrequencyOption);
  sysConfigFile.println(sysConfig.samplingDurationOption);
  sysConfigFile.println(sysConfig.sleepDurationOption);
  sysConfigFile.println(sysConfig.numberOfActiveChannelsOption);
  sysConfigFile.println(sysConfig.tempHumSensorOption);
  sysConfigFile.close(); //Close the file
}

void readSysConfigFile () {
  /* This function checks if a System Configuration File exists in the system.
   *  If it exists, attempt to open this file. 
   *  If the file can't be opened, an error message is printed in the screen and the process keeps repeating until it can open the file.
   *  When the file can be opened, it reads the file and populates the configuration variables with its contents.
   *  After that, runs a function (checkSysConfigConsistency) to check for configuration consistency: if all the configuration variables are valid. This is to prevent
   *  from external users to manually edit the System Configuration File and crash the system.
   *  If the file does not exist, do nothing. See the comment on the } else { below to check why.  
   *  
   * A System Configuration File is a text file (.txt format) encoded in ASCII structured in lines followed by \n and \r characters (i.e., line feed and carriage return).
   * The second line contains the configuration regarding sampling duration of the system (values from 1 to 5).
   * The third line contains the configuration regarding sleep duration of the system (values from 1 to 5).
   * The fourth line contains the configuration regarding the number of active channels of the system (values from 1 to 4)
   * The fifth line contains the configuration regarding the temperature and humidity sensor of the system (values from 1 to 2).
   * 
   */
  if (SD.exists(sysConfgFileName)) {
    File sysConfigFile = SD.open(sysConfgFileName, FILE_READ);
    delay(100);
    while (!sysConfigFile) { /*will enter IF if dataFile could not be opened.*/
      sysConfigFile.close();
      writeLCD(SYSCNFGFILE_NOT_OPEN_SCREEN);
      sysConfigFile = SD.open(sysConfgFileName, FILE_READ);
      delay(2000);
    }
    byte paramToBeConfigured = 0;
    byte temporaryVariable = 0;
    while (sysConfigFile.available()) {
      //Copy configuration variables form sysConfigFile
      //See the description of this function to understand how the System Configuration File is structured
      sysConfigFile.read((const uint8_t *)&temporaryVariable, sizeof(temporaryVariable));
      if (temporaryVariable == '\n' || temporaryVariable == '\r') {
        //Do nothing, it is new line feed or carriage return characters that separates consecutive lines
      } else {
        //Else, it is a value to be read
        switch (paramToBeConfigured) {
          case 0:
            //Converts from ASCII coding to numerical bytes by subtracing "0"
            sysConfig.samplingFrequencyOption = temporaryVariable - '0';
            paramToBeConfigured = paramToBeConfigured + 1; //Next value to be read will be sampling duration
            break;
          case 1:
            //Converts from ASCII coding to numerical bytes by subtracing "0"
            sysConfig.samplingDurationOption = temporaryVariable - '0';
            paramToBeConfigured = paramToBeConfigured + 1; //Next value to be read will be sleep duration
            break;
          case 2:
            //Converts from ASCII coding to numerical bytes by subtracing "0"
            sysConfig.sleepDurationOption = temporaryVariable - '0';
            paramToBeConfigured = paramToBeConfigured + 1; //Next value to be read will be number of active channels
            break;
          case 3:
            //Converts from ASCII coding to numerical bytes by subtracing "0"
            sysConfig.numberOfActiveChannelsOption = temporaryVariable - '0';
            paramToBeConfigured = paramToBeConfigured + 1; //Next value to be read will be temperature and humidity sensor on/off
            break;
          case 4:
            //Converts from ASCII coding to numerical bytes by subtracing "0"
            sysConfig.tempHumSensorOption = temporaryVariable - '0';
            paramToBeConfigured = paramToBeConfigured + 1;
            break;
        }
      }
    }
    //After populating the sysConfig variable, check its consistency
    checkSysConfigConsistency();
    //Close the System Configuration Variable
    sysConfigFile.close();
  } else {
    //If the System Configuration File does not exist, do nothing.
    //In this implementation, after calling this function and seeing no System Configuration File exists, the next instructions
    //either populate sysConfig variable with default values (and creates an System Configuration File accordingly) or
    //do the same thing with customized test configuration informed by the user through the system user interface.
  }
}

void checkSysConfigConsistency() {
  /* Check if sysConfig variable is accordingly to possible configurations implemented.
   *  This is to prevent from external users to manually edit the System Configuration File and crash the system.
   *  
   * A System Configuration File is a text file (.txt format) encoded in ASCII structured in lines followed by \n and \r characters (i.e., line feed and carriage return).
   * The first line contains the configuration regarding sampling frequency of the system (values from 1 to 5).
   * The second line contains the configuration regarding sampling duration of the system (values from 1 to 5).
   * The third line contains the configuration regarding sleep duration of the system (values from 1 to 5).
   * The fourth line contains the configuration regarding the number of active channels of the system (values from 1 to 4)
   * The fifth line contains the configuration regarding the temperature and humidity sensor of the system (values from 1 to 2).
   */
  byte incorrectSysConfig = false;
  if (sysConfig.samplingFrequencyOption < 1 || sysConfig.samplingFrequencyOption > 5) {
    sysConfig.samplingFrequencyOption = samplingFrequencyOption_Default;
  }
  if (sysConfig.samplingDurationOption < 1 || sysConfig.samplingDurationOption > 5) {
    sysConfig.samplingDurationOption = sleepDurationOption_Default;
  }
  if (sysConfig.sleepDurationOption < 1 || sysConfig.sleepDurationOption > 5) {
    sysConfig.sleepDurationOption = sleepDurationOption_Default;
  }
  if (sysConfig.numberOfActiveChannelsOption < 1 || sysConfig.numberOfActiveChannelsOption > 4) {
    sysConfig.numberOfActiveChannelsOption = numberOfActiveChannelsOption_Default;
  }
  if (sysConfig.tempHumSensorOption < 1 || sysConfig.tempHumSensorOption > 2) {
    sysConfig.numberOfActiveChannelsOption = numberOfActiveChannelsOption_Default;
  }
  if (incorrectSysConfig == true) {
    //If any inconsistency is verified, a brand new System Configuration File is created.
    createSysConfigFile ();
  }
}

bool checkButtonLow(int buttonPin) {
  // This function checks whether buttonPin was pressed
  bool buttonPressed = false;
  bool buttonState = digitalRead(buttonPin);
  if (buttonState == LOW) {
    //The button has been pressed: return True
    buttonPressed = true;
  }
  return buttonPressed;
}

bool checkButtonHigh(int buttonPin) {
  // This function checks whether buttonPin was pressed
  bool buttonPressed = false;
  bool buttonState = digitalRead(buttonPin);
  if (buttonState == HIGH) {
    //The button has been pressed: return True
    buttonPressed = true;
  }
  return buttonPressed;
}

void declareCustomSymbols() {
  /*
     Declare custom symbols for the LCD screen
  */
  lcd.createChar(0, microSymbol_1);
  lcd.createChar(1, microSymbol_2);
  lcd.createChar(2, microSymbol_3);
  lcd.createChar(3, microSymbol_4);
  lcd.createChar(4, microSymbol_6);
  lcd.createChar(5, microSymbol_5);
  lcd.createChar(6, microSymbol_7);
  lcd.createChar(7, pauseButtom_Symbol);
}

void writeLCD(byte specialCase) {
  /*Function to write two sentences to 16x2 LCD screen*/
  int minutes = 0;
  int seconds = 0;
  byte repeat = 0;
  byte loadingBar = 0;

  switch (specialCase) {
    case 2:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*Sensor error */
      lcd.print(F("ERR: Sensor nao"));
      lcd.setCursor(0, 1);
      lcd.print(F("iniciado."));
      //lcd.print(accelInitError);
      break;

    case 3:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*SD initialization error */
      lcd.print(F("ERR: SD nao ini"));
      lcd.setCursor(0, 1);
      lcd.print(F("ciado."));
      //lcd.print(SDInitError);
      break;

    case 5:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      minutes = (millis() - startTime) / (60000);
      seconds = (millis() - startTime) / (1000) - minutes * 60;
      char time_char[7];
      sprintf(time_char, "%02d:%02d", minutes, seconds); //Format the string indicating time
      lcd.print(F("Em espera"));
      lcd.setCursor(0, 1);
      lcd.print(F("t: "));
      lcd.print(time_char);//Print minutes elapsed since sleep start
      break;

    case INITIALIZING_SD_SCREEN:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("SD:Iniciando SD"));
      lcd.setCursor(0, 1);
      //lcd.print(SDInitError);
      break;

    case WELCOME_SCREEN:
      //Print welcome screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.write(byte(5));
      lcd.write(byte(0));
      lcd.write(byte(1));
      lcd.write(byte(5));
      lcd.print(F(" "));
      delay(10);
      lcd.write(byte(4));
      lcd.print(F("EMM-ARM"));
      lcd.setCursor(0, 1);
      lcd.write(byte(5));
      lcd.write(byte(2));
      lcd.write(byte(3));
      lcd.write(byte(5));
      repeat = 0;
      seconds = 0;
      while (repeat < 6) {
        lcd.setCursor(4, 1);
        lcd.print(F("       v0.1"));
        loadingBar = 0;
        while (loadingBar < repeat) {
          lcd.setCursor(5 + loadingBar, 1);
          lcd.write(byte(5));
          loadingBar = loadingBar + 1;
        }
        delay(300);
        repeat = repeat + 1;
      }
      break;

    case 8:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F(" "));
      lcd.write(byte(6));
      lcd.print(F(" p/ cfg ensaio"));
      lcd.setCursor(0, 1);
      lcd.print(F("+- p/ cfg RTC"));
      break;

    case 9:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Entrando em cfg"));
      lcd.setCursor(0, 1);
      lcd.print(F("do ensaio"));
      break;

    case 10:
      //Print the title in Frequency Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Config. freq.:"));
      break;

    case 11:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F(" Ensaio EMM-ARM "));
      lcd.setCursor(0, 1);
      lcd.print(F("iniciando ciclo"));
      break;

    case 12:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("SD:Inic. arqvo"));
      lcd.setCursor(0, 1);
      lcd.print(F(".EMM"));
      break;

    case 13:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("SD:Inic. leitu_"));
      lcd.setCursor(0, 1);
      lcd.print(F("ra do arq. EMM"));
      break;

    case 15:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("SD:cartao pode"));
      lcd.setCursor(0, 1);
      lcd.print(F("ser removido!"));
      break;

    case 16:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Insira SD e"));
      lcd.setCursor(0, 1);
      lcd.print(F("pressione "));
      delay(10);
      lcd.write(byte(7));
      delay(10);
      break;

    case 17:
      //Change the frequency option selected in the Frequency COnfiguration Screen
      lcd.setCursor(0, 1);
      lcd.print(F("                "));
      lcd.setCursor(0, 1);
      switch (sysConfig.samplingFrequencyOption) {
        case 1:
          lcd.print(64);
          lcd.print(F(" Hz"));
          break;
        case 2:
          lcd.print(128);
          lcd.print(F(" Hz"));
          break;
        case 3:
          lcd.print(250);
          lcd.print(F(" Hz"));
          break;
        case 4:
          lcd.print(475);
          lcd.print(F(" Hz"));
          break;
        case 5:
          lcd.print(860);
          lcd.print(F(" Hz"));
          break;
      }
      break;

    case 18:
      //Make the first title in the Sampling Duration Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Duracao amostr.:"));
      break;

    case 19:
      //Change the sampling Duration option selected in the Sampling Duration COnfiguration Screen
      lcd.setCursor(0, 1);
      switch (sysConfig.samplingDurationOption) {
        case 1:
          lcd.print(1);
          lcd.print(F("  s "));
          break;
        case 2:
          lcd.print(10);
          lcd.print(F(" s "));
          break;
        case 3:
          lcd.print(60);
          lcd.print(F(" s "));
          break;
        case 4:
          lcd.print(90);
          lcd.print(F(" s "));
          break;
        case 5:
          lcd.print(120);
          lcd.print(F(" s" ));
          break;
      }
      break;

    case 20:
      //Make the first title in the Sleep Duration Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Duracao pausa:"));
      break;

    case 21:
      //Change the sleep duration option selected in the Sleep Duration COnfiguration Screen
      lcd.setCursor(0, 1);
      switch (sysConfig.sleepDurationOption) {
        case 1:
          lcd.print(1);
          lcd.print(F("  s ")); //Erase one space after "s" spaces since 60 has one digit less than other options
          break;
        case 2:
          lcd.print(60);
          lcd.print(F(" s"));
          break;
        case 3:
          lcd.print(300);
          lcd.print(F(" s"));
          break;
        case 4:
          lcd.print(500);
          lcd.print(F(" s"));
          break;
        case 5:
          lcd.print(600);
          lcd.print(F(" s"));
          break;
      }
      break;

    case 22:
      //Make the first title in the Test Mode Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Modo amostragem:"));
      break;

    case 24:
      //Make the first title in the Channel Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Qtd canais ativ:"));
      break;

    case 25:
      //Change the number of active channels in the Channel Configuration Screen
      lcd.setCursor(0, 1);
      switch (sysConfig.numberOfActiveChannelsOption) {
        //sysConfig.numberOfActiveChannelsOption mapping: #1-1/#2-2/#3-3/#4-4
        case 1:
          lcd.print(sysConfig.numberOfActiveChannelsOption);
          lcd.print(F(" canal "));
          break;
        case 2:
          lcd.print(sysConfig.numberOfActiveChannelsOption);
          lcd.print(F(" canais"));
          break;
        case 3:
          lcd.print(sysConfig.numberOfActiveChannelsOption);
          lcd.print(F(" canais"));
          break;
        case 4:
          lcd.print(sysConfig.numberOfActiveChannelsOption);
          lcd.print(F(" canais"));
          break;
      }
      break;

    case 26:
      //Make the first title in the Channel Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Salvar e sair?"));
      break;

    case 27:
      //Print saving and leaving config screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Salvar e sair?"));
      break;

    case SD_INITIALIZED_SCREEN:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("Cartao SD"));
      lcd.setCursor(0, 1);
      lcd.print(F("inicializado"));
      break;

    case 29:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("SD:verificando "));
      lcd.setCursor(0, 1);
      lcd.print(F("diretorios..."));
      break;

    case 30:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("SD:diretorios "));
      lcd.setCursor(0, 1);
      lcd.print(F("OK!"));
      break;

    case 31:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("SD:nomeando"));
      lcd.setCursor(0, 1);
      lcd.print(F("proximo arquivo"));
      break;

    case 32:
      //Make the first title in the DHT22 Configuration Screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Sensor hum/temp:"));
      break;

    case 33:
      //Change the state of activation of DHT22
      lcd.setCursor(0, 1);
      switch (sysConfig.tempHumSensorOption) {
        //sysConfig.tempHumSensorOption mapping: #1-is On/#2-is off
        case 1:
          lcd.print(F("sensor ligado"));
          break;
        case 2:
          lcd.print(F("sensor desligado"));
          break;
      }
      break;

    case 34:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("DHT:erro ao ler"));
      lcd.setCursor(0, 1);
      lcd.print(F("temperatura!"));
      break;

    case 35:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*System sleeping message*/
      lcd.print(F("DHT:erro ao ler"));
      lcd.setCursor(0, 1);
      lcd.print(F("umidade!"));
      break;

    case 36:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("SD:Inic. escri_"));
      lcd.setCursor(0, 1);
      lcd.print(F("ta no arq. TXT"));
      break;

    case 37:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("SD:Inic. trans_"));
      lcd.setCursor(0, 1);
      lcd.print(F("cricao EMM-TXT"));
      break;

    case SYSCNFGFILE_NOT_OPEN_SCREEN:
      lcd.clear();
      lcd.setCursor(0, 0);
      /*Log error file initialization error*/
      lcd.print(F("SD:Arq. sysConfg"));
      lcd.setCursor(0, 1);
      lcd.print(F("nao aberto."));
      //lcd.print(SDFileError);
      break;

    case 40:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Medicoes individ"));
      lcd.setCursor(0, 1);
      lcd.print(F("iniciando ciclo"));
      break;

    case 41:
      char formattedNumber[2];
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Confg RTC atual:"));
      lcd.setCursor(0, 1);
      sprintf(formattedNumber, "%02d", rtc.hour());
      lcd.print(formattedNumber);
      lcd.print(F(":"));
      sprintf(formattedNumber, "%02d", rtc.minute());
      lcd.print(formattedNumber);
      lcd.print(F(" "));
      sprintf(formattedNumber, "%02d", rtc.day());
      lcd.print(formattedNumber);
      lcd.print(F("/"));
      sprintf(formattedNumber, "%02d", rtc.month());
      lcd.print(formattedNumber);
      lcd.print(F("/"));
      sprintf(formattedNumber, "%02d", rtc.year());
      lcd.print(formattedNumber);
      lcd.setCursor(15, 1);
      lcd.write(byte(7));
      break;

    case 52:
      //Make the first title in the leave RTC Clock screen
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Cfg RTC e sair?"));
      break;

    case 53:
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(F("Entrando em cfg"));
      lcd.setCursor(0, 1);
      lcd.print(F("do RTC"));
      break;

    case 54:
      lcd.setCursor(0, 0);
      lcd.print(F("                "));
      lcd.setCursor(0, 0);
      lcd.print(F("Confg RTC atual:"));
      break;

    case 55:
      lcd.setCursor(0, 0);
      lcd.print(F("                "));
      lcd.setCursor(0, 0);
      lcd.print(F("Press "));
      lcd.write(byte(6));
      lcd.print(F(" p/ selec"));
      break;

    case 56:
      lcd.setCursor(0, 0);
      lcd.print(F("                "));
      lcd.setCursor(0, 0);
      lcd.print(F("Pres +- p/ ajust"));
      lcd.write(byte(6));
      lcd.print(F(" p/ selec"));
      break;

    case 57:
      lcd.setCursor(0, 0);
      lcd.print(F("                "));
      lcd.setCursor(0, 0);
      lcd.print(F("Press "));
      lcd.write(byte(7));
      lcd.print(F(" p/ sair"));
      break;

    default:
      /*Default case*/
      break;
  }
}

void configurationScreen() {
  writeLCD(9);
  for (byte i = 0; i < 5; i++) {
    lcd.setCursor(15, 1);
    lcd.write(byte(5));
    delay(500);
    lcd.setCursor(15, 1);
    lcd.print(F(" "));
    delay(500);
  }
  /*Variable that will indicate which option we are configuring
    to allow update of screen and configuration of the option
    Mapping:
    0 -> configure sampling frequency
    1 -> configure duration of sampling
    2 -> configure length of sleep between consecutive samplings
    3 -> configure how many channels
    4 -> configure if DHT sensor is on
    5 -> configure operation mode
    255 -> indicate leaving the configuration screen
  */
  byte configScreen = 0;
  //Auxiliary variable to indicate whether user wants to leave the configuration screen
  byte exitAndSaveOption = 2; //exitAndSaveOption mapping: #1 - Yes / #2 - No
  byte exitAndSaveOption_RTC = 1;
  //Variable to indicate if screen should be update
  bool updateScreen = true;
  //While configScreen is not equal to 255 (the value which indicates leaving the
  //configuration loop), remain in the loop and keeps allowing configuration
  while (configScreen != 255) {
    switch (configScreen) {
      case 0:
        //Print configure sampling frequency screen
        if (updateScreen == true) {
          writeLCD(10);
          writeLCD(17);
          updateScreen = false;
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (sysConfig.samplingFrequencyOption == 5) {
            sysConfig.samplingFrequencyOption = 1;
          } else {
            sysConfig.samplingFrequencyOption = sysConfig.samplingFrequencyOption + 1;
          }
          writeLCD(17);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (sysConfig.samplingFrequencyOption == 1) {
            sysConfig.samplingFrequencyOption = 5;
          } else {
            sysConfig.samplingFrequencyOption = sysConfig.samplingFrequencyOption - 1;
          }
          writeLCD(17);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          configScreen = 1;
          updateScreen = true;
        }
        break;

      case 1:
        //Print configure sampling duration screen
        if (updateScreen == true) {
          writeLCD(18);
          writeLCD(19);
          updateScreen = false;
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (sysConfig.samplingDurationOption == 5) {
            sysConfig.samplingDurationOption = 1;
          } else {
            sysConfig.samplingDurationOption = sysConfig.samplingDurationOption + 1;
          }
          writeLCD(19);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (sysConfig.samplingDurationOption == 1) {
            sysConfig.samplingDurationOption = 5;
          } else {
            sysConfig.samplingDurationOption = sysConfig.samplingDurationOption - 1;
          }
          writeLCD(19);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          configScreen = 2;
          updateScreen = true;
        }
        break;

      case 2:
        //Print configure sleep duration screen
        if (updateScreen == true) {
          writeLCD(20);
          writeLCD(21);
          updateScreen = false;
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (sysConfig.sleepDurationOption == 5) {
            sysConfig.sleepDurationOption = 1;
          } else {
            sysConfig.sleepDurationOption = sysConfig.sleepDurationOption + 1;
          }
          writeLCD(21);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (sysConfig.sleepDurationOption == 1) {
            sysConfig.sleepDurationOption = 5;
          } else {
            sysConfig.sleepDurationOption = sysConfig.sleepDurationOption - 1;
          }
          writeLCD(21);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          configScreen = 3;
          updateScreen = true;
        }
        break;

      case 3:
        //Print configure active channels screen
        if (updateScreen == true) {
          writeLCD(24);
          writeLCD(25);
          updateScreen = false;
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (sysConfig.numberOfActiveChannelsOption == 4) {
            sysConfig.numberOfActiveChannelsOption = 1;
          } else {
            sysConfig.numberOfActiveChannelsOption = sysConfig.numberOfActiveChannelsOption + 1;
          }
          writeLCD(25);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (sysConfig.numberOfActiveChannelsOption == 1) {
            sysConfig.numberOfActiveChannelsOption = 4;
          } else {
            sysConfig.numberOfActiveChannelsOption = sysConfig.numberOfActiveChannelsOption - 1;
          }
          writeLCD(25);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          configScreen = 4;
          updateScreen = true;
        }
        break;

    case 4:
        //Print configure DHT sensor screen
        if (updateScreen == true) {
          writeLCD(32);
          writeLCD(33);
          updateScreen = false;
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (sysConfig.tempHumSensorOption == 2) {
            sysConfig.tempHumSensorOption = 1;
          } else {
            sysConfig.tempHumSensorOption = sysConfig.tempHumSensorOption + 1;
          }
          writeLCD(33);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (sysConfig.tempHumSensorOption == 1) {
            sysConfig.tempHumSensorOption = 2;
          } else {
            sysConfig.tempHumSensorOption = sysConfig.tempHumSensorOption - 1;
          }
          writeLCD(33);
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          configScreen = 6;
          updateScreen = true;
        }
        break;
        
      case 6:
        //Print exit configuration screen
        if (updateScreen == true) {
          writeLCD(26);
          updateScreen = false;
          lcd.setCursor(0, 1);
          lcd.print(F("Nao"));
          delay(500);
        }
        //If Button "+" (PLUS_BUTTON) was pressed, then
        if (checkButtonLow(PLUS_BUTTON)) {
          if (exitAndSaveOption == 2) {
            exitAndSaveOption = 1;
            lcd.setCursor(0, 1);
            lcd.print(F("Sim"));
          } else {
            exitAndSaveOption = 2;
            lcd.setCursor(0, 1);
            lcd.print(F("Nao"));
          }
          delay(500);//delay so the user can see the system updating
        }
        //If Button "-" (MINUS_BUTTON) was pressed, then
        if (checkButtonLow(MINUS_BUTTON)) {
          if (exitAndSaveOption == 1) {
            exitAndSaveOption = 2;
            lcd.setCursor(0, 1);
            lcd.print(F("Nao"));
          } else {
            exitAndSaveOption = 1;
            lcd.setCursor(0, 1);
            lcd.print(F("Sim"));
          }
          delay(500);//delay so the user can see the system updating
        }
        //If Button "↪" (ARROW_BUTTON) was pressed, then
        if (checkButtonLow(ARROW_BUTTON)) {
          if (exitAndSaveOption == 2) {
            //if exitAndSaveOption is equal to 2, then user wants to keep configurating
            //So, next screen will be the first configuration screen
            configScreen = 0;
          } else {
            //else, the user wants to save and leave configuration
            configScreen = 255;
          }
          updateScreen = true;
        }
        break;
    }

  }
  delay(1000);
}

void configurationRTCScreen() {
  byte minuteRTC = 0; byte hourRTC = 0;
  byte dayRTC = 0; byte monthRTC = 0; byte yearRTC = 0;
  writeLCD(53);
  for (byte i = 0; i < 5; i++) {
    lcd.setCursor(15, 1);
    lcd.write(byte(5));
    delay(500);
    lcd.setCursor(15, 1);
    lcd.print(F(" "));
    delay(500);
  }
  //Get current RTC clock data
  rtc.refresh();
  hourRTC = rtc.hour();
  minuteRTC = rtc.minute();
  dayRTC = rtc.day();
  monthRTC = rtc.month();
  yearRTC = rtc.year();
  writeLCD(41);
#define delayTime 150 //delay time used between setting the variables. Adjust for better user experience
  //Not too slow so setting is not so slow, not to fast so user can have control
  byte selectedConfig = 0;
  byte updateScreen = 0;
  char formattedNumber[2];
  byte switchInfoMessage = 54;
  unsigned long elapsedTime;
  elapsedTime = millis();
  //Loop to allow setting each parameter from RTC
  lcd.setCursor(1, 1);
  while (selectedConfig != 255) {
    //Only update info screen every X miliseconds
    if (millis() - elapsedTime > 5000) {
      elapsedTime = millis();
      writeLCD(switchInfoMessage);
      switchInfoMessage = switchInfoMessage + 1;
      if (switchInfoMessage == 58) {
        switchInfoMessage = 54;
      }
    }
    //Shine the cursor
    lcd.cursor();
    //Check in which option we are
    switch (selectedConfig) {
      case 0:
        //This will allow to set hours
        lcd.setCursor(1, 1);
        if (checkButtonLow(PLUS_BUTTON)) {
          //If Button "+" (MINUS_BUTTON) was pressed, then
          if (hourRTC == 23) {
            hourRTC = 0;
          } else {
            hourRTC = hourRTC + 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(MINUS_BUTTON)) {
          //If Button "-" (MINUS_BUTTON) was pressed, then
          if (hourRTC == 0) {
            hourRTC = 23;
          } else {
            hourRTC = hourRTC - 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 1;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        if (updateScreen == 1) {
          lcd.noCursor();
          lcd.setCursor(0, 1);
          sprintf(formattedNumber, "%02d", hourRTC);
          lcd.print(formattedNumber);
          delay(delayTime);//delay so the user can see the system updating
          updateScreen = 0;
          lcd.setCursor(1, 1);
        }
        break;
      case 1:
        //This will allow to set minutes
        lcd.setCursor(4, 1);
        if (checkButtonLow(PLUS_BUTTON)) {
          //If Button "+" (MINUS_BUTTON) was pressed, then
          if (minuteRTC == 59) {
            minuteRTC = 0;
          } else {
            minuteRTC = minuteRTC + 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(MINUS_BUTTON)) {
          //If Button "-" (MINUS_BUTTON) was pressed, then
          if (minuteRTC == 0) {
            minuteRTC = 59;
          } else {
            minuteRTC = minuteRTC - 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 2;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        if (updateScreen == 1) {
          lcd.noCursor();
          lcd.setCursor(3, 1);
          sprintf(formattedNumber, "%02d", minuteRTC);
          lcd.print(formattedNumber);
          delay(delayTime);//delay so the user can see the system updating
          updateScreen = 0;
          lcd.setCursor(4, 1);
        }
        break;
      case 2:
        //This will allow to set days
        lcd.setCursor(7, 1);
        if (checkButtonLow(PLUS_BUTTON)) {
          //If Button "+" (MINUS_BUTTON) was pressed, then
          if (dayRTC == 31) {
            dayRTC = 1;
          } else {
            dayRTC = dayRTC + 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(MINUS_BUTTON)) {
          //If Button "-" (MINUS_BUTTON) was pressed, then
          if (dayRTC == 1) {
            dayRTC = 31;
          } else {
            dayRTC = dayRTC - 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 3;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        if (updateScreen == 1) {
          lcd.noCursor();
          lcd.setCursor(6, 1);
          sprintf(formattedNumber, "%02d", dayRTC);
          lcd.print(formattedNumber);
          delay(delayTime);//delay so the user can see the system updating
          updateScreen = 0;
          lcd.setCursor(7, 1);
        }
        break;
      case 3:
        //This will allow to set months
        lcd.setCursor(10, 1);
        if (checkButtonLow(PLUS_BUTTON)) {
          //If Button "+" (MINUS_BUTTON) was pressed, then
          if (monthRTC == 12) {
            monthRTC = 1;
          } else {
            monthRTC = monthRTC + 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(MINUS_BUTTON)) {
          //If Button "-" (MINUS_BUTTON) was pressed, then
          if (monthRTC == 1) {
            monthRTC = 12;
          } else {
            monthRTC = monthRTC - 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 4;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        if (updateScreen == 1) {
          lcd.noCursor();
          lcd.setCursor(9, 1);
          sprintf(formattedNumber, "%02d", monthRTC);
          lcd.print(formattedNumber);
          delay(delayTime);//delay so the user can see the system updating
          updateScreen = 0;
          lcd.setCursor(10, 1);
        }
        break;
      case 4:
        //This will allow to set years
        lcd.setCursor(13, 1);
        if (checkButtonLow(PLUS_BUTTON)) {
          //If Button "+" (MINUS_BUTTON) was pressed, then
          if (yearRTC == 99) {
            yearRTC = 0;
          } else {
            yearRTC = yearRTC + 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(MINUS_BUTTON)) {
          //If Button "-" (MINUS_BUTTON) was pressed, then
          if (yearRTC == 0) {
            yearRTC = 99;
          } else {
            yearRTC = yearRTC - 1;
          }
          updateScreen = 1;
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 5;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        if (updateScreen == 1) {
          lcd.noCursor();
          lcd.setCursor(12, 1);
          sprintf(formattedNumber, "%02d", yearRTC);
          lcd.print(formattedNumber);
          delay(delayTime);//delay so the user can see the system updating
          updateScreen = 0;
          lcd.setCursor(13, 1);
        }
        break;
      case 5:
        //This will allow to quit RTC config screen
        lcd.setCursor(15, 1);
        if (checkButtonHigh(PAUSE_BUTTON)) {
          //If Button "||" was pressed, then
          rtc.set(0, minuteRTC, hourRTC, 1, dayRTC, monthRTC, yearRTC);
          selectedConfig = 255;
          lcd.noCursor();
        } else if (checkButtonLow(ARROW_BUTTON)) {
          //If Button "↪" (ARROW_BUTTON) was pressed, then
          selectedConfig = 0;
          delay(4 * delayTime); //delay so the user can see the system updating
        }
        break;
    }
  }
}
