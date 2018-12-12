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

// DFU-STM32 device library

class STM32USARTPort {
    // Implements STM32 bootloader access (initialization
    // and commands issuing) via USART.

    _usartPort = null;
    _usartDataRate = null;
    _doubleAckOnWrite = null;

    _send = null;
    _extendedErase = null;

    constructor(usartPort, usartDataRate=null, doubleAckOnWrite=false) {
        // Constructor parameters:
        // -----------------------
        // ⋅ usartPort − Imp device serial port;
        // ⋅ usartDataRate − serial communication baud rate (int),
        //   1200 to 115200;
        // ⋅ extendedErase − MCU's bootloader uses extended Erase
        //   command (true, default) or short Erase commands
        //   (false);
        // ⋅ doubleAckOnWrite − bootloader expects two acknoledge
        //   sequences on write (true) or just one (false, default).

        const USART_SYNC = 0x7f;
        const USART_ACK = 0x79;
        const USART_NO_ACK = 0x1f;

        const USART_CMD_GET = 0x00;
        const USART_CMD_GET_VERSION = 0x01;
        const USART_CMD_ERASE = 0x43;
        const USART_CMD_EXT_ERASE = 0x44;
        const USART_CMD_WRITE = 0x31;

        const USART_DEFAULT_DATA_RATE = 115200;
        const USART_POLL_INTERVAL = 0.01
        // Flash erase operations can take a long time
        const USART_POLL_RETRIES = 3000

        _usartPort = usartPort;
        _doubleAckOnWrite = doubleAckOnWrite;

        if (usartDataRate == null) {
            _usartDataRate = USART_DEFAULT_DATA_RATE;
        } else {
            _usartDataRate = usartDataRate;
        };

        _send = blob(1);
    };

    function connect() {
        // Connects to the MCU's bootloader via serial port.

        _usartPort.configure(_usartDataRate, 8, PARITY_EVEN, 1, NO_CTSRTS);

        local reply = -1;

        _sendByte(USART_SYNC);
        _ack();

        local getResult = __get();
        server.log("Bootloader version: " + getResult[0]);

        // determine supported erase command
        if (getResult[1].find(USART_CMD_EXT_ERASE) != null) {
            _extendedErase = true;
        };
        if (getResult[1].find(USART_CMD_ERASE) != null) {
            _extendedErase = false;
        };
        if (_extendedErase == null) {
            throw "Erase commands are not supported by the bootloader.";
        };
    };

    function erase(sector) {
        // Selects proper method of erasing one sector of the MCU's
        // internal Flash ROM.

        server.log(format("Erasing Flash ROM sector 0x%04x", sector));

        if (_extendedErase) {
            _extErase(sector);
        } else {
            _erase(sector);
        };
    };

    function bulkErase() {
        // Selects proper method of bulk erasing the MCU's internal
        // Flash ROM.

        server.log("Erasing Flash ROM");

        if (_extendedErase) {
            _extBulkErase();
        } else {
            _bulkErase();
        };
    };

    function write(address, data) {
        // Write any volume of data to the MCU's internal memory, starting
        // from given address.

        data.seek(0);

        while (!data.eos()) {

            // limit the size of data being writen to 256 bytes (AN3155)
            local divider = data.len();

            if (divider > 256) {
                divider = 256;
            };

            // write data
            _write256(address, data.readblob(divider));

            // correct address and remaining data
            if (!data.eos()) {
                data = data.readblob(data.len());
                address += divider;
            };
        };
    };

    function disconnect() {
        // Frees USART port.

        _usartPort.disable();
    };

    function _xorChecksum(data) {
        // Calculates xor checksum for a data blob.

        local checksum = 0;

        foreach (_, dataByte in data) {
            checksum = checksum ^ dataByte;
        };
        return checksum;
    };

    function _sendByte(dataByte) {
        // Write byte of data synchronously.

        _send[0] = dataByte;
        _usartPort.write(_send);
    };

