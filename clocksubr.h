/* Revised Dec 29/11 as a subr for clock05 - G. D. Young


*/
#include <Keypad_I2C.h>
#include <Wire.h>

#define ADDR1 0x21
#define ROWS 4
#define COLS 4

char keymap1[ROWS][COLS] = {
  {'1','2','3','+'},
  {'4','5','6','-'},
  {'7','8','9','*'},
  {'c','0','.','='}
};
byte rowPins1[ROWS] = {0, 1, 2, 3}; //connect to the row pin bit# of the keypad
byte colPins1[COLS] = {4, 5, 6, 7}; //connect to the column pin bit #

Keypad_I2C kpd( makeKeymap(keymap1), rowPins1, colPins1, ROWS, COLS, ADDR1 );

#define LCDCOLS 16
#define LCDROWS 2
#define LCD_ADR 0x20

#define RTC_ADR 0x51      //7-bit adr - datasheet A2 write, A3 read
#define RTC_ST_RD_ERR 1   //clock access error codes - status read
#define RTC_TM_RD_ERR 2   // ..time read




#include <LiquidCrystal_I2C.h>
#include <LcdBarCentreZero_I2C.h>

#define MAXBARS 10        //length of display, either side
#define POSN 3            // character position for bargraph
#define LINE 0            // line of lcd for bargraph

LiquidCrystal_I2C lcd2( LCD_ADR, LCDCOLS, LCDROWS );
LcdBarCentreZero_I2C zcb( &lcd2 );     // create bar graph instance

// bar graph variables
int barCount = 0;         // -- value to plot for this example

// clock variables
const char days[ 7 ][ 4 ] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const char months[ 12 ][ 4 ] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
int seconds;
int minutes;
int hours;
int dow;
int dom;
int month;
int year;
int century;
char lvsignal;

long msecounter;
char datestr[32];

char str[32];
byte state[2];
byte rawtime[16];

// setting variables
// const byte setpin = 2;
// const byte extint0pin = 2;   //use ext int on pin 2
const byte acicpin = 7;         // ac input AIN1
const byte acicpin0 = 6;        // ac input AIN0
const byte alarmoutpin = 11;
const byte ppsinpin = 8;      // pulse per second input capture input
const byte icindpin = 13;     // indicator for ref pps input
const byte acindpin = 10;     // indicator for meas input
byte curpos = 0;
byte setmode = HIGH;
byte alarmsetmode = HIGH;
byte setting = false;
byte alarmsetting = false;
byte setkey, exitkey;
char inputstr[32];    // a few extra chars only protection of overrun

byte flags;
byte errcode;
byte first;           // flag to control top line printing


// for bargraph display centre marker
byte carat1[8] = {
  B00000,
  B00000,
  B01010,
  B00100,      // centre marker, alternate style
  B00000,
  B00100,
  B00100,
  B00100
};
byte carat2[8] = {
  B00000,
  B00000,
  B01010,
  B00100,      // centre marker plus right 1 bar
  B00001,
  B00101,
  B00101,
  B00101
};
byte carat3[8] = {
  B00000,
  B00000,
  B01010,
  B00100,      // centre marker plus left 1 bar
  B10000,
  B10100,
  B10100,
  B10100
};

byte scone1[8] = {
  B00100,
  B00100,
  B00100,
  B00100,
  B00000,      // one centre marker
  B00100,
  B00100,
  B00100
};
byte scone2[8] = {
  B00100,
  B00100,
  B00100,
  B00100,
  B00001,      // one centre marker plus right 1 bar
  B00101,
  B00101,
  B00101
};
byte scone3[8] = {
  B00100,
  B00100,
  B00100,
  B00100,
  B10000,      // one centre marker plus left 1 bar
  B10100,
  B10100,
  B10100
};

byte sctwo1[8] = {
  B00110,
  B01010,
  B00100,
  B01110,
  B00000,      // two centre marker
  B00100,
  B00100,
  B00100
};
byte sctwo2[8] = {
  B00110,
  B01010,
  B00100,
  B01110,
  B00001,      // two centre marker plus right 1 bar
  B00101,
  B00101,
  B00101
};
byte sctwo3[8] = {
  B00110,
  B01010,
  B00100,
  B01110,
  B10000,      // two centre marker plus left 1 bar
  B10100,
  B10100,
  B10100
};

