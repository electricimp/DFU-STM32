# DFU-STM32

## Common information
This library is aimed to facilitate the process of updating the firmware of the certain types of custom peripheral controllers (MCUs), working in tandem with the Imp modules.

There may be various reasons to use external MCUs in Imp-enabled devices. Most probable are:
- the project requires a high number of peripheral connections, that exceeds the capabilities of an Imp module,
- an Imp module is used to retrofit the existing device with cloud connectivity, while original (legacy) MCU remains in place, performing its initial tasks.

At the moment, this library supports:
- any Imp module or development board with at least one UART lane and two GPIO pins available. The library was extensively tested with [April](https://developer.electricimp.com/hardware/resources/reference-designs/april) board,
- STM32L0, STM32L1, STM32L4, STM32F0, STM32F1, STM32F2, STM32F3, STM32F4, STM32F7 series of microcontrollers. Was tested with STM32F412ZGT6 MCU (Nucleo-F412ZG development board),
- STM32 standard (built-in) bootloader,
- USART port in asynchronous mode,
- hardware method of entering/exiting the bootloader,
- firmware in Intel Hex format.

## Quick start

1. Include code in your project:
   Copy and paste the `DFU-STM32.agent.lib.nut` file in you agent code, and the `DFU-STM32.device.lib.nut` file in your device code.
   
2. On device side:
    1. Create a port instance with an Imp [UART device](https://developer.electricimp.com/api/hardware/uart) as an argument:
    ```
    local port = STM32USARTPort(hardware.uart1289);
    ```
    
    2. (Optional.) Create an MCU's internal Flash ROM sector map. You can find the details on the sectors' size, physical addresses and enumeration scheme in your MCU's reference manual. For example, this is the sector map of the STM32F412 series microcontrollers:
    ```
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
    ```
    As you can see, STM32F412 series Flash ROM is divided into 12 sectors, enumerated from 0 to 11. The first four sectors have a size of 16 KBytes, the next sector − 64 KBytes, and the last 7 sectors − 128 KBytes each.

    3. Create the DFU-STM32 device object with the following parameters:
        - port object,
        - Flash ROM map,
        - mode setting pin. Must be connected to the `bootX` pin of the MCU,
        - reset pin. Must be connected to the MCU's `nrst` pin.
      ```
      local dfu_stm32 = DFUSTM32Device(
          port, STM32F412FlashMap, hardware.pin5, hardware.pin7
      );
      ```

      If you skip the sector map or pass `null` instead, the device will perform a bulk Flash ROM erase. Bulk erasing can take a long time.

      You can also skip the last two parameters (pins), if you intend to use software method of entering/exiting the bootloader. See [customization guide](./docs/customization.md) on how to do it.

3. On agent side:
   1. Create a DFU-STM32 object:
   ```
   local dfu_stm32 = DFUSTM32Agent();
   ```
   2. Create an instance of the file parser with the `blob` or blob-like object, containing the firmware file:
   ```
   local parser = IntelHexParser(firmwareBlob);
   ```
   3. Parse image and send it to the device:
   ```
   dfu_stm32.sendImage(parser);
   ```

## Library reference
You can find a layout of DFU-STM32's classes and their mandatory methods in the [reference](./docs/reference.md).

## Example
The agent part of an example is featuring a simple web service. The endpoint URL is *"https://<span></span>agent.electricimp.com/&lt;Agent ID&gt;/firmware/update"*. It supports two verbs:
- `POST` takes a request body as a firmware (byte stream), parses it, and sends it to the device,
- `GET` returns a current agent status (either "Busy" or "Idle").

The agent part also has a simple progress indicator. It reports a current progress to a system log each time the data chunk goes to the device.

The device part of the example is pretty minimal.

## License
This library is licensed under the [MIT License](./LICENSE.txt).
