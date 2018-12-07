// Agent source code goes here

@include "DFU-STM32/DFU-STM32.agent.lib.nut"

local status = "Idle";
local firmwareSize = 0;
local progressCounter = 0;

function getProgress() {
    // Returns float value of progress in %.

    return progressCounter.tofloat() / firmwareSize.tofloat() * 100.0;
};

function setStatus(stm32, flashingStatus) {
    // Set status back to “Idle”.

    status = "Idle";
    server.log("Flashing is done.");
};

function determineFirmwareSize(stm32) {
    // Determine the size of the firmware binary.

    foreach (chunk in stm32.chunks) {
        if (chunk != null) {
            firmwareSize += chunk.data.len();
        };
    };
    server.log(format("Firmware size is %i bytes", firmwareSize));

    return true;
};

function advanceCounter(stm32, chunk) {
    // Advance and display the progress counter.

    if (chunk != null) {
        progressCounter += chunk.data.len();
        
        server.log(format("Flashing: %.1f%% done", getProgress()));
    };
};

local dfu_stm32 = DFUSTM32Agent();
dfu_stm32.setBeforeSendBlob(determineFirmwareSize);
dfu_stm32.setBeforeSendChunk(advanceCounter);
dfu_stm32.setOnDone(setStatus);

function updateFirmware(request, response) {
    // MCU's firmware update callback.

    local responseCode = 200;
    local responseBody = {"message": "OK"};

    switch (request.method) {
        case "GET":
            // return system state: “Idle” or “Busy” writing firmware
            server.log("DFU-STM32 status: " + status);
            responseBody.message = status;
            break;

        case "POST":
            // request firmware update
            server.log("Firmware update requested.");

            // check if update is possible
            if (status == "Busy") {
                responseCode = 400;
                responseBody.message = format(
                    "Firmware update is in progress. %.1f%% is complete so far.",
                    getProgress()
                );
                break;
            };

            // do the update
            if (request.headers["content-type"] == "application/octet-stream") {
                // Different content types may signify different methods of
                // firmware delivery. For example, “application/octet-stream”
                // means that the body of the request contains the firmware
                // itself.

                status = "Busy";
                server.log("Firmware recieved.");

                local firmwareBlob = blob();
                firmwareBlob.writestring(request.body);
                firmwareBlob.seek(0);
                dfu_stm32.sendBlob(firmwareBlob);
            } else {
                responseCode = 400;
                responseBody.message = "Unknown firmware delivery method.";
            };
            break;

        default:
            responseCode = 400;
            responseBody.message = "Unknown operation.";
    };

    response.header("Content-Type", "application/json");
    response.send(responseCode, http.jsonencode(responseBody));
};

function dispatchRequest(request, response) {
    // This is a simple HTTP requests dispatcher.

    local dispatchTable = {};
    dispatchTable["/firmware/update"] <- updateFirmware;

    // There may be other agent functions controlled via Internet.
    // They all should be placed in dispatchTable.

    foreach (urlPattern, handler in dispatchTable) {
        if (request.path.find(urlPattern) == 0) {
            handler(request, response);
            return;
        };
    }
    
    // 404 handler
    response.send(404, "No such endpoint.");
};


http.onrequest(dispatchRequest);