byte scfour1[8] = {
  B00010,
  B00110,
  B01110,
  B00010,
  B00000,      // four centre marker
  B00100,
  B00100,
  B00100
};
byte scfour2[8] = {
  B00010,
  B00110,
  B01110,
  B00010,
  B00001,      // four centre marker plus right 1 bar
  B00101,
  B00101,
  B00101
};
byte scfour3[8] = {
  B00010,
  B00110,
  B01110,
  B00010,
  B10000,      // four centre marker plus left 1 bar
  B10100,
  B10100,
  B10100
};

byte scfive1[8] = {
  B01110,
  B01100,
  B00010,
  B01100,
  B00000,      // five centre marker
  B00100,
  B00100,
  B00100
};
byte scfive2[8] = {
  B01110,
  B01100,
  B00010,
  B01100,
  B00001,      // five centre marker plus right 1 bar
  B00101,
  B00101,
  B00101
};
byte scfive3[8] = {
  B01110,
  B01100,
  B00010,
  B01100,
  B10000,      // five centre marker plus left 1 bar
  B10100,
  B10100,
  B10100
};

byte sceight1[8] = {
  B00100,
  B01010,
  B00100,
  B01010,
  B00100,      // eight centre marker
  B00000,
  B00100,
  B00100
};
byte sceight2[8] = {
  B00100,
  B01010,
  B00100,
  B01010,
  B00101,      // eight centre marker plus right 1 bar
  B00001,
  B00101,
  B00101
};
byte sceight3[8] = {
  B00100,
  B01010,
  B00100,
  B01010,
  B10100,      // eight centre marker plus left 1 bar
  B10000,
  B10100,
  B10100
};

void setupBar( byte scale ) {
  zcb.loadCG( );
  if( scale == 0 ) {
    TCCR1B = 0b00000001;    // xxxxx001 => 16 MHz clocking tmr1
    lcd2.createChar( 1, carat1 );    //use alternate centre marker
    lcd2.createChar( 2, carat2 );    //use alternate centre marker
    lcd2.createChar( 3, carat3 );    //use alternate centre marker
  } // if scale == 0
  if( scale == 5 ) {
    TCCR1B = 0b00000010;    // xxxxx010 => 2 MHz clocking tmr1
    lcd2.createChar( 1, scfive1 );    //use alternate centre marker
    lcd2.createChar( 2, scfive2 );    //use alternate centre marker
    lcd2.createChar( 3, scfive3 );    //use alternate centre marker
  } // if scale == 1    
  if( scale == 2 ) {
    TCCR1B = 0b00000010;    // xxxxx010 => 2 MHz clocking tmr1
    lcd2.createChar( 1, sctwo1 );    //use alternate centre marker
    lcd2.createChar( 2, sctwo2 );    //use alternate centre marker
    lcd2.createChar( 3, sctwo3 );    //use alternate centre marker
  } // if scale == 2    
//  if( scale == 4 ) {
//    lcd2.createChar( 1, scfour1 );    //use alternate centre marker
//    lcd2.createChar( 2, scfour2 );    //use alternate centre marker
//    lcd2.createChar( 3, scfour3 );    //use alternate centre marker
//  } // if scale == 4    
  if( scale == 8 ) {
    TCCR1B = 0b00000010;    // xxxxx010 => 2 MHz clocking tmr1
    lcd2.createChar( 1, sceight1 );    //use alternate centre marker
    lcd2.createChar( 2, sceight2 );    //use alternate centre marker
    lcd2.createChar( 3, sceight3 );    //use alternate centre marker
  } // if scale == 8    
} // setupBar( )

byte getRtcStatus( byte *st ) {
  Wire.beginTransmission( RTC_ADR ); // start write to slave
  Wire.send( (uint8_t) 0x00 );    // set adr pointer to status 1
  Wire.endTransmission();
  errcode = Wire.requestFrom( RTC_ADR, 2 ); // request control_status_1 and 2
  if( errcode == 2 ) {
    st[0] = Wire.receive( );
    st[1] = Wire.receive( );
    return 0;
  } else {
    return RTC_ST_RD_ERR;
  } // if RTC responded with 2 bytes
} // getRtcStatus

byte clrRtcStatus( uint8_t fl ) {
  state[1] = state[1] & (~fl);    // reflect new state immediately
  Wire.beginTransmission( RTC_ADR ); // start write to slave
  Wire.send( (uint8_t) 0x01 );    // set adr pointer to status 2
  Wire.send( (uint8_t) state[1] );
  Wire.endTransmission();
  return 0;
} // clrRtcStatus

