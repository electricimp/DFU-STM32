// DFU-STM32 agent library

const EVENT_START_FLASHING = "start-flashing";
const EVENT_REQUEST_CHUNK = "request-chunk";
const EVENT_RECEIVE_CHUNK = "receive-chunk";
const EVENT_DONE_FLASHING = "done-flashing";

function getFileSize(uri) {
    // returns size of the remote file
    // TODO: error processing
    local resp = http.get(uri, {"Range": "bytes=0-0"}).sendsync();
    return split(resp.headers["content-range"], "/")[1].tointeger();
}

class FirmwareBlob {
    // Emulates read-only blob interface on remote file.
    // TODO: buffering

    firmwareUri = null;
    pointer = null;

    constructor (uri) {
        firmwareUri = uri;
        pointer = 0;
    };

    function len() {
        // get firmware size
        return getFileSize(firmwareUri);
    };

    function eos() {
        // check if end of file is reached
        maxPointer = len() - 1;
        return pointer >= maxPointer;
    };

    function tell() {
        // return current position
        return pointer;
    };

    function seek(offset, offsetBase) {
        // set current position
        // TODO: check bounds
        switch (offsetBase) {
            case 'e':
                pointer = len() - position;
                break;
            case 'c':
                pointer += position;
                break;
            case 'b':
                pointer = position;
                break;
            default:
                // raise error
        }
    };

    // TODO: implement the rest or the blob API
    // (read-only)

    // ...

}


class BlobIterator {
    // An abstract class for parsing firmware files
    // and splitting them onto device-manageable chunks.
    //
    // One chunk − one set of bootloader commands for clearing
    // and writing a continuous FlashROM area.
    //
    // Real file parsers should implement/inherit this.

    blob = null;

    constructor (blob) {
        // validate file format and initialize generator
        throw "This is an abstract firmware blob iterator!";
    };

    function nextChunk() {
        // incapsulate generator logic for yielding chunks

    };
}


class DFUSTM32Agent {
    // Firmware updater agent is responsible for:
    // ⋅ parsing .hex or .dfu files and creating firmware blobs,
    // ⋅ keeping account on available firmware versions,
    // ⋅ spliting blobs on chunks,
    // ⋅ sending chunks to device.

    static VERSION = "0.1.0";

    chunks = null;
    maxFirmwareBlobSize = null;
    chunkSize = null;

    constructor(maxBlobSize=32768) {
        // initialize agent

        maxFirmwareBlobSize = maxBlobSize;

    };

    function chunkGenerator(blob) {
        server.log("Blob received by chunk generator.");

        yield {"start": 100, "length": 100};
        yield {"start": 200, "length": 100};
        yield {"start": 300, "length": 42};
        return null;
    };

    function createBlob(uri) {
        // takes firmware file from given URI and returns
        // blob or blob-like object

        local fileSize = getFileSize(uri);

        if (fileSize > maxFirmwareBlobSize) {
            // create a blob-like object
            result = FirmwareBlob(maxFirmwareBlobSize, uri);
        } else {
            // create a blob object
            resp = http.get(uri).sendsync();
            result = blob(fileSize);
            result.writestring(resp.body);
        };
        return result;
    };

    function validateBlob(blob) {
        // check memory ranges or target MCU type/PnP ID,
        // maybe include custom callback

        // ...
    };

    function sendBlob(blob) {
        // invoke generator to split firmware into chunks and
        // send it to device

        chunks = chunkGenerator(blob);

        device.on(EVENT_REQUEST_CHUNK, onRequestChunk.bindenv(this));
        device.on(EVENT_DONE_FLASHING, onDoneFlashing.bindenv(this));

        device.send(EVENT_START_FLASHING, null);

    };

    function onRequestChunk (_) {
        // EVENT_REQUEST_CHUNK handler

        device.send(EVENT_RECEIVE_CHUNK, resume chunks);
    };

    function onDoneFlashing (status) {
        // EVENT_DONE_FLASHING handler
        server.log("Flashing is done. Status: " + status);

    };

}
