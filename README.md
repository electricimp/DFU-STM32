# DFU-STM32
This library is aimed to facilitate the process of updating the firmware of the certain types of custom peripheral controllers (MCUs), working in tandem with the Imp modules.

There may be various reasons to use external MCUs in Imp-enabled devices. Most probable are:
- the project requires a high number of peripheral connections, that exceeds the capabilities of an Imp module,
- an Imp module is used to retrofit the existing device with cloud connectivity, while original (legacy) MCU remains in place, performing its initial tasks.

The library has a modular structure that allows you to adapt it to a wide range of MCUs. Here is a layout of DFU-STM32's classes and their mandatory methods.

- Agent side:
    - [file parser class](#file-parser-class):
        - [generateChunks()](#generatechunks),
    - [agent class](#agent-class):
        - [setBeforeSendImage()](#setbeforesendimagecallback),
        - [setBeforeSendChunk()](#setbeforesendchunkcallback),
        - [setOnDone()](#setondonecallback),
        - [sendImage()](#sendimageparser),
- Device side:
    - port class:
        - connect(),
        - erase(),
        - bulkErase(),
        - write(),
        - disconnect(),
    - device class:
        - setBeforeStart(),
        - setBeforeInvoke(),
        - setOnReceiveChunk(),
        - setBeforeDismiss(),
        - setBeforeDone(),
        - onStartFlashing(),
        - invokeBootloader(),
        - onReceiveChunk(),
        - writeChunk(),
        - dismissBootloader().

## File parser class
Translates file of a certain format (Intel Hex, DfuSe, binary, et c.), into chunks with binary data. Each chunk should contain:
- a blob of data with a fixed maximum size,
- an address at which the data will be stored in MCU's memory.

When no data left in file, parser must return `null`.

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
| callback | `function` | no | |

Callback parameter:
- DFUSTM32Agent class instance.

Callback should return falsey value to abort sending blob to device, or truey value to continue operation.

### setBeforeSendChunk(*callback*)
Set callback for the moment before sending chunk to device.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | no | |

Callback parameters:
- DFUSTM32Agent class instance;
- chunk (either table with target address and blob of binary data, or null − end of transfer).

No return value specified.

### setOnDone(*callback*)
Set callback for the end of the agent-device operation.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| callback | `function` | no | |

Callback parameters:
- DFUSTM32Agent class instance;
- client status string. By default it is either "OK" or "Aborted", but the range of statuses can be extended on device's side.

No return value specified.

### sendImage(*parser*)
Set parser instance, then invoke its generator function [generateChunks()](#generatechunks) to split firmware into chunks and send it to the device.

| Parameter | Data&nbsp;Type | Required? | Description |
| --- | --- | --- | --- |
| parser | `object` | yes | Object of the parser class. |
