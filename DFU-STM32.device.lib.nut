// DFU-STM32 device library

class STM32SPIPort {
    // Implements STM32 bootloader access (initialization
    // and commands issuing) via SPI.

    _spiPort = null;
    _spiDataRate = null;
    _spiSelectPin = null;
    _send = null;

    constructor(spiPort, spiSelectPin=null, spiDataRate=null) {
        // Constructor parameters:
        // -----------------------
        // ⋅ spiPort − device SPI port;
        // ⋅ spiDataRate − SPI data rate in kHz (float);
        // ⋅ spiSelectPin − GPIO pin used to select remote (slave) port
        //   (can be null if MCU's slave select pin is hardwired).

        // bootloader protocol-related constants
        const SPI_SYNC = 0x5a;
        const SPI_PRESYNC = 0xa5;
        const SPI_DUMMY = 0x00;
        const SPI_ACK = 0x79;
        const SPI_NO_ACK = 0x1f;

        // SPI configuration
        const SPI_WAIT_FOR_ACK = 10000;
        const SPI_DEFAULT_DATA_RATE = 117.1875;

        // bootloader commands
        const SPI_CMD_GET_VERSION = 0x01;
        const SPI_CMD_UNPROTECT = 0x73;
        const SPI_CMD_ERASE = 0x43;
        const SPI_CMD_EXT_ERASE = 0x44;
        const SPI_CMD_WRITE = 0x31;

        _spiPort = spiPort;
        _spiSelectPin = spiSelectPin;
        if (spiDataRate == null) {
                _spiDataRate = SPI_DEFAULT_DATA_RATE;
            } else {
                _spiDataRate = spiDataRate;
            };
        // temporary structure for the data byte being send
        _send = blob(1);
    };

    function _writeReadByte(data=null) {
        // Reads and writes unsigned integer data simultaneously
        // from/to SPI port.

        if (data == null) {
            data = SPI_DUMMY;
        };
        _send[0] = data;
        local recv = _spiPort.writeread(_send);
        return recv[0];
    };

    function _ack() {
        // Waits for reaction on synchronization procedure
        // or command according to AN4286.

        local recv = null;

        for (local i=SPI_WAIT_FOR_ACK; i-= 1; i > 0) {
            recv = _writeReadByte();
            if (recv == SPI_ACK) {
                return;
            };
            if (recv == SPI_NO_ACK) {
                throw "Connection is not acknowledged!";
            };
        };

        throw "Connection is timed out!";
    };

    function _sendCommand(cmd) {
        // Sends bootloader command.

        local cmdFrame = blob(3);

        cmdFrame[0] = SPI_SYNC;
        cmdFrame[1] = cmd;
        cmdFrame[2] = cmd ^ 0xff;

        _spiPort.write(cmdFrame);
    };

    function _xorChecksum(data) {
        // Calculates xor checksum for a data blob.

        local checksum = 0;

        foreach (_, dataByte in data) {
            checksum = checksum ^ dataByte;
        };
        return checksum;
    };

    function connect() {
        // Configures SPI port and makes sure the bootloader is up
        // and accepting commands.

        if (_spiSelectPin != null) {
            // SPI is selected when this pin is low
            _spiSelectPin.configure(DIGITAL_OUT, 0);
        };

        // flags are set according to AN2606
        _spiPort.configure(MSB_FIRST | CLOCK_IDLE_LOW, _spiDataRate);

        // synchronization according to AN4286
        if (_writeReadByte(SPI_SYNC) != SPI_PRESYNC) {
            throw "Can not sync with bootloader!";
        };

        _ack();
        _writeReadByte(SPI_ACK);

        // read bootloader version
        _sendCommand(SPI_CMD_GET_VERSION);
        _ack();
        local version = _writeReadByte().tostring();
        version = version.slice(0, -1) + "." + version.slice(-1);
        server.log("Bootloader version: " + version);
        _ack();
    };

    function unprotect() {
        //

        server.log("Disabling Flash memory write protection");

        _sendCommand(SPI_CMD_UNPROTECT);
        _ack();
        _ack();
    };

    function erase(sector) {
        //

        server.log("Erasing sector " + sector);

        _sendCommand(SPI_CMD_ERASE);
        _ack();

        local sectorFrame = blob(3);
        
        sectorFrame[0] = 0;
        sectorFrame[1] = sector & 0xff;
        sectorFrame[2] = sectorFrame[0] ^ sectorFrame[1];
        _spiPort.write(sectorFrame);
        _ack();

    };

    function extErase(sector) {
        // Erases a single sector (or block, or page)
        // of the MCU's internal Flash ROM. Since our protocol
        // is of streaming nature, we can hardly make use
        // of multi-sector erasing or mass erasing.

        server.log("Erasing sector " + sector);

        _sendCommand(SPI_CMD_EXT_ERASE);
        _ack();

        local sectorFrame = blob(3);

        // erase N+1 sector, where N=0
        sectorFrame[0] = 0;
        sectorFrame[1] = 1;
        sectorFrame[2] = 1;
        sectorFrame.seek(0);
        _spiPort.write(sectorFrame);
        _ack();

        // sector to erase, MSB first
        sectorFrame[0] = sector >> 8;
        sectorFrame[1] = sector && 0xff;
        sectorFrame[2] = sectorFrame[0] ^ sectorFrame[1];
        sectorFrame.seek(0);
        _spiPort.write(sectorFrame);
        _ack();
    };

    function write(address, data) {
        // Writes the data (array of bytes) into MCU's memory,
        // starting with address given.

    };

    function disconnect() {
        // Deselects SPI port.

        if (_spiSelectPin != null) {
            _spiSelectPin.write(1);
        };
    };

}

class STM32USARTPort {
    // Implements STM32 bootloader access (initialization
    // and commands issuing) via SPI.

    constructor() {
        throw "USART is not yet implemented!"
    };
}

class DFUSTM32Device {
    // DFU-STM32 device library
    
    static VERSION = "0.1.0";

    _port = null;
    bootModePin = null;
    resetPin = null;

    constructor(port) {
        // Constructor parameters:
        // -----------------------
        // ⋅ port − DFU port object.

        const EVENT_START_FLASHING = "start-flashing";
        const EVENT_REQUEST_CHUNK = "request-chunk";
        const EVENT_RECEIVE_CHUNK = "receive-chunk";
        const EVENT_DONE_FLASHING = "done-flashing";

        _port = port;

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
        imp.sleep(1);

        resetPin.write(1);

        imp.sleep(1);

        _port.connect();

        server.log("Bootloader is on.");

        imp.sleep(1);

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

        server.log(
            "Chunk " + chunk.start + ":" +
            chunk.data.len() + " is written."
        );
    };

    function dismissBootloader() {
        // reboot MCU in normal mode

        bootModePin.write(0);
        resetPin.write(0);
        imp.sleep(1);
        resetPin.write(1);

        _port.disconnect();

        server.log("Bootloader is off.");
    };

}
