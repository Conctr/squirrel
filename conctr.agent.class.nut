
// Squirrel class to interface with the Conctr platform

// Copyright (c) 2016 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Conctr {

    static version = [1,0,0];

    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ = "conctr_get_location";
    static LOCATION_RESP = "conctr_location";

    _lastKnownLoc = null;

    _api_key = null;
    _app_id = null;
    _device_id = null;
    _region = null;
    _env = null;
    _model = null;
    _dataApiEndpoint = null;

    _DEBUG = false;


    /**
     * @param  {String} app_id -
     * @param  {String} api_key - Application specific api key from Conctr
     * @param  {String} model_ref - Model reference used to validate data payloads by Conctr, including the version number
     * @param  {String} region - (defaults to "us-west-2")
     * @param  {String} env - (defaults to "core")
     * @param  {String} device_id - Unique identifier for associated device. (Defaults to imp device id)
     */

    constructor(app_id, api_key, model_ref, region = null, env = null, device_id = null) {

        assert(typeof app_id == "string");
        assert(typeof api_key == "string");

        _app_id = app_id;
        _api_key = api_key;
        _model = model_ref;
        _region = (region == null) ? "us-west-2" : region;
        _env = (env == null) ? "core" : env;
        _device_id = (device_id == null) ? imp.configparams.deviceid : device_id;

        _lastKnownLoc={"location":null,"ts":0};

        // Setup the endpoint url
        _dataApiEndpoint = _formDataEndpointUrl(_app_id, _device_id, _region, _env);

        // Set up listeners for device events
        device.on(DATA_EVENT, sendData.bindenv(this));

    }



    /**
     * Set device unique identifier
     * 
     *@param {String} device_id - Unique identifier for associated device. (Defaults to imp device id)
     */
    function setDeviceId(device_id) {
        _device_id = (device_id == null) ? imp.configparams.deviceid : device_id;
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

        local currentWifis=null;

        // Add the model id to each of the payloads
        if (typeof payload == "array") {

            // It's an array of tables
            foreach (k,v in payload) {
                if (typeof v != "table") {
                    throw "Conctr: Payload must contain a table or an array of tables";
                }

                // Set the model
                payload[k]._model <- _model;

                // Set the time stamp if not set already
                if (!("_ts" in payload[k]) || (payload[k]._ts == null)) {
                    payload[k]._ts <- time();
                }

                //cache the last known location if it is more recent then current cached value
                if("_location" in payload[k] && payload[k]._ts > _lastKnownLoc.ts){
                    _lastKnownLoc.location=payload[k]._location;
                    _lastKnownLoc.ts=payload[k]._ts;
                }

                // Store the ids
                if ("_id" in payload[k]) {
                    ids.push(payload[k]._id);
                    delete payload[k]._id;
                }



                //If location is not present in the payload and the payload did not come from the device request location from device. 
                if(!("_location" in payload[k]) && (!("_source" in payload[k]) ||  ("_source" in payload[k] && payload[k]._source!="impdevice"))){
                    if(currentWifis==null && device.isconnected()){
                        if(_DEBUG){
                            server.log("Retrieving location from device");
                        }
                        _getLocation(function(wifis){
                            if(wifis!=null){
                                currentWifis=wifis;
                                _lastKnownLoc.location=wifis;
                                _lastKnownLoc.ts=time();
                                payload[k]._location <- wifis;
                            }
                                
                            _postDataToConctr(payload[k],callback);

                        }.bindenv(this));
                    }else{

                        if(_DEBUG){
                            server.log("Skipping location request from device.");
                        }

                        if(currentWifis!=null){
                            payload._location=currentWifis;
                        }else{
                            server.log("CONCTR: warning, could not get location from device as it is not connected.");
                        }

                        _postDataToConctr(payload[k],callback);
                    }
                }else{
                    _postDataToConctr(payload[k],callback);
                }

            }
        } else {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }

    }

    function _postDataToConctr(payload,callback = null){


        local headers = {
            "Content-Type": "application/json",
            "Authorization": "api:" + _api_key
        };


        // Send the payload(s) to the endpoint
        if (_DEBUG) server.log(format("CONCTR Sending: %s",http.jsonencode(payload)));

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
                if (body) server.log("CONCTR Response: " + http.jsonencode(body));
                if (error) server.log("CONCTR Error: " + http.jsonencode(error));
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
     * Retrieves location (array of wifis) from device if conditions in current location sending opts are met, responds with null if conditions not met
     * @param  {Function} callback [description]
     */
    function _getLocation(callback){

        if(_DEBUG){
            server.log("CONCTR:Requesting location from device.");
        }

        device.on(LOCATION_RESP,callback);

        device.send(LOCATION_REQ,"");

        

    }

    /**
     * Returns a table containing the last recieved location update from the device
     * @return {Table} last known location with keys location and ts (timestamp) 
     * {
     *     location,
     *     ts
     * }
     */
    function getLastKnownLocation(){
        return _lastKnownLoc;
    }

    /**
     * Forms and returns the insert data API endpoint for the current device and Conctr application
     *
     * @param  {String} app_id
     * @param  {String} device_id
     * @param  {String} region
     * @param  {String} env
     * @return {String} url endpoint that will accept the data payload
     */
    function _formDataEndpointUrl(app_id, device_id, region, env) {

        // This is the temporary value of the data endpoint.
        return format("https://api.%s.conctr.com/data/apps/%s/devices/%s", env, app_id, device_id);
        // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
        //return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s", region, env, app_id, device_id);
    }

}
