
// Squirrel class to interface with the Conctr platform (http://conctr.com)

// Copyright (c) 2016 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Conctr {

    static version = [1,0,0];

    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ = "conctr_get_location";
    static AGENT_OPTS = "conctr_agent_options";
    static SOURCE_DEVICE = "impdevice";
    static SOURCE_AGENT = "impagent";

    static HOUR_SEC = 3600; // One hour in seconds


    _api_key = null;
    _app_id = null;
    _device_id = null;
    _region = null;
    _env = null;
    _model = null;
    _dataApiEndpoint = null;

    // Location recording options
    _locationRecording = true;
    _locationSent = false;
    _locationTimeout = 0;
    _sendLocInterval = 0;
    _sendLocOnce = false;

    _DEBUG = false;


    /**
     * @param  {String} appId - Conctr application identifier
     * @param  {String} apiKey - Application specific api key from Conctr
     * @param  {String} model_ref - Model reference used to validate data payloads by Conctr, including the version number
     * @param  {String} user - Unique identifier for associated device. (Defaults to imp device id)
     * @param  {String} region - (defaults to "us-west-2")
     * @param  {String} env - (defaults to "core")
     */

    constructor(appId, apiKey, model_ref, useAgentId = false,region = null, env = null) {

        assert(typeof appId == "string");
        assert(typeof apiKey == "string");

        _app_id = appId;
        _api_key = apiKey;
        _model = model_ref;
        _region = (region == null) ? "us-west-2" : region;
        _env = (env == null) ? "staging" : env;
        _device_id = (useAgentId) ? split(http.agenturl(), "/").pop() : imp.configparams.deviceid;

        // Setup the endpoint url
        _dataApiEndpoint = _formDataEndpointUrl(_app_id, _device_id, _region, _env);
        _setOpts();

        // Set up listeners for device events
        device.on(DATA_EVENT, sendData.bindenv(this));
        device.on(AGENT_OPTS, _setOpts.bindenv(this));

    }



    /**
     * Set device unique identifier
     * 
     * @param {String} deviceId - Unique identifier for associated device. (Defaults to imp device id)
     */
    function setDeviceId(deviceId = null) {
        _device_id = (deviceId == null) ? imp.configparams.deviceid : deviceId;
        _dataApiEndpoint = _formDataEndpointUrl(_app_id, _device_id, _region, _env);
    }


    /**
     * Sends data for persistance to Conctr
     *
     * @param  {Table} payload - Table containing data to be persisted
     * @param  {Function (err,response)} callback - Callback function on http resp from Conctr
     * @return {Null}
     * @throws {Exception} -
     */
    function sendData(payload, callback = null) {

        // If it's a table, make it an array
        if (typeof payload == "table") {
            payload = [ payload ];
        }

        // Capture all the data ids in an array
        local ids = [];

        // Add the model id to each of the payloads
        if (typeof payload == "array") {

            // It's an array of tables
            foreach (k, v in payload) {
                if (typeof v != "table") {
                    throw "Conctr: Payload must contain a table or an array of tables";
                }

                if (!("_source" in v)) {
                    v._source <- SOURCE_AGENT;
                }

                // Set the model
                v._model <- _model;

                // Set the time stamp if not set already
                if (!("_ts" in v) || (v._ts == null)) {
                    v._ts <- time();
                }

                // Store the ids
                if ("_id" in v) {
                    ids.push(v._id);
                    delete v._id;
                }

                if ("_location" in v && !_locationSent) {
                    // Update _locationSent flag if payload has a location.
                    _locationSent = true;

                    //update timeout 
                    _locationTimeout = time() + _sendLocInterval;

                }

                // If location is not present in the payload and the payload did not come from the device request location from device.
                if (!("_location" in v) && v._source == SOURCE_AGENT) {
                    _getLocation();
                }
                
                _postDataToConctr(v, ids, callback);

            }
        } else {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }

    }

    /**
     * Posts data payload to Conctr.
     * @param  {Table}   payload  Data to be sent to Conctr
     * @param  {Array}   ids      Ids of callbacks to device
     * @param  {Function} callback Optional callback for result.
     */
    function _postDataToConctr(payload, ids, callback = null) {

        local headers = {};
        headers["Content-Type"] <- "application/json";
        if (_api_key.find("api:") == null) {
            headers["Authorization"] <- "api:" + _api_key;
        } else {
            headers["Authorization"] <- _api_key;
        }

        // Send the payload(s) to the endpoint
        if (_DEBUG) {
            server.log(format("Conctr: sending to %s", _dataApiEndpoint));
            server.log(format("Conctr: %s", http.jsonencode(payload)));
        }

        local request = http.post(_dataApiEndpoint, headers, http.jsonencode(payload));

        request.sendasync(function(response) {
            // Parse the response
            local success = (response.statuscode >= 200 && response.statuscode < 300);
            local body = null, error = null;

            // Parse out the body and the error if we can
            if (typeof response.body == "string" && response.body.len() > 0) {
                try {
                    body = http.jsondecode(response.body)

                    if ("error" in body) error = body.error;

                } catch (e) {
                    error = e;
                }
            }

            // If we have a failure but no error message, set it
            if (success == false && error == null) {
                error = "Http Status Code: " + response.statuscode;
            }


            if (_DEBUG) {
                if (error) server.error("Conctr: " + http.jsonencode(error));
                else if (body) server.log("Conctr: response: " + http.jsonencode(body));
            }

            // Return the result
            if (callback) {
                callback(error, body);
            } else if (ids.len() > 0) {
                // Send the result back to the device
                local device_result = { "ids": ids, "body": body, "error": error};
                device.send(DATA_EVENT, device_result);
            } else if (error != null) {
                server.error("Conctr Error: " + error);
            }

        }.bindenv(this));
    }

    /**
     * Sends a request to the device to send its current location (array of wifis) if conditions in current location sending opts are met. 
     * Note: device will send through using its internal sendData function, we will not wait send location within the current payload.
     * 
     */
    function _getLocation() {

        if (!_locationRecording) {

            if (_DEBUG) {
                server.log("Conctr: location recording is not enabled");
            }
            // not recording location 
            return;

        } else {
           
            //check new location scan conditions are met and search for proximal wifi networks
            if ((_sendLocOnce == true && _locationSent == false) || ((_sendLocOnce == false) && (_locationRecording == true) && (_locationTimeout <= time()))) {
                
                if (_DEBUG) {
                    server.log("Conctr: requesting location from device");
                }

                //update timeout 
                _locationTimeout = time() + _sendLocInterval;

                //update flagg to show we sent location.
                _locationSent = true;

                //Request location from device
                device.send(LOCATION_REQ,"");

            } else {
                //conditions for new location search (using wifi networks) not met
                return;
            }
        }
    }

    /**
     * Funtion to set location recording options
     * 
     * @param opts {Table} - location recording options 
     * {
     *   {Boolean}  sendLoc - Should location be sent with data
     *   {Integer}  sendLocInterval - Duration in seconds between location updates
     *   {Boolean}  sendLocOnce - Setting to true sends the location of the device only once when the device restarts 
     *  }
     *
     * NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
     *       with the data until this flag is changed.
     */
    function _setOpts(opts = {}) {

        if (_DEBUG) {
            server.log("Conctr: setting agent opts to: " + http.jsonencode(opts));
        }

        _sendLocInterval = ("sendLocInterval" in opts && opts.sendLocInterval != null) ? opts.sendLocInterval : HOUR_SEC; // set default sendLocInterval between location updates
        _sendLocOnce = ("sendLocOnce" in opts && opts.sendLocOnce != null) ? opts.sendLocOnce : false;
        _locationRecording = ("sendLoc" in opts  && opts.sendLoc != null) ? opts.sendLoc : _locationRecording;
        _locationSent = false;
    }

    /**
     * Forms and returns the insert data API endpoint for the current device and Conctr application
     *
     * @param  {String} appId
     * @param  {String} deviceId
     * @param  {String} region
     * @param  {String} env
     * @return {String} url endpoint that will accept the data payload
     */
    function _formDataEndpointUrl(appId, deviceId, region, env) {

        // This is the temporary value of the data endpoint.
        return format("https://api.%s.conctr.com/data/apps/%s/devices/%s", env, appId, deviceId);
        // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
        //return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s", region, env, appId, deviceId);
    }

}
