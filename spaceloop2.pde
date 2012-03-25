#include "OneWire.h"
#include "LiquidCrystal.h"
#include "TM1638.h"
#include "EEPROM.h"
#include "AnythingEEPROM.h"

#define MAXSENSORS 40
#define MAXZONES   32

byte addr[8];  /* buffer */
byte data[12]; /* buffer */

TM1638        tm(/*dio*/ 2, /*clk*/ 3, /*stb0*/ 4);
OneWire       ds(7);
OneWire       dsprogram(8);
LiquidCrystal lcd(A0, A1, A2, A3, A4, A5);

const byte ledA = 10;
const byte ledB = 11;

byte addrs[MAXSENSORS][8];
byte nsensors = 0;
byte wantedsensors = 0;

struct sensorid {
    byte zone;
    byte nr;
};
sensorid ids[MAXSENSORS];

bool blinkstate = false; 
char zonenamebuf[256];  // Actual buffer, copied from EEPROM
char* zonenames[MAXZONES];    // Pointers to strings in zonenamebuf


extern int __bss_end;
extern void *__brkval;

int get_free_memory() {
    int free_memory;
    if((int)__brkval == 0)
         free_memory = ((int)&free_memory) - ((int)&__bss_end);
    else free_memory = ((int)&free_memory) - ((int)__brkval);
    return free_memory;
}


char reverse_bits (unsigned char byte) {
    unsigned char ret;
    for ( unsigned char i = 0; i < 8; ++i ) {
        ret = ( ret << 1 ) | ( byte & 1 );
        byte >>= 1;
    }

    return ret;
}

void redgreen (char b) {
    if (b == 0) {
        tm.setLEDs(0xFF00);
        digitalWrite(ledA, LOW);
        digitalWrite(ledB, HIGH);
    } else if (b == 1) {
        tm.setLEDs(blinkstate ? 0x18E0 : 0x1807);
        digitalWrite(ledA, HIGH);
        digitalWrite(ledB, blinkstate ? HIGH : LOW);
    } else {
        digitalWrite(ledA, LOW);
        digitalWrite(ledB, LOW);
    }
}

void display_numtext (unsigned char num, char* text) {
    char numstr[9] = "";
    itoa(num, numstr, 10);
    char str[9] = "        ";
    byte width = 4;
    strcpy(&str[width - strlen(text)], text);
    strcpy(&str[width], "    ");
    strcpy(&str[8 - strlen(numstr)], numstr);
    tm.setDisplayToString(str);
}

float celsius(byte d[12]) {
    unsigned int raw = (d[1] << 8) | d[0];

    byte cfg = d[4]; 

    raw >>=
        cfg == 0x1F ? 3
      : cfg == 0x3F ? 2
      : cfg == 0x5F ? 1 : 0;

    float rate =
        cfg == 0x1F ? 0.5
      : cfg == 0x3F ? 0.25
      : cfg == 0x5F ? 0.125
      : cfg == 0x7F ? 0.0625 : 1;

    float ret = (float)raw * rate;
    return ret;
}


void scan(bool complain = 0) {
    sensorid stored[MAXSENSORS];
    EEPROM_readAnything(256, stored);

    nsensors = 0;
    wantedsensors = 0;

    ds.reset_search();
    while (ds.search(addr)) {
        if (OneWire::crc8(addr, 7) != addr[7]) continue;
        for (byte i = 0; i < 8; i++) addrs[nsensors][i] = addr[i];

        ds.write(0xBE);  // read scratchpad
        for (byte i = 0; i < 9; i++) data[i] = ds.read();
        ids[nsensors].zone = data[2];
        ids[nsensors].nr   = data[3];

        nsensors++;
    }
    Serial.print(nsensors); Serial.println(" sensors found.\n");

    wantedsensors = nsensors;
    for (byte i = 0; i < MAXSENSORS; i++) {
        sensorid id = stored[i];
        if (id.zone == 0 && id.nr == 0) break;
        bool found = 0;
        for (byte j = 0; j < nsensors; j++) {
            if (id.zone == ids[j].zone && id.nr == ids[j].nr) {
                found = 1;
                break;
            }
        }
        if (found) continue;

        ids[wantedsensors].zone = id.zone;
        ids[wantedsensors].nr   = id.nr;
        wantedsensors++;

        if (complain) {
            lcd.clear();
            lcd.print("MISSING SENSOR");
            lcd.setCursor(0, 1);
            lcd.print(zonenames[ id.zone ]);
            if (id.nr & 0x7F) { // Skip if 0
                lcd.print(" ");
                lcd.print(id.nr & 0x7F, DEC);
            }
            delay(2500);
        }
    }

    if (nsensors == wantedsensors) {
        if (nsensors < MAXSENSORS) {
            ids[nsensors].zone = 0;
            ids[nsensors].nr   = 0;
        }
        EEPROM_writeAnything(256, ids);
    }
}

