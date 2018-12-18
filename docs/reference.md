# DFU-STM32 library reference

- Agent side:
    - [file parser class](#file-parser-class):
        - [generateChunks()](#generatechunks),
    - [agent class](#agent-class):
        - [setBeforeSendImage()](#setbeforesendimagecallback),
        - [setBeforeSendChunk()](#setbeforesendchunkcallback),
        - [setOnDone()](#setondonecallback),
        - [sendImage()](#sendimageparser).
- Device side:
    - [port class](#port-class):
        - [connect()](#connect),
        - [erase()](#erasesector),
        - [bulkErase()](#bulkerase),
        - [write()](#writeaddress-data),
        - [disconnect()](#disconnect),
    - [device class](#device-class):
        - [setBeforeStart()](#setbeforestartcallback),
        - [setBeforeInvoke()](#setbeforeinvokecallback),
        - [setOnReceiveChunk()](#setonreceivechunkcallback),
        - [setBeforeDismiss()](#setbeforedismisscallback),
        - [setBeforeDone()](#setbeforedonecallback),
        - [onStartFlashing()](#onstartflashingdata),
        - [invokeBootloader()](#invokebootloader),
        - [onReceiveChunk()](#onreceivechunkchunk),
        - [writeChunk()](#writechunkchunk),
        - [dismissBootloader()](#dismissbootloader).
- [Events](#events).

## File parser class
Translates file of a certain format (Intel Hex, DfuSe, binary, et c.), into chunks with binary data. Each chunk should contain:
- a blob of data with a fixed maximum size,
- an address at which the data will be stored in MCU's memory.

When no data left in file, parser must return `null`.

At the moment, the only parser class implemented is *IntelHexParser*. Intel Hex files specification is available [here](https://web.archive.org/web/20160607224738/http://microsym.com/editor/assets/intelhex.pdf). This format is well supported by GNU compiler suite, ARM Keil, IntelliJ CLion, et c. It is simple, text-oriented, and suitable for many 8-, 16-, or 32-bit microcontrollers.

### Constructor: FileParser(*fileBlob[, chunkSize]*)
| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| fileBlob | blob | yes | `blob` or blob-like object, containing the firmware file. |
| chunkSize | int | no | Maximum chunk size, defaults to 4KB. |

### generateChunks()
A [generator function](https://developer.electricimp.com/squirrel/squirrelcrib#generator-functions) that yields chunks.

## Agent class
Agent class, DFUSTM32Agent, is responsible for sending chunks to the device side, using Imp API messages.

### Constructor: DFUSTM32Agent()
Set up message handlers.

### setBeforeSendImage(*callback*)
Set callback for the moment after all agent side initialization is done, but before sending firmware to device.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameter:
- DFUSTM32Agent class instance.

Callback should return falsey value to abort sending blob to device, or truey value to continue operation.

### setBeforeSendChunk(*callback*)
Set callback for the moment before sending chunk to device.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameters:
- DFUSTM32Agent class instance;
- chunk (either table with target address and blob of binary data, or null − end of transfer).

No return value specified.

### setOnDone(*callback*)
Set callback for the end of the agent-device operation.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameters:
- DFUSTM32Agent class instance;
- client status string. By default it is either "OK" or "Aborted", but the range of statuses can be extended on device's side.

No return value specified.

### sendImage(*parser*)
Set parser instance, then invoke its generator function [generateChunks()](#generatechunks) to split firmware into chunks and send it to the device.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| parser | `object` | yes | Object of the parser class. |

## Port class
Implements an access to MCU's bootloader (initialization and commands issuing) over a hardware-defined communication lane (USART, SPI, CAN, USB, et c.).

At the moment, the only port class implemented is *STM32USARTPort*. It allows to access STM32 factory bootloader over USART in asynchronous mode.

The bootloader commands are explained by the ST Micro in the document [AN3155](http://www.st.com/web/en/resource/technical/document/application_note/CD00264342.pdf). Some details of the initialization of the bootloader in different families and models of STM32 microcontrollers are described in [AN2602](http://www.st.com/st-web-ui/static/active/en/resource/technical/document/application_note/CD00167594.pdf).

The following reference uses `STM32USARTPort` as an example of port class. All the following methods described in this topic must be implemented in any other port class.

### Constructor: STM32USARTPort(*usartPort[, usartDataRate][, doubleAckOnWrite]*)
Constructor parameters:

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| usartPort | `object` | yes | Imp device serial port, instance of [uart](https://developer.electricimp.com/api/hardware/uart) class. |
| usartDataRate | `int` | no | Serial communication baud rate. Values from 1200 to 115200 are supported by Imp. Default is 115200. |
| doubleAckOnWrite | `bool` | no | This parameter is specific to some STM32 devices. Default is `false`. |

### connect()
Connects to the MCU's bootloader via serial port.

### erase(sector)
Selects proper method of erasing one sector of the MCU's internal Flash ROM.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| sector | `int` | yes | An ID of sector to erase. Refer to you specific microcontroller's datasheet for details. |

### bulkErase()
Selects proper method of bulk erasing the MCU's internal Flash ROM.

### write(*address, data*)
Write any volume of data to the MCU's internal memory, starting from given address.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| address | `int` | yes | Starting address. |
| data | `blob` | yes | Bytes of data to be written. |

### disconnect()
Frees USART port.

## Device class
DFU-STM32 device class implements the method of entering and exiting the STM32 built-in bootloader. When the bootloader is made active, the device class is providing the port instance with the data sent by the agent.

### Constructor: DFUSTM32Device(*port[, flashSectorMap][, bootModePin][, resetPin]*)
Constructor parameters:

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| port | `object` | yes | An instance of the device port class. |
| flashSectorMap | `table` | no | A map of MCU's Flash ROM. Have the following form: `{sector number: [first byte address, last byte address]}`. If not set, the bulk erase will be performed, which is slow and not suitable in many cases. If set empty, no erase will be performed. |
| bootModePin | `object` | no | Object of class [pin](https://developer.electricimp.com/api/hardware/pin). Sets to logical `1` to enter the bootloader, resets to `0` to exit back to normal mode. |
| resetPin | `object` | no | Object of class [pin](https://developer.electricimp.com/api/hardware/pin). The hardware GPIO pin behind this object must be connected to MCU's `nrst` signal. |

To implement some other way of entering/exiting the bootloader, you must register the [beforeInvoke](#setbeforeinvokebeforeinvoke) and [beforeDismiss](#setbeforedismissbeforedismiss) callbacks and put your hardware-specific code there. In this case, `bootModePin` and `resetPin` constructor parameters are optional.

### setBeforeStart(*callback*)
Set callback for the time just before the process of flashing starts. It can be used to check power source, ask user permission, et c.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameter:
- DFUSTM32Device class instance.

Callback should return falsey value to abort flashing, or truey value to continue operation.

### setBeforeInvoke(*callback*)
Set callback to replace or prepend the standard mechanism of entering the bootloader on the MCU. Fires right after `_beforeStart`. Have its counterpart callback, `_beforeDismiss`.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameter:
- DFUSTM32Device class instance.

Callback should return falsey value to skip the standard mechanism and proceed to bootloader connecting, or truey value to enter the bootloader mode by manipulating reset and bootX pins.

### setOnReceiveChunk(*callback*)
Set callback for receiving chunk from agent.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameters:
- DFUSTM32Device class instance;
- chunk (either table with target address and blob of binary data, or null − end of transfer).

Callback should return truey value to proceed or falsey value to abort writing data and proceed to finalize flashing and switch MCU into normal mode.

### setBeforeDismiss(*callback*)
Set callback to replace or prepend the standard mechanism of leaving the bootloader. Fires before `_beforeDone`.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | yes | |

Callback parameter:
- DFUSTM32Device class instance.

Callback should return falsey value to skip the standard mechanism, or truey value to proceed to switching MCU to the normal mode by manipulating reset and bootX pins.

### setBeforeDone(*callback*)
Set callback for the end of device operation. Use this chance to perform extra cleanup, extend status, et c.

Callback parameters:
- `DFUSTM32Device` class instance;
- default device status: either `STATUS_OK` or `STATUS_ABORTED`.

This callback should return device status string.

### onStartFlashing(*data*)
EVENT_START_FLASHING handler.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| data | `table` | yes | Not needed. |

### invokeBootloader()
Sets bootX pin(s) and pull reset or issue some command to MCU for reboot itself into the bootloader mode.

### onReceiveChunk(*chunk*)
EVENT_RECEIVE_CHUNK handler.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| chunk | `table` | yes | Data chunk. |

### writeChunk(*chunk*)
Writes the chunk to the MCU's memory.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| chunk | `table` | yes | Data chunk. |

### dismissBootloader()
Reboots MCU to normal mode.

## Events
DFU-STM32 uses Electric Imp's [messaging system](https://developer.electricimp.com/examples/deviceagent) for agent-device communication. The library therefore defines a number of messages.

| Message name | Direction | Payload | Meaning |
| --- | --- | --- | --- |
| `EVENT_START_FLASHING` | agent → device | none | The agent have a new firmware image and want to make sure that the device is ready to flash it. |
| `EVENT_REQUEST_CHUNK` | device → agent | none | The device is waiting for a chunk of firmware data. |
| `EVENT_RECEIVE_CHUNK` | agent → device | `table`: chunk | The agent is sending a chunk to the device. Chunk format is described [here](#setbeforesendchunkcallback). |
| `EVENT_DONE_FLASHING` | device → agent | `string`: status | Either the device is finished the process of flashing the firmware and returned back to normal mode, or the process was aborted, depending on `status`. The standard statuses are described [here](#setbeforedonecallback). |

DFU-STM32's working process can be described by the following diagram.

![diagram](https://raw.githubusercontent.com/nobitlost/DFU-STM32/develop/docs/diagram1.png)