    function _sendCommand(command) {
        // Write command byte, followed by XOR checksum.

        local commandBlob = blob(2);

        commandBlob[0] = command;
        commandBlob[1] = command ^ 0xff;
        _usartPort.write(commandBlob);
    };

    function _readByte() {
        // Read data byte with polling.

        local reply;

        for (local i = 0; i < USART_POLL_RETRIES; i += 1) {
            reply = _usartPort.read();
            if (reply != -1) {
                return reply;
            };
            imp.sleep(USART_POLL_INTERVAL);
        };

        throw "Reading from USART timed out!";
    };

    function _ack() {
        // Acknowledge the sent packet.

        local reply = _readByte();

        switch (reply) {
            case USART_ACK:
                return;

            case USART_NO_ACK:
                throw "Not acknowledged!";

            default:
                throw format("Unexpected data: 0x%02x", reply);
        };
    };

    function __get() {
        // Issues Get command. Returns bootloader version and
        // a list of supported commands.

        _sendCommand(USART_CMD_GET);
        _ack();

        // the number of bytes to follow – 1 except current
        // and ACKs (from AN3155)
        local replyLength = _readByte();

        // bootloader version (0 < Version < 255),
        // example: 0x10 = Version 1.0 (from AN3155)
        local version = _readByte().tostring();
        version = version.slice(0, -1) + "." + version.slice(-1);

        // get commands
        local commandList = [];
        for (local i = 0; i < replyLength; i += 1) {
            commandList.append(_readByte());
        };

        _ack();
        return [version, commandList];
    };

    function _erase(sector) {
        // Short erase implementation.
        
        _sendCommand(USART_CMD_ERASE);
        _ack();

        sector = sector & 0xff;

        // erase one sector
        _sendByte(0);

        // send sector number
        _sendByte(sector);

        // send checksum
        _sendByte(sector);
        _ack();
    };

    function _bulkErase() {
        // Short bulk erase implementation.

        _sendCommand(USART_CMD_ERASE);
        _ack();

        _sendByte(0xff);
        _sendByte(0x00);
        _ack();
    };

    function _extErase(sector) {
        // Extended erase implementation.

        _sendCommand(USART_CMD_EXT_ERASE);
        _ack();

        // erase one sector
        _sendByte(0);
        _sendByte(0);

        // send sector number
        local sectorMSB = sector >> 8;
        local sectorLSB = sector & 0xff;

        _sendByte(sectorMSB);
        _sendByte(sectorLSB);

        // send checksum
        _sendByte(sectorMSB ^ sectorLSB);
        _ack();
    };

    function _extBulkErase() {
        // Extended bulk erase implementation.

        _sendCommand(USART_CMD_EXT_ERASE);
        _ack();

        // erase one sector
        _sendByte(0xff);
        _sendByte(0xff);
        _sendByte(0x00);
        _ack();
    };

    function _write256(address, dataBlob) {
        // Writes up to 256 bytes into MCU's memory
        // (straightforward implementation of the bootloader's
        // Write Memory command).

        local dataSize = dataBlob.len();
        if (dataSize <= 0 || dataSize > 256) {
            throw "Can not write so much as " + dataSize + " bytes in one go.";
        };

        _sendCommand(USART_CMD_WRITE);
        _ack();

        // prepare big-endian buffer with address bytes
        local addressBlob = blob(4);
        for (local i = 3; i >= 0; i -= 1) {
            addressBlob[i] = address & 0xff;
            address = address >> 8;
        };
        
        _usartPort.write(addressBlob);
        _sendByte(_xorChecksum(addressBlob));
        _ack();

        _sendByte(dataSize - 1);
        _usartPort.write(dataBlob);
        _sendByte((dataSize - 1) ^ _xorChecksum(dataBlob));
        _ack();

        // Some products may return two NACKs instead of one when Read
        // Protection (RDP) is active (or Read Potection level 1 is active).
        // To know if a given product returns a single NACK or two NACKs
        // in this situation, refer to the known limitations section
        // relative to that product in AN2606.
        if (_doubleAckOnWrite) {
            _ack();
        };
    };
}

