// Agent source code goes here

@include "DFU-STM32/DFU-STM32.agent.lib.nut"

local dfu_stm32 = DFUSTM32Agent();

function onFlashRequest (request, response) {

    local responseCode = 200;
    local responseBody = {"message": "OK"};
    local status = "Unknown";

    switch (request.method) {
        case "GET":
            // return state of the system: idle, writing, or finished
            // writing firmware. In case of device support, this set
            // of states can be extended
            server.log("DFU-STM32 status: " + status);
            responseBody.message = status;
            break;
        case "POST":
            // request firmware update
            server.log("Firmware update requested.");

            // check if update is possible
            if (status == "Busy") {
                responseCode = 400;
                responseBody.message = "Firmware update is in progress!";
                break;
            };

            // do the update
            switch (request.headers["content-type"]) {
                case "application/json":
                    // body contains a URI, that points to the firmware file,
                    // and optional auth info
                    local requestBody = http.jsondecode(request.body);
                    if ("uri" in requestBody) {
                        server.log("Firmware source: " + requestBody.uri);
                    } else {
                        responseCode = 400;
                        responseBody.message = "Firmware location is not set!";
                        break;
                    };
                    if ("username" in requestBody) {
                        server.log("User name: " + requestBody.username);
                    };
                    if ("password" in requestBody) {
                        server.log("Password is provided.");
                    };
                    // TODO: create an actual blob
                    // TODO: start the update
                    break;
                case "application/octet-stream":
                    // body contains a firmware itself
                    server.log("Firmware recieved.");
                    // TODO: create an actual blob
                    // TODO: start the update

                    local firmwareBlob = blob();
                    firmwareBlob.writestring(request.body);
                    firmwareBlob.seek(0);
                    dfu_stm32.sendBlob(firmwareBlob);

                    break;
                default:
                    responseCode = 400;
                    responseBody.message = "Unknown firmware delivery method!";
            };
            break;
        default:
            responseCode = 400;
            responseBody.message = "Unknown operation";
    };

    response.header("Content-Type", "application/json");
    response.send(responseCode, http.jsonencode(responseBody));
};

http.onrequest(onFlashRequest);
