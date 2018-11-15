// Device source code goes here

@include "DFU-STM32/DFU-STM32.device.lib.nut"

local port = STM32SPIPort(hardware.spi189, hardware.pin2);

local dfu_stm32 = DFUSTM32Device(port);
