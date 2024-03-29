// clock calendar display
//
// created: Dec 15, 2011 G. D. Young
//
// revised: Dec 22/11 - use PCF8563 chip
//          Dec 23/11 - add year, month setting, display
//          Dec 27,28/11 - add alarm, freq out control
//          Dec 29/11 - add sound o/p
//          Feb 24/12 - using revised i2ckeypad library
//          Mar 06/12 - using Keypad_I2C library
//          Mar 8-9/12 -bar graph, clock 1/sec interrupt
//          Mar 10/12 - ext int timer grab interval
//          Mar 11/12 - correct grabdiff calc error, move 
//                      most of subr to clocksubr.h, initial bar disp
//          Mar 18/12 - set mode entry/exit via keypad ver 0.7
//          Mar 19/12 - bar graph scale adjust
//          Mar 21/12 - select calib/meas with analog comp IC, pin8 IC
//          Mar 22/12 - exit cal mode cleanup - use keypad's PRESSED
//          Mar 23/12 - cleanups, indicator blinks
//          Mar 24/12 - automatic exit from cal mode
//          Mar 25/12 - histogram of cntdiff for auto exit of cal,
//                      suppress erroneous screen displays
//
// Stand-alone version to develop display formatting. Will eventually
// use a real-time clock/calendar IC to retain values over power down.
//  - chip added Dec 22, counters in the IC are used to SET the 
//    'stand-alone' counters, IC is only accessed from setup()
//  - the sound routines are placed in separate 'tabs' which are
//    brought in with #include "clocksubr.h". This is the mechanism
//    arduino uses to implement modules in separate files.

#include <ctype.h>
#include <stdint.h>
#include <avr/interrupt.h>
#include <avr/io.h>
#include <Keypad_I2C.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <LcdBarCentreZero_I2C.h>

#include "clocksubr.h"

// pulse per second handler variables
byte iccnt0[ ] = { 0, 0, 0, 0 };
byte iccnt1[ ] = { 0, 0, 0, 0 };
byte icflag;
byte acicflag;   // when input capture is via comp input
word ovflcnt = 0;
word *iccnt0LS;
word *iccnt0MS;
word iccnt;
word ictmr, ictmrdiff;
byte scale = 5; // for bargraph scale, setup for 0.5 ppm/bar
byte calmode = true;      // startup in calmode - ppsinpin active
byte calentry = true;
byte scalesetmode = HIGH;
byte firstcnt = true;   // flag to ignore invalid differences
word oldcnt, cntdiff;
word caldiff;
int barlength;

// automatic calibration exit histogram method
word calsamp[5];
byte calsnr[5];
byte calidx, calnxt;

// indicator flash timing
long offtime;
byte indpin;

// automatic calibration mode exit
#define AUTOCNT 5
byte autocnt;

// clock_calibration interrupt service routines
// capture interrupt
ISR( TIMER1_CAPT_vect ) {
  // read captured count
//  *iccnt0LS = ICR1;
  iccnt = ICR1;
  *iccnt0MS = ovflcnt;
//  ovflcnt = 0;
  // set flag for background
    icflag = true;
  ictmr = TCNT1;   // grab timer for measure of int response time
} // input capture interrupt service

// timer overflow interrupt
ISR( TIMER1_OVF_vect ) {
  ovflcnt += 1;
} // timer count overflow interrupt service


// setup for interrupt service functions
void setupInputCapt( ) {
  // get pointers to time-holding array(s)
  iccnt0LS = (word *)&iccnt0[2];
  iccnt0MS = (word *)&iccnt0[0];
  pinMode( icindpin, OUTPUT );
  pinMode( ppsinpin, INPUT );
  pinMode( acicpin, INPUT );
  digitalWrite( ppsinpin, HIGH );
  digitalWrite( acicpin, HIGH );
  // set prescaler and set input capture falling edge
//  TCCR1B = 0b00000001;    // xxxxx001 => 16 MHz clocking tmr1
  TCCR1B = 0b01000010;    // xxxxx010 => 2 MHz clocking tmr1
  // rest of control for 'normal port' operation
  TCCR1A = 0;
  // setup comparator input, but leave IC on ppsinpin (ref input)
  DIDR1 = 0b00000011;  // turn off AIN0, AIN1 digital i/p buffers
  ACSR = 0b01010011;   // comp on, AIN0 to BGref, disable ac int, falling edge
  // clear all the timer1 flags
  TIFR1 = 0;
  // enable IC interrupts, OVFL ints, disable others.
  TIMSK1 = 0b00100001;
//    TIMSK1 = 0b00100000; //no overflow ints
  calmode = true;   // go to cal mode on startup
} // setupInputCapt( )

