// Device source code goes here

@include "DFU-STM32/DFU-STM32.device.lib.nut"

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

local port = STM32USARTPort(hardware.uart1289);
local dfu_stm32 = DFUSTM32Device(port, STM32F412FlashMap);
