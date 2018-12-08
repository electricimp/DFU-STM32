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

// DFU-STM32 agent library

class IntelHexParser {
    // Splits blob-like object, containing a file
    // of Intel Hex format, into chunks.

    _chunkSize = null;
    _fileBlob = null;

    constructor(fileBlob, chunkSize=4096) {
        // Constructor parameters:
        // -----------------------
        // ⋅ fileBlob − blob or blob-like object with a firmware file,
        // ⋅ chunkSize − (optional) size of a resulting chunk (bytes).
        //   Defaults to DEFAULT_CHUNK_SIZE.

        const PARSE_ERROR_MSG = "Intel Hex Parse Error: ";

        // Intel Hex file format-related constants:

        // - record types, that can be used in storing ARM MCU firmware
        const RECORD_TYPE_DATA = "00";     // Data Record
        const RECORD_TYPE_EOF = "01";      // End of File Record
        const RECORD_TYPE_ULBA = "04";     // Extended Linear Address Record
        const RECORD_TYPE_START = "05";    // Start Linear Address Record

        // - record delimiters
        const SPACING_CHARS = " \t\r\n";

        const DEFAULT_CHUNK_SIZE = 4096;

        if (chunkSize == null) {
            _chunkSize = DEFAULT_CHUNK_SIZE;
        } else {
            _chunkSize = chunkSize;
        };
        _fileBlob = fileBlob;
    };

    function _hexToInt(str) {
        // Converts a string of hexadecimal digits to an integer.

        local hex = 0;

        foreach (ch in str) {
            local nibble;

            if (ch >= '0' && ch <= '9') {
                nibble = (ch - '0');
            } else if (ch >= 'A' && ch <= 'F') {
                nibble = (ch - 'A' + 10);
            } else if (ch >= 'a' && ch <= 'f') {
                nibble = (ch - 'a' + 10);
            } else {
                throw PARSE_ERROR_MSG + "hex digit is out of range";
            };
            hex = (hex << 4) + nibble;
        }
        return hex;
    };

    function _parseRecord() {
        // Parse Intel Hex record and return its type and contents. Move the
        // blob's pointer to the next record.

        // eat cr/lfs
        local recordMark = null;
        do {
            recordMark = _fileBlob.readstring(1);
        } while (SPACING_CHARS.find(recordMark));

        if (recordMark != ":") {
            throw PARSE_ERROR_MSG + "record mark is invalid: " + recordMark;
        };

        local recordLength = _hexToInt(_fileBlob.readstring(2));
        local loadOffset = _hexToInt(_fileBlob.readstring(4));
        local recordType = _fileBlob.readstring(2);

        // save data position in blob and skip data by now
        local dataPointer = _fileBlob.tell();
        _fileBlob.seek(recordLength * 2, 'c');

        local checkSum = _hexToInt(_fileBlob.readstring(2));
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
                result.data = _hexToInt(_fileBlob.readstring(recordLength * 2));
                _fileBlob.seek(tempPointer);
                break;

            case RECORD_TYPE_DATA:
                // data record
                local tempPointer = _fileBlob.tell();
                _fileBlob.seek(dataPointer);
                result.data = blob(recordLength);
                for (local i = 0; i < recordLength; i += 1) {
                    result.data[i] = _hexToInt(_fileBlob.readstring(2));
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
        local data = blob();
        local chunkOffset = null;

        while (true) {
            local record = _parseRecord();

            switch (record.type) {
                case RECORD_TYPE_ULBA:
                    // ULBA should precede data
                    server.log(format(
                        "Firmware start address is 0x%04x0000",
                        record.data
                    ));
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

                            // flush up to _chunkSize bytes of data
                            local divider = data.len();

                            if (divider > _chunkSize) {
                                divider = _chunkSize;
                            };

                            data.seek(0);
                            local chunk = {
                                "start": ulba + chunkOffset,
                                "data": data.readblob(divider)
                            };

                            // and save the rest
                            if (data.eos()) {
                                data = blob();
                            } else {
                                data = data.readblob(data.len());
                            };

                            // append record to buffer
                            data.seek(0, 'e');
                            data.writeblob(record.data);

                            // correct chunk offset for the saved data
                            chunkOffset += divider;
                            yield chunk;
                        } else {
                            data.writeblob(record.data);
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

                    // prepare to reuse the file
                    _fileBlob.seek(0);

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

    _blobParser = null;
    _maxBlobSize = null;
    
    chunks = null;

    // callbacks
    _beforeSendBlob = null;
    _beforeSendChunk = null;
    _onDone = null;

    constructor(maxBlobSize=32768) {
        // initialize agent

        const EVENT_START_FLASHING = "start-flashing";
        const EVENT_REQUEST_CHUNK = "request-chunk";
        const EVENT_RECEIVE_CHUNK = "receive-chunk";
        const EVENT_DONE_FLASHING = "done-flashing";

        _maxBlobSize = maxBlobSize;

        init();
    };

    function init() {
        device.on(EVENT_REQUEST_CHUNK, onRequestChunk.bindenv(this));
        device.on(EVENT_DONE_FLASHING, onDoneFlashing.bindenv(this));
    };

    function setBeforeSendBlob(beforeSendBlob) {
        // Set callback for the moment after all agent side
        // initialization is done, but before sending blob to
        // device.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Agent class instance.
        //
        // Callback should return falsey value to abort sending
        // blob to device, or truey value to continue operation.


        _beforeSendBlob = beforeSendBlob;
    };

    function setBeforeSendChunk(beforeSendChunk) {
        // Set callback for the moment before sending chunk
        // to device.
        //
        // Callback parameters:
        // ⋅ DFUSTM32Agent class instance;
        // ⋅ chunk (either table with target address and blob of
        //   binary data, or null − end of transfer).
        //
        // No return value specified.

        _beforeSendChunk = beforeSendChunk;
    };

    function setOnDone(onDone) {
        // Set callback for the end of the agent-device operation.
        //
        // Callback parameter:
        // ⋅ DFUSTM32Agent class instance;
        // ⋅ client status string. By default it is either "OK" or
        //   "Aborted", but the range of statuses can be extended
        //   on device's side.
        //        
        // No return value specified.

        _onDone = onDone;
    };

    function _resetChunks() {
        // Resets chunk generator

        chunks = _blobParser.generateChunks();
    };

    function sendBlob(blob) {
        // invoke generator to split firmware into chunks and
        // send it to device

        _blobParser = IntelHexParser(blob);
        _resetChunks();

        // process callback
        if (_beforeSendBlob != null) {
            if (!_beforeSendBlob(this)) {
                // if callback returns falsy value, stop sending blob
                return;
            };
            // cleanup after running callback
            _resetChunks();
        };

        // start flashing
        device.send(EVENT_START_FLASHING, null);
    };

    function onRequestChunk(_) {
        // EVENT_REQUEST_CHUNK handler

        local chunk = resume chunks;

        if (_beforeSendChunk != null) {
            _beforeSendChunk(this, chunk);
        };
        device.send(EVENT_RECEIVE_CHUNK, chunk);
    };

    function onDoneFlashing(status) {
        // EVENT_DONE_FLASHING handler

        if (_onDone != null) {
            _onDone(this, status);
        };
    };

}