void program() {
    lcd.clear();
    lcd.print("PROGRAMMING MODE");
    redgreen(2);

    if (OneWire::crc8(addr, 7) != addr[7]) return;

    dsprogram.reset();
    dsprogram.select(addr);
    dsprogram.write(0xBE);  // read scratchpad
    for (byte i = 0; i < 9; i++) data[i] = dsprogram.read();
    if (data[8] != OneWire::crc8(data, 8)) return;

    unsigned char zone = data[2];  // user byte 1
    unsigned char nr   = data[3];  // user byte 2

    zone = reverse_bits(zone) & 0xF1;
    byte keys = 0;
    while (! (keys & 0x02)) {
        unsigned short disp = reverse_bits(zone);
        display_numtext(disp, "ZONe");
        tm.setLEDs(zone + 0x0200);
        keys = tm.getButtons();
        if (keys) delay(300);  // debounce;
        zone ^= (keys & 0xF8);
    }
    zone = reverse_bits(zone);

    while (tm.getButtons() & 0x02);
    delay(300); // debounce

    nr = reverse_bits(nr) & 0xF9;
    keys = 0;
    while (! (keys & 0x02)) {
        unsigned short disp = reverse_bits(nr);
        if (disp & 0x80) display_numtext(disp & 0x7F, "S-nr");
        else             display_numtext(disp & 0x7F, "T-nr");
        tm.setLEDs(nr + 0x0200);
        keys = tm.getButtons();
        if (keys) delay(300);  // debounce;
        nr ^= (keys & 0xF9);
    }
    nr = reverse_bits(nr);
    delay(300); // debounce

    tm.setDisplayToString("done    "); delay(1000);

    dsprogram.reset();
    dsprogram.select(addr);
    dsprogram.write(0x4e);  // write scratchpad
    dsprogram.write(zone);  // user byte 1
    dsprogram.write(nr);    // user byte 2
    dsprogram.write(0x1f);  // config: 9 bits resolution

    dsprogram.reset();
    dsprogram.select(addr);
    dsprogram.write(0x48);  // copy scratchpad to eeprom

    tm.setDisplayToString("unplug  ");

    while (data[8] == OneWire::crc8(data, 8)) {
        dsprogram.reset();
        dsprogram.select(addr);
        dsprogram.write(0xBE);  // read scratchpad
        for (byte i = 0; i < 9; i++) data[i] = dsprogram.read();
    }

    tm.setDisplayToString("yay     ");
    delay(3000);
    tm.clearDisplay();
}

void setup() {
    Serial.begin(9600);
    lcd.begin(20, 2);
    lcd.print("Hoi wereld");

    EEPROM_readAnything(0, zonenamebuf);
    char index = 0;
    for (int i = 0; i < 255; i++)
        if (zonenamebuf[i] == '\0') zonenames[++index] = &zonenamebuf[i] + 1;


    pinMode(ledA, OUTPUT);
    pinMode(ledB, OUTPUT);

    scan(1);
    tm.clearDisplay();
}


