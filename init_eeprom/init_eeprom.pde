#include "EEPROM.h"
#include "AnythingEEPROM.h"

void setup () {
    EEPROM_writeAnything(0,
        /* 0*/ "\0"
        /* 1*/ "Entree\0"
        /* 2*/ "Klusbunker\0"
        /* 3*/ "Meukhok\0"
        /* 4*/ "Kantoor\0"
        /* 5*/ "Lounge\0"
        /* 6*/ "Hal beneden\0"
        /* 7*/ "Serverhok\0"
        /* 8*/ "Toiletten\0"
        /* 9*/ "Kelder\0"
        /*10*/ "SparksHack\0"
        /*11*/ "foo\0"
        /*12*/ "bar\0"
        /*13*/ "baz\0"
        /*14*/ "quux\0"
        /*15*/ "xyzzy\0"
        /*16*/ "Hellingbaan\0"
        /*17*/ "meh\0"
        /*18*/ "bla\0"
        /*19*/ "Voordeur\0"
        /*20*/ "RevSpace\0"
        /*21*/ "\0"
        /*22*/ "\0"
        /*23*/ "\0"
        /*24*/ "\0"
        /*25*/ "\0"
        /*26*/ "\0"
        /*27*/ "\0"
        /*28*/ "\0"
        /*29*/ "\0"
        /*30*/ "\0"
        /*31*/ "\0"
    );
    EEPROM_writeAnything(256, "\x14\x81\0\0");
}


void loop () { }
