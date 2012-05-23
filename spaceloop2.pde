#include "spaceloop2.h"
#include "OneWire.h"
#include "LiquidCrystal.h"
#include "TM1638.h"
#include "EEPROM.h"
#include "AnythingEEPROM.h"
#include <avr/pgmspace.h>

#define MAXSENSORS 40
#define MAXZONES   32
#define BUSES      4
#define TEXTLINES  4
#define TEXTCOLS   20

byte addr[8];  /* buffer */
byte data[12]; /* buffer */

TM1638        tm(/*dio*/ 2, /*clk*/ 3, /*stb0*/ 4);
OneWire       buses[BUSES] = {
    OneWire(6),
    OneWire(7),
    OneWire(8),
    OneWire(9)
};
#define dsprogram buses[2]

LiquidCrystal lcd(A0, A1, A2, A3, A4, A5);

const byte ledA = 10;
const byte ledB = 11;

byte      addrs[ MAXSENSORS ][9];  // 9th byte is bus-index; OneWire ignores it
sensorid    ids[ MAXSENSORS ];
byte    present[(MAXSENSORS + 7) / 8];
byte       good[(MAXSENSORS + 7) / 8];

float min = -199;
float max = -199;
float avg;
sensorid minid = { 0, 0 };
sensorid maxid = { 0, 0 };

byte known;    // Number of sensors known (from EEPROM or search)
byte seen;     // Number of sensors actually encountered on any bus since reset
byte current;  // Number of sensors currently on their respective busses
byte missing;  // Number of "s"-sensors currently missing (open)

char state;     // 0: closed, 1: open, -2: leds off (program or init)
bool seen_all;  // 0: keep searching (slow), 1: don't search (fast)

char zonenamebuf[256];     // Actual buffer, copied from EEPROM
char* zonenames[MAXZONES]; // Pointers to strings in zonenamebuf

extern int __bss_end;
extern void *__brkval;

int get_free_memory() {
    int free_memory;
    if((int)__brkval == 0)
         free_memory = ((int)&free_memory) - ((int)&__bss_end);
    else free_memory = ((int)&free_memory) - ((int)__brkval);
    return free_memory;
}

void clear_bit(byte* array, byte index) {        array[index/8] &= ~(1 << (index%8)); }
void   set_bit(byte* array, byte index) {        array[index/8] |=  (1 << (index%8)); }
bool  test_bit(byte* array, byte index) { return array[index/8] &   (1 << (index%8)); }

char reverse_bits (unsigned char byte) {
    unsigned char ret = 0;
    for ( unsigned char i = 0; i < 8; ++i ) {
        ret = ( ret << 1 ) | ( byte & 1 );
        byte >>= 1;
    }

    return ret;
}

void set_state(char b) {
    state = b;
    led();
    if (state == 0) closed_view();
    else if (state == 1) open_view();
}

void led() {
    static bool ledblinkstate;
    static unsigned long lednext;

    if (millis() < lednext) return;
    ledblinkstate = !ledblinkstate;
    lednext = millis() + (seen_all ? 500 : 2000);

    if (state == 0) {
        tm.setLEDs(0xFF00);
        digitalWrite(13, HIGH);
        digitalWrite(ledA, LOW);
        digitalWrite(ledB, HIGH);
    } else if (state == 1) {
        tm.setLEDs(ledblinkstate ? 0x18E0 : 0x1807);
        digitalWrite(13, ledblinkstate ? HIGH : LOW);
        digitalWrite(ledA, HIGH);
        digitalWrite(ledB, ledblinkstate ? HIGH : LOW);
    } else {
        digitalWrite(13, LOW);
        digitalWrite(ledA, LOW);
        digitalWrite(ledB, LOW);
    }
}

void mydelay(unsigned long d) {
    d += millis();
    while (d >= millis()) led();
}