class DFUSTM32Device {
    // DFU-STM32 device library
    
    static VERSION = "0.1.0";

    _port = null;
    _flashSectorMap = null;
    _flashErasedSectors = null;
    
    _bootModePin = null;
    _resetPin = null;

    _beforeStart = null;
    _beforeInvoke = null;
    _onReceiveChunk = null;
    _beforeDismiss = null;
    _beforeDone = null;
    
    constructor(
        port,
        flashSectorMap=null,
        bootModePin=null,
        resetPin=null
    ) {
        // Constructor parameters:
        // -----------------------
        // ⋅ port − DFU port object;
        // ⋅ flashSectorMap − (optional) a map of {sector number: sector
        //   descriptor}. Sector descriptor is a two-array of [start
        //   address, end address] of a sector. If not set, device will
        //   perform a bulk erase of MCU's Flash ROM (default). Empty map
        //   means no Flash ROM erase will be done;
        // ⋅ bootModePin − GPIO pin that sets bootloader mode on (high)
        //   or off (low). Samples by the MCU on reset;
        // ⋅ resetPin − GPIO pin that resets MCU when driven low. Must be
        //   open-drained.

        const EVENT_START_FLASHING = "start-flashing";
        const EVENT_REQUEST_CHUNK = "request-chunk";
        const EVENT_RECEIVE_CHUNK = "receive-chunk";
        const EVENT_DONE_FLASHING = "done-flashing";

        // time to hold reset
        const RESET_DELAY = 0.01
        // time for bootloader initialization
        const BOOTLOADER_DELAY = 0.1

        const STATUS_OK = "OK";
        const STATUS_ABORTED = "Aborted";

        _port = port;
        _bootModePin = bootModePin;
        _resetPin = resetPin;
        if (flashSectorMap != null) {
            _flashSectorMap = flashSectorMap;
            _flashErasedSectors = [];
        };

        init();
    };

    function init() {
        agent.on(EVENT_START_FLASHING, onStartFlashing.bindenv(this));
        agent.on(EVENT_RECEIVE_CHUNK, onReceiveChunk.bindenv(this));
    };

    function setBeforeStart(beforeStart) {
        // Set callback for the time just before the process of
        // flashing starts. It can be used to check power source,
        // ask user permission, et c.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Device class instance.
        //
        // Callback should return falsey value to abort flashing,
        // or truey value to continue operation.

        _beforeStart = beforeStart;
    };

    function setBeforeInvoke(beforeInvoke) {
        // Set callback to replace or prepend the standard
        // mechanism of entering the bootloader on the MCU.
        // Fires right after `_beforeStart`. Have its
        // counterpart callback, `_beforeDismiss`.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Device class instance.
        //
        // Callback should return falsey value to skip the
        // standard mechanism and proceed to bootloader
        // connecting, or truey value to enter the bootloader
        // mode by manipulating reset and bootX pins.

        _beforeInvoke = beforeInvoke;
    };

    function setOnReceiveChunk(onReceiveChunk) {
        // Set callback for receiving chunk from agent.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Device class instance;
        // ⋅ chunk (either table with target address and blob
        //   of binary data, or null − end of transfer).
        //
        // Callback should return truey value to proceed or
        // falsey value to abort writing data and proceed to
        // finalize flashing and switch MCU into normal mode.

        _onReceiveChunk = onReceiveChunk;
    };

    function setBeforeDismiss(beforeDismiss) {
        // Set callback to replace or prepend the standard
        // mechanism of leaving the bootloader. Fires before
        // `_beforeDone`.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Device class instance.
        //
        // Callback should return falsey value to skip the
        // standard mechanism, or truey value to proceed
        // switching MCU to the normal mode by manipulating
        // reset and bootX pins.

        _beforeDismiss = beforeDismiss;
    };