// turn on indicator, setup OFF time
void flash( byte pin, int duration ) {
  digitalWrite( pin, HIGH );
  indpin = pin;
  offtime = millis( ) + duration;
} // flash on

void setup(){
  Wire.begin( );
  Serial.begin( 9600 );         //debug
  lcd2.init();
  lcd2.begin( LCDCOLS, LCDROWS );
  lcd2.clear( );
  lcd2.setCursor( 0, 0 );
  lcd2.print( "Clk 0.7 " );
  lcd2.setCursor( 0, 1 );
  lcd2.setBacklight( HIGH );
  setupBar( scale );                // change centre marker
  errcode = getRtcStatus( state );
  if( errcode ) {
    lcd2.print( "clk st err " );
    lcd2.print( (int)errcode );
  } // if read error
  errcode = getRtcTime( rawtime );
  if( errcode ) {
    lcd2.print( "clk rd err " );
    lcd2.print( (int)errcode );
  } // if read error
  if( errcode == 0 ) {
    lvsignal = ' ';
    if( (rawtime[0]&0x80) == 0x80 ) lvsignal = '?';
    seconds = rawtime[0] & 0x0f;
    seconds += ( (rawtime[0] & 0x70)>>4 )*10;
    minutes = rawtime[1] & 0x0f;
    minutes += ( (rawtime[1] & 0x70)>>4 )*10;
    hours = rawtime[2] & 0x0f;
    hours += ( (rawtime[2] & 0x30)>>4 )*10;
    dom = rawtime[3] & 0x0f;
    dom +=( (rawtime[3]&0x30)>>4 )*10;
    dow = rawtime[4]&0x07;
    month = ( (rawtime[5]&0x10)>>4 )*10;
    month += rawtime[5]&0x0f;
    year = ( (rawtime[6]&0xf0)>>4 )*10;
    year += rawtime[6]&0x0f;
    century = 19;                 // 4-digit year kludge.
    if( year < 80 ) century = 20; 
  } else {
    seconds = 1;     // no clock present default distinctive pattern
    minutes = 2;
    hours = 3;
    dow = 4;
    dom = 5;
    month = 6;
    year = 7;
    century = 20;
  } // if good time available
  setRtcClkOut( (byte)0x83 );  // set clk out to 1 Hz
//  setRtcClkOut( (byte)0 );     // set clk out OFF
  msecounter = millis( );
  pinMode( alarmoutpin, OUTPUT );
  pinMode( acindpin, OUTPUT );
  setupInputCapt( ); // includes setting interrupt input pins mode
  first = true;
  
  kpd.addEventListener( startSetMode );
  kpd.setHoldTime( 600 );

// debug
//  sprintf( str, "%.2x %.2x %.2x ", state[1], rawtime[7], rawtime[8] );
//  Serial.print( str );

} // setup( )