void display_numtext (unsigned char num, const char* text) {
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

bool anything_on_bus(OneWire ds) {
    ds.reset_search();
    byte dummy[8];
    return ds.search(dummy);
}

bool seen_sensor(sensorid id) {
    if (!seen) return 0;
    for (byte j = 0; j < seen; j++)
        if (id.zone == ids[j].zone && id.nr == ids[j].nr) return 1;
    return 0;
}

void search() {
    sensorid stored[MAXSENSORS];
    EEPROM_readAnything(256, stored);

    known = 0;

    for (byte b = 0; b < BUSES; b++) {
        OneWire ds = buses[b];

        ds.reset_search();
        while (ds.search(addr)) {
            if (OneWire::crc8(addr, 7) != addr[7]) continue;

            ds.write(0xBE);  // read scratchpad
            for (byte i = 0; i < 9; i++) data[i] = ds.read();
            sensorid id;
            id.zone = data[2];
            id.nr   = data[3];
            if (seen_sensor(id)) continue;

            for (byte i = 0; i < 8; i++) addrs[seen][i] = addr[i];
            addrs[seen][8] = b;
            ids[seen++] = id;
        }
    }

    known = seen;
    // Append any sensors that are known (in EEPROM), but not yet seen.
    for (byte i = 0; i < MAXSENSORS; i++) {
        sensorid id = stored[i];
        if (id.zone == 0 && id.nr == 0) break;
        if (seen_sensor(id)) continue;
        ids[known++] = id;
    }

    if (seen == known) {
        seen_all = true;
        if (seen < MAXSENSORS) {
            ids[seen].zone = 0;
            ids[seen].nr   = 0;
        }
        EEPROM_writeAnything(256, ids);
    }
}

void program() {
    lcd.clear();
    lcd.print("PROGRAMMEERMODUS");
    lcd.setCursor(0, 1);
    lcd.print("2 + 7 = annuleren");
    tm.setLEDs(0x42);

    // Begin with empty bus to avoid re-programming production sensors
    while (anything_on_bus(dsprogram)) {
        tm.setDisplayToString("unplug  ");
        if (tm.getButtons() == 0x42) return;
    }

    tm.setDisplayToString("insert  ");
    dsprogram.reset_search();
    while (!dsprogram.search(addr)) {
        if (tm.getButtons() == 0x42) return;
    }

    if (OneWire::crc8(addr, 7) != addr[7]) return;

    lcd.setCursor(0, 1);
    lcd.print("               ");  // clear

    dsprogram.reset();
    dsprogram.select(addr);
    dsprogram.write(0xBE);  // read scratchpad
    for (byte i = 0; i < 9; i++) data[i] = dsprogram.read();
    if (data[8] != OneWire::crc8(data, 8)) return;

    unsigned char zone = data[2];  // user byte 1
    unsigned char nr   = data[3];  // user byte 2

    zone = reverse_bits(zone) & 0xF8;
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
    dsprogram.write(0x3f);  // config: 9 bits resolution

    dsprogram.reset();
    dsprogram.select(addr);
    dsprogram.write(0x48);  // copy scratchpad to eeprom

    tm.setDisplayToString("unplug  ");
    while (anything_on_bus(dsprogram));

    tm.setDisplayToString("yay     ");
    delay(1500);
}

void print_sensor(Print &target, sensorid id, bool verbose = 0) {
    target.print(zonenames[ id.zone ]);
    if (verbose) {
        target.print("(");
        target.print(id.zone, DEC);
        target.print(") ");
        target.print(id.nr & 0x80 ? "s" : "t");
        target.print(id.nr & 0x1F, DEC);
    } else if (id.nr & 0x1F) {
        target.print(" ");
        target.print(id.nr & 0x1F, DEC);
    }
}

void closed_view() {
    if (min == -199 && max == -199) return;  // Haven't seen any temperatures yet
    lcd.clear();
    lcd.print("\xFF TEMPERATUUR \xFF");
    lcd.setCursor(0, 1);
    lcd.print("L="); lcd.print(min, 0); lcd.print("\xdf" " ");
    lcd.print(zonenames[minid.zone]);
    lcd.setCursor(0, 2);
    lcd.print("H="); lcd.print(max, 0); lcd.print("\xdf" " ");
    lcd.print(zonenames[maxid.zone]);
    lcd.setCursor(0, 3);
    lcd.print("Gemiddeld: "); lcd.print(avg, 1); lcd.print(" \xdf" "C");
    tm.clearDisplay();
}

void setup() {
    Serial.begin(9600);
    Serial.println("[Reset]");

    lcd.begin(TEXTCOLS, TEXTLINES);
    lcd.print("Hoi wereld");
    tm.clearDisplay();

    EEPROM_readAnything(0, zonenamebuf);
    byte index = 0;
    for (int i = 0; i < 255; i++)
        if (zonenamebuf[i] == '\0') zonenames[++index] = &zonenamebuf[i] + 1;

    pinMode(13, OUTPUT);
    pinMode(ledA, OUTPUT);
    pinMode(ledB, OUTPUT);

    set_state(-1);
}

void open_view() {
    byte y = 0;
    lcd.clear();
    if (missing < TEXTLINES) {
        // Enough room for a descriptive line
        lcd.print("SLUITEN VOOR VERTREK");
        y++;
    }
    for (byte n = 0; n < known; n++) {
        if (test_bit(good, n)) continue;
        sensorid id = ids[n];

        lcd.setCursor(0, y);
        print_sensor(lcd, id, 0);
        if (n >= seen) {
            lcd.print(" \xa5");  // &middot;
        }
        if (++y >= TEXTLINES) break;
    }
    if (missing) display_numtext(missing, "OPeN");
    else tm.clearDisplay();
}

void probe(bool print_temperatures) {
    current = 0;        // Counts up
    missing = known;    // Counts down

    byte numtemp = 0;   // Number of valid temperatures, for average
    float sum = 0;
    min = 150;
    max = -30;

    for (byte i = 0; i < BUSES; i++) {
        OneWire ds = buses[i];
        ds.reset();
        ds.skip();
        ds.write(0x44);  // convert temperature
    }
    for (byte i = 0; i < BUSES; i++) {
        // wait until finished converting
        while (!buses[i].read()) led();
    };

    for (byte n = 0; n < known; n++) {
        sensorid id = ids[n];
        byte tries = 0;

        RETRY:
        clear_bit(present, n);
        clear_bit(good, n);
        if (id.nr & 0x80) {
            // T-sensors are always good enough and we don't really miss them
            set_bit(good, n);
            missing--;
        }

        if (n >= seen) continue;  // Don't probe if address unknown

        OneWire ds = buses[ addrs[n][8] ];
        ds.reset();
        ds.select(addrs[n]);
        ds.write(0xbe);  // read scratchpad
        for (byte i = 0; i < 9; i++) data[i] = ds.read();
        if (data[8] != OneWire::crc8(data, 8)) {
            mydelay(10);
            if (tries++ < 3) goto RETRY;
            continue;
        }

        float c = celsius(data);
        if (c < 50) {
            if (print_temperatures) {
                print_sensor(Serial, id, 1);
                Serial.print(": ");
                Serial.println(c, 2);
            }
            sum += c;
            if (id.zone != 20) {  // HACK: skip spacestate
                if (c < min) { min = c; minid = id; }
                if (c > max) { max = c; maxid = id; }
            }
            numtemp++;
        }

        set_bit(present, n);
        set_bit(good, n);
        current++;
        missing--;
    }
    avg = sum / numtemp;
}

void compare(bool printchanges) {
    static byte prev_absent[(MAXSENSORS + 7) / 8];
    for (byte n = 0; n < known; n++) {
        bool present = test_bit(good, n);
        if (printchanges && present == test_bit(prev_absent, n)) {
            Serial.print("[");
            print_sensor(Serial, ids[n], 0);
            Serial.println(present ? " dicht]" : " open]");
        }
        if (present) clear_bit(prev_absent, n);
        else           set_bit(prev_absent, n);
    }
}

void loop() {
    static unsigned long nextprint = millis();

    bool printtemp = 0;
    if (millis() >= nextprint) {
        nextprint = millis() + 30000;
        printtemp = 1;
        Serial.println();
    }

    if (!seen_all) search();

    probe(printtemp); // Sets: good, min, max, avg, current, missing.
    compare(1);       // Prints changes.

    byte new_state = missing ? 1 : 0;
    if (new_state != state) set_state(new_state);

    if (!missing && printtemp) closed_view();

    byte keys = tm.getButtons();
    if (keys == 0x01)
        tm.setDisplayToDecNumber(get_free_memory(), 0);
    else if (keys == 0x02)
        tm.setDisplayToDecNumber(current, 0);
    else if (keys == 0x04)
        tm.setDisplayToDecNumber(seen, 0);
    else if (keys == 0x20)
        tm.setDisplayToDecNumber(known, 0);
    else if (keys == 0x81) {
        byte oldstate = state;
        set_state(-1);
        program();
        set_state(oldstate);
    }
    else if (keys == 0x18 && missing) {
        sensorid store[MAXSENSORS];
        byte nstored = 0;
        for (byte i = 0; i < known; i++) {
            if (i < seen && test_bit(good, i)) {
                store[nstored++] = ids[i];
            } else {
                Serial.print("[Sensor ");
                print_sensor(Serial, ids[i], 1);
                Serial.println(" gewist.]");
            }
        }
        if (nstored < MAXSENSORS) {
            store[nstored].zone = 0;
            store[nstored].nr   = 0;
        }
        EEPROM_writeAnything(256, store);
        seen = 0; // Force re-learning
        search();
        probe(0);
        compare(0);  // Just refill "prevabsent"; don't print anything
        while (tm.getButtons());
        mydelay(500); // debounce
        nextprint = millis();
    }
    else if (!keys && !missing)
        tm.clearDisplay();
    mydelay(20);
}

// vim: ft=c