    function setBeforeDone(beforeDone) {
        // Set callback for the end of device operation.
        // Use this chance to perform extra cleanup,
        // extend status, et c.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Device class instance;
        // ⋅ default device status: either STATUS_OK or
        //   STATUS_ABORTED.
        //
        // Callback should return device status string.

        _beforeDone = beforeDone;
    };

    function onStartFlashing(_) {
        // EVENT_START_FLASHING handler

        if (_beforeStart == null || _beforeStart(this)) {
            invokeBootloader();
            agent.send(EVENT_REQUEST_CHUNK, null);
        } else {
            agent.send(EVENT_DONE_FLASHING, STATUS_ABORTED);
        };
    };

    function invokeBootloader() {
        // set bootX pins and pull reset
        // or issue some command to MCU
        // for reboot itself into the bootloader mode

        // boot modes:
        // 0 − from the main Flash memory
        // 1 − from the system memory (bootloader)
        _bootModePin.configure(DIGITAL_OUT);

        // must be held high for normal MCU operation
        _resetPin.configure(DIGITAL_OUT_OD, 1);

        if (_beforeInvoke == null || _beforeInvoke(this)) {

            if (_bootModePin == null && _resetPin == null) {
                throw "You must set boot mode and reset GPIO pins " +
                      "to use the default bootloader invocation method."
            };

            server.log("Resetting...");
            _bootModePin.write(1);
            _resetPin.write(0);
            imp.sleep(RESET_DELAY);
            _resetPin.write(1);
            imp.sleep(BOOTLOADER_DELAY);
            _port.connect();
        };
        server.log("Bootloader is on.");

        if (_flashSectorMap == null) {
            _port.bulkErase();
        };
    };

    function onReceiveChunk(chunk) {
        // EVENT_RECEIVE_CHUNK handler

        local status = STATUS_OK;

        if (_onReceiveChunk == null || _onReceiveChunk(this, chunk)) {
            if (chunk != null) {
                writeChunk(chunk);
                agent.send(EVENT_REQUEST_CHUNK, null);
                return;
            };
        } else {
            status = STATUS_ABORTED;
        };

        dismissBootloader();
        
        if (_beforeDone != null) {
            status = _beforeDone(this, status);
        };
        agent.send(EVENT_DONE_FLASHING, status);
    };

    function writeChunk(chunk) {
        // write chunk

        if (_flashSectorMap != null) {
            // see which sectors this chunk resides in
            local chunkSectors = [];

            foreach (sector, descr in _flashSectorMap) {
                if (
                    chunk.start <= descr[1] &&
                    chunk.start + chunk.data.len() > descr[0]
                ) {
                    // chunk crosses the sector boundaries
                    chunkSectors.append(sector);
                };
            };

            if (!chunkSectors.len()) {
                server.log(format(
                    "Trying to write without prior erasing: 0x%08x-0x%08x",
                    chunk.start,
                    chunk.start + chunk.data.len() - 1
                ));
            };

            // see if the sectors are already erased
            foreach (sector in chunkSectors) {
                if (_flashErasedSectors.find(sector) == null) {
                    // sector is not erased, erase it
                    _port.erase(sector);
                    // list sector as erased
                    _flashErasedSectors.append(sector);
                };
            };
        };

        _port.write(chunk.start, chunk.data);
    };

    function dismissBootloader() {
        // Reboots MCU to normal mode.

        _port.disconnect();

        if (_beforeDismiss == null || _beforeDismiss(this)) {
            server.log("Resetting...");
            _bootModePin.write(0);
            _resetPin.write(0);
            imp.sleep(RESET_DELAY);
            _resetPin.write(1);
        };

        server.log("Bootloader is off.");
    };
}
