// DFU-STM32 agent library

class FirmwareBlob {
	// Emulates blob interface on remote file.

	firmwareUri = null;
	bufferSize = null;

	constructor (size, uri) {
		bufferSize = size;
		firmwareUri = uri;
	};

}

class DFUSTM32Agent {
	// Firmware updater agent is responsible for:
	// ⋅ parsing .hex or .dfu files and creating firmware blobs,
	// ⋅ keeping account on available firmware versions,
	// ⋅ spliting blobs on chunks,
	// ⋅ sending chunks to device.

	static VERSION = "0.1.0";

	static firmwares = {};

	maxFirmwareBlobSize = null;

	constructor(maxBlobSize=32768) {
		// initialize agent

		maxFirmwareBlobSize = maxBlobSize;

	};

	function parseFirmware (uri) {
		// parses firmware file from given URI
		local resp = http.get(uri, {"Range": "bytes=0-0"}).sendsync();
		// file must exist
		local fileSize = split(resp.headers["content-range"], "/")[1].tointeger();

		if (fileSize > maxFirmwareBlobSize) {
			result = FirmwareBlob(maxFirmwareBlobSize, uri);
		} else {
			resp = http.get(uri).sendsync();
			result = blob(fileSize);
			result.writestring(resp.body);
		};
		return result;
	};

	function addFirmware (versionId, uri) {
		// adds firmware to firmware pool
		firmwares[versionId] <- parseFirmware(url);
	};

	function deleteFirmware (versionId) {
		// deletes firmware form pool
		delete firmwares[versionId];
	};

	function canUpdate (currentVersionId) {
		// returns array of version IDs higher than current (may be empty)

	};



}
