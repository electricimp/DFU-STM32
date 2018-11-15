const EVENT_START_FLASHING = "start-flashing";
const EVENT_REQUEST_CHUNK = "request-chunk";
const EVENT_RECEIVE_CHUNK = "receive-chunk";
const EVENT_DONE_FLASHING = "done-flashing";

class STM32SPIPort {
    // Implements STM32 bootloader access (initialization
    // and commands issuing) via SPI.

    static spiSync = 0x5a;       // 90
    static spiPreSync = 0xa5;    // 165
    static spiDummy = 0x00;      // 0
    static spiAck = 0x79;        // 121
    static spiNoAck = 0x1f;      // 31

    static spiCmdGetVersion = 0x01;

    static spiWaitForAck = 10000;
    static spiDefaultDataRate = 117.1875;

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

        _spiPort = spiPort;
        _spiSelectPin = spiSelectPin;
        if (spiDataRate == null) {
                _spiDataRate = spiDefaultDataRate;
            } else {
                _spiDataRate = spiDataRate;
            };
        _send = blob(1);
    };

    function _writeReadByte(data=null) {
        // Reads and writes unsigned integer data simultaneously
        // from/to SPI port.

        if (data == null) {
            data = spiDummy;
        };
        _send[0] = data;
        local recv = _spiPort.writeread(_send);
        return recv[0];
    };

    function _ack() {
        // Waits for reaction on synchronization procedure
        // or command according to AN4286.

        local recv = null;

        for (local i=spiWaitForAck; i-= 1; i > 0) {
            recv = _writeReadByte();
            if (recv == spiAck) {
                return;
            };
            if (recv == spiNoAck) {
                throw "Connection is not acknowledged!";
            };
        };

        throw "Connection is timed out!";
    };

    function _sendCommand(cmd) {
        // Sends bootloader command.

        local cmdFrame = blob(3);

        cmdFrame[0] = spiSync;
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
        if (_writeReadByte(spiSync) != spiPreSync) {
            throw "Can not sync with bootloader!";
        };

        _ack();
        _writeReadByte(spiAck);

        // read bootloader version
        _sendCommand(spiCmdGetVersion);
        _ack();
        local version = _writeReadByte().tostring();
        version = version.slice(0, -1) + "." + version.slice(-1);
        server.log("Bootloader version: " + version);
        _ack();
    };

    function disconnect() {
        // Deselects SPI port.

        if (_spiSelectPin != null) {
            _spiSelectPin.write(0);
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
