// MIT License
//
// Copyright 2015-2018 Electric Imp
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Basic example of setting up DFUSTM32Device for the STM32F412 series
// microcontroller. Can be set up with Nucleo-F412ZG development board.

@include "DFU-STM32/DFU-STM32.device.lib.nut"

// create Flash ROM sector map

// from STM32F412 reference manual (RM0402),
// section 3.3 “Embedded Flash memory”
local STM32F412FlashMap = {};
STM32F412FlashMap[0] <- [0x08000000, 0x08003fff];
STM32F412FlashMap[1] <- [0x08004000, 0x08007fff];
STM32F412FlashMap[2] <- [0x08008000, 0x0800bfff];
STM32F412FlashMap[3] <- [0x0800c000, 0x0800ffff];
STM32F412FlashMap[4] <- [0x08010000, 0x0801ffff];
STM32F412FlashMap[5] <- [0x08020000, 0x0803ffff];
STM32F412FlashMap[6] <- [0x08040000, 0x0805ffff];
STM32F412FlashMap[7] <- [0x08060000, 0x0807ffff];
STM32F412FlashMap[8] <- [0x08080000, 0x0809ffff];
STM32F412FlashMap[9] <- [0x080a0000, 0x080bffff];
STM32F412FlashMap[10] <- [0x080c0000, 0x080dffff];
STM32F412FlashMap[11] <- [0x080e0000, 0x080fffff];

// create port object with Imp hardware port as a parameter
local port = STM32USARTPort(hardware.uart1289);

// create device object and set its port object, Flash map,
// mode setting pin, and reset pin
local dfu_stm32 = DFUSTM32Device(
    port, STM32F412FlashMap, hardware.pin5, hardware.pin7
);
