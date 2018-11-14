const EVENT_START_FLASHING = "start-flashing";
const EVENT_REQUEST_CHUNK = "request-chunk";
const EVENT_RECEIVE_CHUNK = "receive-chunk";
const EVENT_DONE_FLASHING = "done-flashing";

class DFUSTM32Device {
    // 
    
    static VERSION = "0.1.0";

    spiSelectPin = null;
    bootModePin = null;
    resetPin = null;

    constructor() {
        init();
    };

    function init() {
        agent.on(EVENT_START_FLASHING, onStartFlashing.bindenv(this));
        agent.on(EVENT_RECEIVE_CHUNK, onReceiveChunk.bindenv(this));

        // SPI is selected when this pin is low
        spiSelectPin = hardware.pin2;
        spiSelectPin.configure(DIGITAL_OUT, 0);

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

        //     Pinout
        // =================
        // 1 − SCLK (SPI189)
        // 2 − SCS (GPIO)
        // 5 − BOOT0 (GPIO)
        // 7 − RESET (GPIO)
        // 8 − MOSI (SPI189)
        // 9 − MISO (SPI189)

        server.log("Resetting...");

        bootModePin.write(1);
        resetPin.write(0);
        imp.sleep(1);

        resetPin.write(1);

        imp.sleep(1);

        hardware.spi189.configure(MSB_FIRST | CLOCK_IDLE_LOW, 117.1875);

        const spiSync = 0x5a;   // 90 01011010
        const spiDummy = 0x00;
        const spiAck = 0x79;    // 121 01111001
        const spiNoAck = 0x1f;  // 31 00011111

        local recv = null;
        local send = blob(1);

        send[0] = spiSync;
        recv = hardware.spi189.writeread(send);
        server.log("RECIEVED " + recv[0]);  // must be 0xa5

        for (local guard = 100; guard -= 1; guard > 0) {
            recv = hardware.spi189.readblob(1);
            if (recv[0] == spiAck) {
                // never happens
                server.log("Sync acknowledged: " + guard);
                break;
            };
            if (recv[0] == spiNoAck) {
                // never happens
                server.log("Sync not acknowledged: " + guard);
                break;
            };
            server.log("RECIEVED " + recv[0]);
        };

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

        server.log("Bootloader is off.");
    };

}
