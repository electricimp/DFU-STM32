// DFU-STM32 agent library

class IntelHexParser {

    static RECORD_TYPE_DATA = "00";     // Data Record
    static RECORD_TYPE_EOF = "01";      // End of File Record
    static RECORD_TYPE_ULBA = "04";     // Extended Linear Address Record
    static RECORD_TYPE_START = "05";    // Start Linear Address Record

    parseErrorMsg = "Intel Hex Parse Error: ";
    _chunkSize = null;
    _fileBlob = null;
    spacingChars = null;

    constructor(fileBlob, chunkSize=4096) {
        _chunkSize = chunkSize;
        _fileBlob = fileBlob;
        spacingChars = " \t\r\n";
    };

    function hexToInt(str) {
        // Parses a hex string and turns it into an integer.

        local hex = 0x0000;

        foreach (ch in str) {
            local nibble;
            if (ch >= '0' && ch <= '9') {
                nibble = (ch - '0');
            } else {
                nibble = (ch - 'A' + 10);
            }
            hex = (hex << 4) + nibble;
        }
        return hex;
    };

    function parseRecord() {
        // Parse Intel Hex record and return its type and contents. Move the
        // blob's pointer to the next record.

        // eat cr/lfs
        local recordMark = null;
        do {
            recordMark = _fileBlob.readstring(1);
        } while (spacingChars.find(recordMark));

        if (recordMark != ":") {
            throw parseErrorMsg + "Record mark is invalid: " + recordMark;
        };

        local recordLength = hexToInt(_fileBlob.readstring(2));
        local loadOffset = hexToInt(_fileBlob.readstring(4));
        local recordType = _fileBlob.readstring(2);

        // save data position in blob and skip data by now
        local dataPointer = _fileBlob.tell();
        _fileBlob.seek(recordLength * 2, 'c');

        local checkSum = hexToInt(_fileBlob.readstring(2));
        local result = {
            "type": recordType,
            "offset": loadOffset,
            "data": null
        };

        switch (recordType) {
            case RECORD_TYPE_ULBA:
                // extended linear address record (ULBA)
                local tempPointer = _fileBlob.tell();
                _fileBlob.seek(dataPointer);
                result.data = hexToInt(_fileBlob.readstring(recordLength * 2));
                _fileBlob.seek(tempPointer);
                break;

            case RECORD_TYPE_DATA:
                // data record
                local tempPointer = _fileBlob.tell();
                _fileBlob.seek(dataPointer);
                result.data = [];
                for (local i = 0; i < recordLength; i += 1) {
                    result.data.append(hexToInt(_fileBlob.readstring(2)));
                };
                _fileBlob.seek(tempPointer);
                break;
        };

        return result;
    };

    function generateChunks() {
        // Gathers records into chunks (or splits records between chunks
        // if needed). Returns chunk or null.

        local ulba = 0;
        local data = [];
        local chunkOffset = null;

        while (true) {
            local record = parseRecord();

            switch (record.type) {
                case RECORD_TYPE_ULBA:
                    // ULBA should precede data
                    server.log("Firmware start address is " + record.data);
                    ulba = record.data << 16;
                    break;

                case RECORD_TYPE_DATA:
                    // initialize first chunk's offset
                    if (chunkOffset == null) {
                        chunkOffset = record.offset;
                    };

                    if (chunkOffset + data.len() != record.offset) {
                        // data is not contiguous − flush!
                        if (data.len() > 0) {
                            local chunk = {
                                "start": ulba + chunkOffset,
                                "data": data
                            };
                            data = record.data;
                            chunkOffset = record.offset;
                            yield chunk;
                        };

                    } else {
                        if (data.len() >= _chunkSize) {
                            // chunk data is ready

                            // flush up to _chunkSize bytes of data, save
                            // the rest
                            local divider = data.len();
                            if (divider > _chunkSize) {
                                divider = _chunkSize;
                            };

                            local chunk = {
                                "start": ulba + chunkOffset,
                                "data": data.slice(0, divider)
                            };
                            data = data.slice(divider);
                            data.extend(record.data);
                            // correct chunk offset for the saved data
                            chunkOffset = (
                                record.offset - data.len() + record.data.len()
                            );
                            yield chunk;
                        } else {
                            data.extend(record.data);
                        };
                    };
                    break;

                case RECORD_TYPE_EOF:
                    // flush data
                    if (data.len() > 0) {
                        local chunk = {
                            "start": ulba + chunkOffset,
                            "data": data
                        };
                        data = record.data;
                        chunkOffset = record.offset;
                        yield chunk;
                    };
                    // stop
                    return;

                default:
                    server.log("Skipping record type " + record.type);
                    break;
            };
        };
    };
};


class DFUSTM32Agent {
    // Firmware updater agent is responsible for:
    // ⋅ parsing .hex or .dfu files and creating firmware blobs,
    // ⋅ keeping account on available firmware versions,
    // ⋅ spliting blobs on chunks,
    // ⋅ sending chunks to device.

    static VERSION = "0.1.0";

    static EVENT_START_FLASHING = "start-flashing";
    static EVENT_REQUEST_CHUNK = "request-chunk";
    static EVENT_RECEIVE_CHUNK = "receive-chunk";
    static EVENT_DONE_FLASHING = "done-flashing";

    _blobParser = null;
    _chunks = null;
    _maxBlobSize = null;

    constructor(maxBlobSize=32768) {
        // initialize agent

        _maxBlobSize = maxBlobSize;

        init();
    };

    function init() {
        device.on(EVENT_REQUEST_CHUNK, onRequestChunk.bindenv(this));
        device.on(EVENT_DONE_FLASHING, onDoneFlashing.bindenv(this));
    };

    function validateBlob(blob) {
        // check memory ranges or target MCU type/PnP ID,
        // maybe include custom callback

        // ...
    };

    function sendBlob(blob) {
        // invoke generator to split firmware into chunks and
        // send it to device

        _blobParser = IntelHexParser(blob, 1024);
        _chunks = _blobParser.generateChunks();
        device.send(EVENT_START_FLASHING, null);
    };

    function onRequestChunk (_) {
        // EVENT_REQUEST_CHUNK handler

        device.send(EVENT_RECEIVE_CHUNK, resume _chunks);
    };

    function onDoneFlashing (status) {
        // EVENT_DONE_FLASHING handler

        server.log("Flashing is done. Status: " + status);
    };

}
