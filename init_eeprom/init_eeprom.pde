#include "EEPROM.h"
#include "AnythingEEPROM.h"

void setup () {
    EEPROM_writeAnything(0,
        /* 0*/ "\0"
        /* 1*/ "Ingang\0"
        /* 2*/ "Arcade\0"
        /* 3*/ "Handwerklokaal\0"
        /* 4*/ "Keuken\0"
        /* 5*/ "Lounge\0"
        /* 6*/ "Hacklab\0"
        /* 7*/ "Studio\0"
        /* 8*/ "Toiletten\0"
        /* 9*/ "Dakterras\0"
        /*10*/ "Doka\0"
        /*11*/ "Lift\0"
        /*12*/ "Liftmachinekamer\0"
        /*13*/ "Serverhok\0"
        /*14*/ "Storage\0"
        /*15*/ "Room 101\0"
        /*16*/ "Stookhok\0"
        /*17*/ "Nooduitgang\0"
        /*18*/ "Dubbele deur\0"
        /*19*/ "\0"
        /*20*/ "\0"
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
    EEPROM_writeAnything(256, "\0\0");
}


void loop () { }