void loop() {
    static unsigned int iteration = 0;
    static unsigned long blinkflip = millis();
    static unsigned long nextprint = millis();

    // Serial.println(get_free_memory());
    dsprogram.reset_search();
    if (dsprogram.search(addr)) program();

    if (millis() >= blinkflip) {
        blinkflip = millis() + (nsensors == wantedsensors ? 500 : 2000);
        blinkstate = !blinkstate;
    }

    bool printtemp = 0;
    if (millis() >= nextprint) {
        nextprint = millis() + 5000;
        printtemp = 1;
    }

    if (nsensors != wantedsensors) scan();

    ds.reset();
    ds.skip();
    ds.write(0x44);  // convert temperature
    while (!ds.read());  // wait until finished


    byte numfound = 0;
    byte numtemp = 0;   // numfound - num85 :)
    float sum = 0;
    float min = 150;
    float max = -30;
    byte found[MAXSENSORS];

    for (byte n = 0; n < wantedsensors; n++) {
        found[n] = 0;
        if (n >= nsensors) continue;

        sensorid id = ids[n];
        ds.reset();
        ds.select(addrs[n]);
        ds.write(0xbe);  // read scratchpad
        for (byte i = 0; i < 9; i++) data[i] = ds.read();
        if (data[8] != OneWire::crc8(data, 8)) continue;

        float c = celsius(data);
        if (c != 85) {
            if (printtemp) {
                Serial.print(zonenames[ id.zone ]);
                Serial.print("("); Serial.print(id.zone, DEC);
                Serial.print(") ");
                Serial.print(id.nr & 0x80 ? "s" : "t");
                Serial.print(id.nr & 0x1F, DEC); Serial.print(": ");
                Serial.println(c, 1);
            }
            sum += c;
            if (c < min) min = c;
            if (c > max) max = c;
            numtemp++;
        }

        found[n] = 1;
        numfound++;
    }

    static byte prevfound[MAXSENSORS];
    bool anychange = 0;
    for (byte n = 0; n < nsensors; n++) {
        if (found[n] != prevfound[n]) {
            sensorid id = ids[n];
            anychange = 1;
            Serial.print(zonenames[ id.zone ]);
            if (id.nr & 0x1F) {
                Serial.print(" ");
                Serial.print(id.nr & 0x1F, DEC);
            }
            Serial.println(found[n] ? " closed" : " open");
        }
        prevfound[n] = found[n];
    }

    if (numfound < wantedsensors) {
        redgreen(1);
        if (anychange) {
            lcd.clear();
            byte y = 0;
            for (byte n = 0; n < wantedsensors; n++) {
                sensorid id = ids[n];
                if (!found[n] && (id.nr & 0x80)) {
                    lcd.setCursor(0, y++);
                    lcd.print(zonenames[ id.zone ]);
                    if (id.nr & 0x7F) { // Skip if 0
                        lcd.print(" ");
                        lcd.print(id.nr & 0x7F, DEC);
                    }
                }
            }
        }
    } else {
        if (anychange) iteration = 0;
        redgreen(0);
        if (!(iteration++ % 100)) {
            float avg = sum / numtemp;
            lcd.clear();
            lcd.print("min="); lcd.print(min, 0);
            lcd.print(" avg="); lcd.print(avg, 1);
            lcd.setCursor(0, 1);
            lcd.print("max="); lcd.print(max, 0);
        }
    }

    byte keys = tm.getButtons();
    if (keys == 0x01)
        tm.setDisplayToDecNumber(get_free_memory(), 0);
    else if (keys == 0x02)
        tm.setDisplayToDecNumber(numfound, 0);
    else if (keys == 0x04)
        tm.setDisplayToDecNumber(nsensors, 0);
    else if (keys == 0x20)
        tm.setDisplayToDecNumber(wantedsensors, 0);
    else if (keys == 0x18 && numfound < wantedsensors) {
        Serial.println("aoeuaoeu");
        sensorid store[MAXSENSORS];
        byte nstored = 0;;
        for (byte i = 0; i < nsensors; i++) {
            if (found[i]) {
                store[nstored].zone = ids[i].zone;
                store[nstored].nr   = ids[i].nr;
                nstored++;
            }
        }
        if (nstored < MAXSENSORS) {
            store[nstored].zone = 0;
            store[nstored].nr   = 0;
        }
        EEPROM_writeAnything(256, store);
        scan();
        while (tm.getButtons());
        delay(500); // debounce
    }
    else if (!keys)
        tm.clearDisplay();

//    delay(1000);

}
