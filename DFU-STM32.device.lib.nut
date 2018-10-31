const EVENT_START_FLASHING = "start-flashing";
const EVENT_REQUEST_CHUNK = "request-chunk";
const EVENT_RECEIVE_CHUNK = "receive-chunk";
const EVENT_DONE_FLASHING = "done-flashing";

class DFUSTM32Device {
    // 
    
    static VERSION = "0.1.0";

    constructor() {
        init();
    };

    function init() {
        agent.on(EVENT_START_FLASHING, onStartFlashing.bindenv(this));
    };

    function onDisabledEvent(_) {
        // handler for disabled events
        server.log("This event is disabled.");
    };

    function onStartFlashing(_) {
        // EVENT_START_FLASHING handler

        invokeBootloader();

        agent.on(EVENT_RECEIVE_CHUNK, onReceiveChunk.bindenv(this));
        agent.on(EVENT_START_FLASHING, onDisabledEvent);

        agent.send(EVENT_REQUEST_CHUNK, null);
    };

    function invokeBootloader() {
        // set bootX pins and pull reset
        // or issue some command to MCU
        // for reboot itself into the bootloader mode

        server.log("Bootloader is on.");
    };

    function onReceiveChunk(chunk) {
        // EVENT_RECEIVE_CHUNK handler
        
        if (chunk) {
            writeChunk(chunk);
            agent.send(EVENT_REQUEST_CHUNK, null);
        } else {
            agent.on(EVENT_RECEIVE_CHUNK, onDisabledEvent);
            dismissBootloader();
            agent.on(EVENT_START_FLASHING, onStartFlashing.bindenv(this));

            // TODO: "OK" → try to make sure that MCU is up
            // and running in normal mode
            agent.send(EVENT_DONE_FLASHING, "OK");
        };
        
    };

    function writeChunk(chunk) {
        // write chunk
        server.log("Chunk " + chunk.start + ":" + chunk.length + " is written.");
    };

    function dismissBootloader() {
        // reboot MCU in normal mode
        server.log("Bootloader is off.");
    };

}
