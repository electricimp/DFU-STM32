// DFU-STM32 agent library

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

	blob = null;
	maxFirmwareBlobSize = null;
	chunkSize = null;
	status = null;

	constructor(maxBlobSize=32768) {
		// initialize agent

		status = "Unknown";
		maxFirmwareBlobSize = maxBlobSize;

	};

	function onRequest(query, response) {
		// This method is a public interface of the library

		local responseCode = 200;
		local responseBody = {"message": "OK"};

		switch (query.method) {
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
				switch (query.headers["content-type"]) {
					case "application/json":
						// body contains a URI, that points to the firmware file,
						// and optional auth info
						local queryBody = http.jsondecode(query.body);
						if ("uri" in queryBody) {
							server.log("Firmware source: " + queryBody.uri);
						} else {
							responseCode = 400;
							responseBody.message = "Firmware location is not set!";
							break;
						};
						if ("username" in queryBody) {
							server.log("User name: " + queryBody.username);
						};
						if ("password" in queryBody) {
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

	function createBlob (uri) {
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

	function validateBlob (blob) {
		// check memory ranges or target MCU type/PnP ID,
		// maybe include custom callback

		// ...
	};

	function sendBlob (blob) {
		// invoke generator to split firmware into chunks and
		// send it to device
	};

}