void loop( ) {
  
    setkey = kpd.getKey( );
    if( exitkey ) {
    calmode = false;
    firstcnt = true;
    calentry = true;
    exitkey = false;
//    caldiff = cntdiff;         // grab this value for ref
    ACSR = ACSR | 0b00010100;  // clr flag, enable comp IC
    kbdBeep( NOTE_A5, 100 );
  } // if exit calmode
  
  if( calmode == true && calentry == true ) {
    // switch off comp IC, to allow ref input ICs
    ACSR = ACSR & 0b11110011;  // mask off ACIC, be sure ACIE still 0
    kbdBeep( NOTE_D4, 100 );
    delay( 150 );
    kbdBeep( NOTE_A4, 100 );
    calentry = false;
    autocnt = 0;            // reset automatic exit counter
    firstcnt = true;
  } // if entering calmode

  if( millis( ) > offtime ) digitalWrite( indpin, LOW );

  if( icflag && calmode ) {
    icflag = false;
    flash( icindpin, 250 );
//    cntdiff = *iccnt0LS - oldcnt;
//    oldcnt = *iccnt0LS;
    if( firstcnt ) {
      cntdiff = 0;
      firstcnt = false;
      for( calidx = 0; calidx < 5; calidx++ ) calsnr[calidx] = 0;
      calnxt = 0;      // setup histogram auto exit
    } else {
      cntdiff = iccnt - oldcnt;
    } // ignore invalid oldcnt
    oldcnt = iccnt;
    Serial.print( *iccnt0MS, HEX );
    Serial.print( " " );
    Serial.print( iccnt, HEX );
    ictmrdiff = ictmr - iccnt;
    Serial.print( " diff " );
    Serial.print( cntdiff, HEX );
    Serial.print( " ictmrdiff " );
    Serial.println( ictmrdiff, HEX );
    lcd2.setCursor( 0, 0 );
    lcd2.print( "        " ); // clear screen for cal values
    lcd2.setCursor( 0, 0 );
    lcd2.print( cntdiff, HEX );
    // try to automatically exit from cal mode
//    if( abs( cntdiff - caldiff ) < 2 ) autocnt++;
//    if( autocnt > AUTOCNT ) {
//      exitkey = true;
//      firstcnt = true;  // setup meas to ignore first diff calc
//    } // if count of equal pairs enough
//    caldiff = cntdiff;    // retain for next comparison

    // use histogram of cntdiff values method for auto-exit
    for( calidx = 0; calidx < 5; calidx++ ) {
      if( calsamp[calidx] == cntdiff ) {
        calsnr[calidx]++;
        if( calsnr[calidx] > 5 ) {
          caldiff = calsamp[calidx];  // keep first value found 5 times
          exitkey = true;
          firstcnt = true;
        } // if this value found 5 times
      } // if sample value already in list
    } // loop over saved values
    if( calidx >= 5 ) {
      calsamp[calnxt] = cntdiff;      // save in next available slot
      calnxt++;
      if( calnxt >= 5 ) calnxt = 0;   // loop around to start
    } // if sample value not found
      
  } // if input capt flag set

  if( icflag && !calmode ) {
    icflag = false;
    flash( acindpin, 250 );
    if( firstcnt ) {
      cntdiff = 0;
      firstcnt = false;
    } else {
      cntdiff = iccnt - oldcnt;
    } // ignore first invalid diff
    oldcnt = iccnt;
    Serial.print( *iccnt0MS, HEX );
    Serial.print( " " );
    Serial.print( iccnt, HEX );
    ictmrdiff = ictmr - iccnt;
    Serial.print( " diff " );
    Serial.print( cntdiff, HEX );
    Serial.print( " ictmrdiff " );
    Serial.print( ictmrdiff, HEX );
    barlength = cntdiff - caldiff;
    if( scale == 2 ) barlength = barlength>>2;
    if( scale == 8 ) barlength = barlength>>4;
    Serial.print( " bar " );
    Serial.println( barlength, DEC );
    if( cntdiff != 0 ) {
      zcb.drawBar( barlength, MAXBARS, POSN, LINE );
      lcd2.leftToRight( ); // bar graph uses rightToLeft for neg args
    } // do not draw invalid diff
  }// if analog comparator IC happened

  if( millis( ) >= msecounter+1000 ) {
    msecounter += 1000;
    seconds += 1;
    if( seconds > 59 ) {
      seconds = 0;
      minutes += 1;
      digitalWrite( alarmoutpin, LOW );  //uncomment to clear in 1min
      getRtcStatus( state );    // check for alarm
      if( ( state[1] & 0x08 ) == 0x08 ) {
        digitalWrite( alarmoutpin, HIGH );
        playtune( minutes&3 );
        clrRtcStatus( 0x08 );
      } // if alarm flag
    } // if minute
    if( minutes > 59 ) {
      minutes = 0;
      hours += 1;
    } // if hour
    if( hours > 23 ) {
      hours = 0;
      dow += 1;
    } // if day
    if( dow > 6 ) {
      dow = 0;
    } // if week

    if( first ) {
      sprintf( datestr, "Clk 0.7 %.3s %.2d%.2d",
                   months[month-1], century, year );
      lcd2.noBlink( );
      lcd2.setCursor( 0, 0 );
      lcd2.print( datestr );
      first = false;
    } // put year, month if first pass
    sprintf( datestr, "%.2d:%.2d:%.2d%c %s %.2d", 
             hours, minutes, seconds, lvsignal, days[dow], dom );
    lcd2.noBlink( );
    lcd2.setCursor( 0, 1 );
    lcd2.print( datestr );

  } // if second has elapsed
  
// use keypad HOLD state to enter setmode
  setkey = kpd.getKey( );
  if( setmode == LOW ) {
    sprintf( datestr, "%.2d.%.2d.%.2d %.1d %.2d %.2d", 
                   hours, minutes, seconds, dow, dom, month );
    kbdBeep( NOTE_D4, 100 );
    delay( 150 );
    kbdBeep( NOTE_A4, 100 );
    curpos = 0;
  } // if setmode
  while( setmode == LOW ) {
    lcd2.setCursor( 0, 1 );
    lcd2.print( datestr );
    if( curpos < 17 ) {
      lcd2.setCursor( curpos, 1 );
    } else {
      lcd2.setCursor( curpos-3, 0 );
    } // if setting bottom line
    lcd2.blink( );
    setkey = kpd.getKey( );
    while( setkey == NO_KEY && setmode == LOW ) {
      setkey = kpd.getKey( );
      if( setkey == '+' ) setmode = HIGH; // exit setmode on C key
    } // wait for key
    setting = true;
    if( setmode == LOW ) {
      if( isdigit( setkey ) || setkey == '.' ) {
        kbdBeep( NOTE_A5, 100 );
        inputstr[curpos] = setkey;
        datestr[curpos] = setkey;
        curpos += 1;
      } else {
        kbdBeep( NOTE_A3, 150 );
      } // if entry valid digit or period
    } // only update if still in setmode
  } // while setmode

// use keypad HOLD state to enter setmode
  setkey = kpd.getKey( );
  if( alarmsetmode == LOW ) {
    lcd2.setCursor( 0, 0 );
    lcd2.print( "ALM Set" );
    kbdBeep( NOTE_D4, 100 );
    delay( 150 );
    kbdBeep( NOTE_A4, 100 );
    curpos = 0;
    sprintf( datestr, "mm.hh dm d      " );
  } // if alarmsetmode
  while( alarmsetmode == LOW ) {
    digitalWrite( alarmoutpin, HIGH );
    lcd2.setCursor( 0, 1 );
    lcd2.print( datestr );
    lcd2.setCursor( curpos, 1 );
    lcd2.blink( );
    setkey = kpd.getKey( );
    while( setkey == NO_KEY && alarmsetmode == LOW ) {
      setkey = kpd.getKey( );
      if( setkey == '-' ) alarmsetmode = HIGH; // exit alrmsetmode on C key
    } // wait for key
    digitalWrite( alarmoutpin, LOW );
    alarmsetting = true;
    if( alarmsetmode == LOW ) {
      if( isdigit( setkey ) || setkey == '.' ) {
        kbdBeep( NOTE_A5, 100 );
        inputstr[curpos] = setkey;
        datestr[curpos] = setkey;
        curpos += 1;
      } else {
        kbdBeep( NOTE_A3, 150 );
      } // if entry valid
    } // if still setting
  } // while alarmsetmode
 
// set scale of bargraph
  setkey = kpd.getKey( );
  if( scalesetmode == LOW ) {
    lcd2.setCursor( 0, 0 );
    lcd2.print( "Scale " );
    curpos = 6;
    lcd2.print( 3, DEC );
    kbdBeep( NOTE_D4, 100 );
    delay( 150 );
    kbdBeep( NOTE_A4, 100 );
  } // if scalesetmode
  while( scalesetmode == LOW ) {
    lcd2.setCursor( curpos, 0 );
    lcd2.print( (int)scale, DEC );
    lcd2.setCursor( curpos, 0 );
    lcd2.blink( );
    setkey = kpd.getKey( );
    while( setkey == NO_KEY && scalesetmode == LOW ) {
//      alarmsetmode = digitalRead( alarmsetpin );
      setkey = kpd.getKey( );
      if( setkey == '*' ) {
        scalesetmode = HIGH; // exit alrmsetmode on C key
        setupBar( scale );
        calmode = true;      // go to cal mode next
        calentry = true;
        icflag = false;      // zap any pending ic interrupt
      } // if exit scale setting
    } // wait for key
    if( scalesetmode == LOW ) {
      if( isdigit( setkey ) ) {
        if( setkey == '0' || setkey == '1' || setkey == '2' || setkey == '5' || setkey == '8' ) {
          kbdBeep( NOTE_A5, 100 );
          scale = setkey & 0x0f;
        } else {
          kbdBeep( NOTE_A3, 150 );
        } // if valid scale value
      } else {
        kbdBeep( NOTE_A3, 150 );
      } // if entry valid
    } // if still setting
  } // while scalesetmode
 
  if( setting && ( curpos == 19 || curpos == 8 ) ) { 
    //only set if exact number entries: 8 is time only
    getRtcTime( rawtime );     // get current info in case only time
    inputstr[2] = '\0';
    inputstr[5] = '\0';
    inputstr[8] = '\0';        // separate into individual strings
    inputstr[10] = '\0';
    inputstr[13] = '\0';
    inputstr[16] = '\0';
    inputstr[19] = '\0';
    hours = atoi( &inputstr[0] );
    minutes = atoi( &inputstr[3] );
    seconds = atoi( &inputstr[6] );
    if( curpos > 8 ) {
      dow = atoi( &inputstr[9] );
      dom = atoi( &inputstr[11] );
      month = atoi( &inputstr[14] );
      year = atoi( &inputstr[17] );
      century = 19;
      if( year < 80 ) century = 20;
    } // if setting whole shebang
  // also pack the inputstr chars into the clock bcd format rawtime
    rawtime[2] = (inputstr[0]&0x03)<<4; // hours
    rawtime[2] |= inputstr[1]&0x0f;
    rawtime[1] = (inputstr[3]&0x0f)<<4;  // minutes
    rawtime[1] |= inputstr[4]&0x0f;
    rawtime[0] = (inputstr[6]&0x07)<<4;  // seconds
    rawtime[0] |= inputstr[7]&0x0f;
    if( curpos > 8 ) {
      rawtime[4] = inputstr[9]&0x07;       // day of week
      rawtime[3] = (inputstr[11]&0x03)<<4; // day of month
      rawtime[3] |= inputstr[12]&0x0f;
      rawtime[5] = (inputstr[14]&0x01)<<4; // month
      rawtime[5] |= inputstr[15]&0x0f;
      rawtime[6] = (inputstr[17]&0x0f)<<4; //years
      rawtime[6] |= inputstr[18]&0x0f;
    } // if setting whole shebang
    Wire.beginTransmission( RTC_ADR ); // setup to write to clock
    Wire.send( 0x00 );            // adress pointer <- 0
    Wire.send( 0x20 );            // ctrl 1, STOP bit
    Wire.send( 0x00 );            // ctrl 2, disable ints, alarms
    for( byte ix=0; ix<7; ix++ ) Wire.send( rawtime[ix] );
    Wire.endTransmission( );           // STOP, set all clock regs
    Wire.beginTransmission( RTC_ADR );
    Wire.send( 0x00 );
    Wire.send( 0x00 );
    Wire.endTransmission( );           // restart the counters
//    setRtcClkOut( (byte)0x83 );  // set clk out to 1 Hz
    setting = false;
    first = true;                 // arm for calendar display
    curpos = 0;
    msecounter = millis( );
  } // if setting entry correct
  
  
  if( alarmsetting ) {
    inputstr[2] = '\0';
    inputstr[5] = '\0';
    inputstr[8] = '\0';        // separate into individual strings
    inputstr[10] = '\0';
    rawtime[7] = 0x80;          // clear all alarm enables
    rawtime[8] = 0x80;
    rawtime[9] = 0x80;
    rawtime[10] = 0x80;
    flags = 0x08;
    if( curpos < 2 || curpos > 10 ) {
      // no setting
      lcd2.setCursor( 0, 0 );
      lcd2.print( "NOT Set" );
    } else {
      if( curpos >= 2 ) {
        rawtime[7] = (inputstr[0]&0x07)<<4;   // minute alarm
        rawtime[7] |= inputstr[1]&0x0f;
      } // if minutes entry
      if( curpos >= 5 ) {
        rawtime[8] = (inputstr[3]&0x03)<<4;  // hour alarm
        rawtime[8] |= inputstr[4]&0x0f;
      } // if hour entry
      if( curpos >= 8 ) {
        rawtime[9] = (inputstr[6]&0x03)<<4;  // day of month alarm
        rawtime[9] |= inputstr[7]&0x0f;
        if( rawtime[9] == 0 ) rawtime[9] = 0x80; // 0 means no DOM
      } // if day of month entry
      if( curpos == 10 ) {
        rawtime[10] = inputstr[9]&0x07;       // day of week
      } // if day of week entry
    } // if reasonable number entries

    Wire.beginTransmission( RTC_ADR ); // setup to write to clock
    Wire.send( 0x09 );            // adress pointer <- 9 alarm regs
    for( byte ix=7; ix<11; ix++ ) Wire.send( rawtime[ix] );
    Wire.endTransmission( );      // set all alarm regs
    alarmsetting = false;
    curpos = 0;
    clrRtcStatus( flags );

  } // if alarmsetting
  
  
} // loop( )


void startSetMode( KeypadEvent setkey ) {
  
  switch( kpd.getState( ) ){
  case PRESSED:
      if( setkey == '=' && calmode ) exitkey = true;
      break;
  case HOLD:
      if( setkey == '+' ) {
        setmode = LOW;
      } // if setting key held
      if( setkey == '-' ) {
        alarmsetmode = LOW;
      } // if alarm setting key held
      if( setkey == '*' ) {
        scalesetmode = LOW;
      } // if set scale key held
      if( setkey == '=' ) {
        calmode = true;
      } // if cal key held
      break;  
  case RELEASED:
      break;
  } // switch on keypad state
  
} // startSetMode( )
