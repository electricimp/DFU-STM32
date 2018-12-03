// DFU-STM32 device library


class STM32USARTPort {
    // Implements STM32 bootloader access (initialization
    // and commands issuing) via USART.

    _usartPort = null;
    _usartDataRate = null;
    _send = null;
    _extendedErase = null;
    _doubleAckOnWrite = null;

    constructor(
        usartPort,
        usartDataRate=null,
        extendedErase=true,
        doubleAckOnWrite=false
    ) {
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

        const USART_CMD_GET_VERSION = 0x01;
        const USART_CMD_ERASE = 0x43;
        const USART_CMD_EXT_ERASE = 0x44;
        const USART_CMD_WRITE = 0x31;

        const USART_DEFAULT_DATA_RATE = 115200;
        const USART_POLL_INTERVAL = 0.01
        // Flash erase operations can take a long time
        const USART_POLL_RETRIES = 3000

        _usartPort = usartPort;
        _extendedErase = extendedErase;
        _doubleAckOnWrite = doubleAckOnWrite;

        if (usartDataRate == null) {
            _usartDataRate = USART_DEFAULT_DATA_RATE;
        } else {
            _usartDataRate = usartDataRate;
        };

        _send = blob(1);
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

    function connect() {
        // Connects to the MCU's bootloader via serial port.

        _usartPort.configure(_usartDataRate, 8, PARITY_EVEN, 1, NO_CTSRTS);

        local reply = -1;

        _sendByte(USART_SYNC);
        _ack();

        _sendCommand(USART_CMD_GET_VERSION);
        _ack();

        local reply = blob(3);

        foreach (i, _ in reply) {
            reply[i] = _readByte();
        };

        local version = reply[0].tostring();
        version = version.slice(0, -1) + "." + version.slice(-1);
        server.log("Bootloader version: " + version);

        _ack();
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

    function write(address, data) {
        // Write any volume of data blob to the MCU's internal memory,
        // starting from given address.

        server.log(format("START: 0x%08x", address));
        server.log(format("DATA: %i BYTES", data.len()));

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
}

class DFUSTM32Device {
    // DFU-STM32 device library
    
    static VERSION = "0.1.0";

    _port = null;
    _flashSectorMap = null;
    _flashErasedSectors = null;
    bootModePin = null;
    resetPin = null;

    constructor(port, flashSectorMap=null) {
        // Constructor parameters:
        // -----------------------
        // ⋅ port − DFU port object;
        // ⋅ flashSectorMap − (optional) a map of {sector number: sector
        //   descriptor}. Sector descriptor is a two-array of [start
        //   address, end address] of a sector. If not set, device will
        //   perform a bulk erase of MCU's Flash ROM (default). Empty map
        //   means no Flash ROM erase will be done.

        const EVENT_START_FLASHING = "start-flashing";
        const EVENT_REQUEST_CHUNK = "request-chunk";
        const EVENT_RECEIVE_CHUNK = "receive-chunk";
        const EVENT_DONE_FLASHING = "done-flashing";

        _port = port;
        if (flashSectorMap != null) {
            _flashSectorMap = flashSectorMap;
            _flashErasedSectors = [];
        };

        init();
    };

    function init() {
        agent.on(EVENT_START_FLASHING, onStartFlashing.bindenv(this));
        agent.on(EVENT_RECEIVE_CHUNK, onReceiveChunk.bindenv(this));

        // boot modes:
        // 0 − from the main Flash memory
        // 1 − from the system memory (bootloader)
        bootModePin = hardware.pin5;
        bootModePin.configure(DIGITAL_OUT);

        // must be held high for normal MCU operation
        resetPin = hardware.pin7;
        resetPin.configure(DIGITAL_OUT_OD, 1);
    };

    function onStartFlashing(_) {
        // EVENT_START_FLASHING handler

        invokeBootloader();
        agent.send(EVENT_REQUEST_CHUNK, null);
    };

    function invokeBootloader() {
        // set bootX pins and pull reset
        // or issue some command to MCU
        // for reboot itself into the bootloader mode

        server.log("Resetting...");

        bootModePin.write(1);
        resetPin.write(0);
        // hold reset for a while
        imp.sleep(0.1);
        resetPin.write(1);
        // give bootloader time to initialize itself
        imp.sleep(0.1);
        _port.connect();

        server.log("Bootloader is on.");

        if (_flashSectorMap == null) {
            _port.bulkErase();
        };
    };

    function onReceiveChunk(chunk) {
        // EVENT_RECEIVE_CHUNK handler
        
        if (chunk) {
            writeChunk(chunk);
            agent.send(EVENT_REQUEST_CHUNK, null);
        } else {
            dismissBootloader();

            // TODO: "OK" → try to make sure that MCU is up
            // and running in normal mode
            agent.send(EVENT_DONE_FLASHING, "OK");
        };
        
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

        server.log(
            "Chunk " + chunk.start + ":" +
            chunk.data.len() + " is written."
        );
    };

    function dismissBootloader() {
        // reboot MCU in normal mode

        _port.disconnect();

        server.log("Resetting...");

        bootModePin.write(0);
        resetPin.write(0);
        // hold reset for a while
        imp.sleep(0.1);
        resetPin.write(1);

        server.log("Bootloader is off.");
    };
}
