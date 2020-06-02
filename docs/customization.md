# DFU-STM32 customization guide
The library has a modular structure that allows you to adapt it to a wide range of firmware file formats, microcontrollers, and communication ports and protocols.

## Callbacks
Main DFU-STM32 classes have a set of callbacks designed to simplify the extension of library functionality. These callbacks are:

- On agent:
    - [beforeSendImage](./reference.md#setbeforesendimagecallback),
    - [beforeSendChunk](./reference.md#setbeforesendchunkcallback),
    - [onDone](./reference.md#setondonecallback),
- on device:
    - [beforeStart](./reference.md#setbeforestartcallback),
    - [beforeInvoke](./reference.md#setbeforeinvokecallback),
    - [onReceiveChunk](./reference.md#setonreceivechunkcallback),
    - [beforeDismiss](./reference.md#setbeforedismisscallback),
    - [beforeDone](./reference.md#setbeforedonecallback).

The [example](../README.md#example) shows how to use agent callbacks to make a progress indicator.

Other legitimate use cases of callbacks might be:
- additional firmware validation,
- chunk enumeration to prevent accidental data loss,
- verification of already written image,
- custom (e. g. [software](https://stm32f4-discovery.net/2017/04/tutorial-jump-system-memory-software-stm32/)) method of entering/exiting the bootloader mode,
- et c.

## Another firmware file format
To implement a new firmware file format, you must create a class with the following methods:
- constructor, that accepts at least two parameters:
  - a blob that contains firmware,
  - a chunk size in bytes (`int`), which optimally should have a reasonable default value, i.e. 4096.

  If the firmware file has not enough info on how to flash it, you must provide additional constructor arguments. For example, when parsing a contigious binary file, provide a starting address,
- `generateChunks()` − generator function, that yields chunks. Chunk format is described in the [reference](./reference.md#setbeforesendchunkcallback).

Firmware file format class must be able to restart chunk generation in a thread-safe manner. In other words, `generateCunks()` must always provide the same consistent result, no matter when or how many times it is called.

## Another device port
All the mandatory methods, that the DFU-STM32 device port class must implement, are described in [its reference](./reference.md#port-class).