byte getRtcTime( byte *rt ) {
  Wire.beginTransmission( RTC_ADR ); // start write to slave
  Wire.send( (uint8_t) 0x02 );    // set adr pointer to VL_seconds
  Wire.endTransmission();
  errcode = Wire.requestFrom( RTC_ADR, 11 ); // request control_status_1 and 2
  if( errcode == 11 ) {
    for( byte ix=0; ix<11; ix++ ) {
      *(rt+ix) = Wire.receive( );
    } // for received bytes
    return 0;
  } else {
    return RTC_TM_RD_ERR;
  } // if RTC responded with 7 bytes
} // getRtcTime

void setRtcClkOut( byte ctrl ) {
  Wire.beginTransmission( RTC_ADR );
  Wire.send( (uint8_t) 0x0d );  // adr pointer to contro reg
  Wire.send( (uint8_t) ctrl );
  Wire.endTransmission( );
} // setRtcClkOut


/* Melody
 
 Plays a melody 
 
 created 21 Jan 2010
 modified 30 Aug 2011
 by Tom Igoe 
 */

 #include "pitches.h"
 
 #define TONEPIN 12
 #define EXTMULT 8    // provide for external division by EXTMULT
 #define REST 2
 
// pre-calculate note durations in duration array
int wn = 1000;   // whole note duration

    // to calculate the note duration, take one second 
    // divided by the note type.
    //e.g. quarter note = 1000 / 4, eighth note = 1000/8, etc.
//    int noteDuration = 1000/noteDurations[thisNote];

int melody0[] = {
  NOTE_C4, NOTE_G3,NOTE_G3, NOTE_A3, NOTE_G3, REST, NOTE_B3, NOTE_C4,0};

// note durations: 4 = quarter note, 8 = eighth note, etc.:
int noteDurations0[ ] = {
  wn/4, wn/8, wn/8, wn/4, wn/4, wn/4, wn/4, wn/4, 0 };

int melody1[] = {
   NOTE_G3, NOTE_G3, NOTE_G3, NOTE_G4, NOTE_B3, NOTE_G4, 0 };
int noteDurations1[ ] = {
       wn/8,   wn/8,   wn/8,     wn/4,    wn/8,    wn/1, 0 };

int melody2[ ] = {
  NOTE_C4, NOTE_C4, NOTE_G4, NOTE_G4, NOTE_A4, NOTE_A4, NOTE_G4, 
  NOTE_F4, NOTE_F4, NOTE_E4, NOTE_E4, NOTE_D4, NOTE_D4, NOTE_C4,
  NOTE_G4, NOTE_G4, NOTE_F4, NOTE_F4, NOTE_E4, NOTE_E4, NOTE_D4,
  NOTE_G4, NOTE_G4, NOTE_F4, NOTE_F4, NOTE_E4, NOTE_E4, NOTE_D4,
  NOTE_C4, NOTE_C4, NOTE_G4, NOTE_G4, NOTE_A4, NOTE_A4, NOTE_G4,
  NOTE_F4, NOTE_F4, NOTE_E4, NOTE_E4, NOTE_D4, NOTE_D4, NOTE_C4, 0 };
int noteDurations2[ ] = {
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2,
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2,
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2,
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2,
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2,
   wn/4,    wn/4,     wn/4,    wn/4,    wn/4,    wn/4,   wn/2, 0 };
   

int* mptr;
int* dptr;

void playtune( uint8_t tunenr ) {

  switch( tunenr ) {
    case 0:
            mptr = &melody0[0];
            dptr = &noteDurations0[0];
            break;
    case 1:
            mptr = &melody1[0];
            dptr = &noteDurations1[0];
            break;
    case 2:
            mptr = &melody2[0];
            dptr = &noteDurations2[0];
            break;
    default:
            mptr = &melody0[0];
            dptr = &noteDurations0[0];
  }; // switch on tune selector
  // iterate over the notes of the melody:
//  for (int thisNote = 0; thisNote < NRNOTES; thisNote++) {
//  int thisNote = 0;
  while( *mptr ) {
    int freq = EXTMULT * (*mptr);
    if( freq < NOTE_B1 ) freq = 0;  // insert rest
    tone(TONEPIN, freq, *dptr );

    // to distinguish the notes, set a minimum time between them.
    // the note's duration + 30% seems to work well:
//    int pauseBetweenNotes = noteDurations[thisNote] * 1.30;
    int pauseBetweenNotes = *dptr * 1.30;
    delay(pauseBetweenNotes);
    // stop the tone playing:
    noTone(TONEPIN);
//    thisNote++;
    mptr++;
    dptr++;
  } // loop over notes
} // playtune

void kbdBeep( int note, int durn ) {
  tone( TONEPIN, EXTMULT*note, durn );
} // kbdBeep


