// Squirrel class to interface with the Conctr platform

// Copyright (c) 2016 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Conctr {

    static version = [1, 0, 0];

    // event to emit data payload
    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ = "conctr_get_location";
    static AGENT_OPTS = "conctr_agent_options";
    static SOURCE_DEVICE = "impdevice";

    // 1 hour in milliseconds
    static HOUR_SEC = 3600;

    // Location recording parameters
    _locationRecording = true;
    _locationSent = false;
    _locationTimeout = 0;
    _sendLocInterval = 0;
    _sendLocOnce = false;

    _DEBUG = false;

    // Callbacks
    _onResponse = null;

    /**
     * Constructor for Conctr
     * 
     * @param opts - location recording options 
     * {
     *   {Boolean}  sendLoc - Should location be sent with data
     *   {Integer}  sendLocInterval - Duration in seconds between location updates
     *   {Boolean}  sendLocOnce - Setting to true sends the location of the device only once when the device restarts 
     *  }
     *
     * NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
     *       with the data until this flag is changed.
     */
    constructor(opts = null) {

        _onResponse = {};

        // Call setOpts even if opts is null so defaults are set and agent gets default opts.
        setOpts(opts);

        agent.on(DATA_EVENT, _doResponse.bindenv(this));
        agent.on(LOCATION_REQ,_handleLocReq.bindenv(this));
    }


    /**
     * Funtion to set location recording options
     * 
     * @param opts {Table} - location recording options 
     * {
     *   {Boolean}  sendLoc - Should location be sent with data
     *   {Integer}  sendLocInterval - Duration in milliseconds since last location update to wait before sending a new location
     *   {Boolean}  sendLocOnce - Setting to true sends the location of the device only once when the device restarts 
     *  }
     *
     * NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
     *       with the data until this flag is changed.
     */
    function setOpts(opts = {}) {

        _sendLocInterval = ("sendLocInterval" in opts && opts.sendLocInterval != null) ? opts.sendLocInterval : HOUR_SEC;
        _sendLocOnce = ("sendLocOnce" in opts && opts.sendLocOnce != null) ? opts.sendLocOnce : false;

        _locationRecording = ("sendLoc" in opts  && opts.sendLoc != null) ? opts.sendLoc : _locationRecording;
        _locationTimeout = (hardware.millis() / 1000);
        _locationSent = false;
        
        if (_DEBUG) {
            server.log("Conctr: setting agent options from device");
        }
        setAgentOpts(opts);
    }


    /**
     * @param  {Table} options - Table containing options to be sent to the agent
     */
    function setAgentOpts(opts) {
        
        agent.send(AGENT_OPTS,opts);
        
    }

    
    /**
     * @param  {Table} payload - Table containing data to be persisted
     * @param  { {Function (err,response)} callback - Callback function on resp from Conctr through agent
     */
    function sendData(payload, callback = null) {

        if (typeof payload != "table") {
            throw "Conctr: Payload must contain a table";
        }

        // set timestamp to now if not already set
        if (!("_ts" in payload) || (payload._ts == null)) {
            payload._ts <- time();
        }

        // Add an unique id for tracking the response
        payload._id <- format("%d:%d", hardware.millis(), hardware.micros());
        payload._source <- SOURCE_DEVICE;

        // Todo: Don't getWifis if the _location is already set
        _getWifis(function(wifis) {

            // Store the location (wifis) if we have it and if it's not already set
            if ((wifis != null) && !("_location" in payload)) {
                payload._location <- wifis;
            }

            // Todo: Add optional Bullwinkle here
            // Store the callback for later
            if (callback) _onResponse[payload._id] <- callback;

            agent.send("conctr_data", payload);

        }.bindenv(this));

    }


    /**
     * Responds to callback associated with (callback) ids in response from agent
     *
     * @param response {Table} - response for callback from agent - 
     * {
     *     {String}  id - id of the callback that was stored in _onResponse
     *     {Table}   error - error response from agent
     *     {Boolean} body - response body from agent 
     * }
     * 
     */
    function _doResponse(response) {
        foreach(id in response.ids) {
            if (id in _onResponse) {
                _onResponse[id](response.error, response.body);
            }
        }
    }

    
    /**
     * handles a location request from the agent and responsed with wifis.
     * @return {[type]} [description]
     */
    function _handleLocReq(arg) {

        if (_DEBUG) {
            server.log("Conctr: recieved a location request from agent");
        }

        sendData({});
    }



    /**
     * Checks current location recording options and calls the callback function with either currently available
     * wifis or null fullfilment of current conditions based on current options
     * 
     * @param  {Function} callback - called with wifi result 
     * @return {onSuccess([Objects])} - Array of wifi objects
     *
     */
    function _getWifis(callback) {

        if (!_locationRecording) {

            if (_DEBUG) {
                server.log("Conctr: location recording is not enabled");
            }

            // not recording location 
            return callback(null);

        } else {

            // check new location scan conditions are met and search for proximal wifi networks
            local now = (hardware.millis() / 1000);
            if ((_sendLocOnce == true) && (_locationSent == false) || ((_sendLocOnce == false) && (_locationRecording == true) && (_locationTimeout < now))) {

                local wifis = imp.scanwifinetworks();

                // update timeout 
                _locationTimeout = now + _sendLocInterval;
                _locationSent = true;

                return callback(wifis);

            } else {

                // conditions for new location search (using wifi networks) not met
                return callback(null);

            }
        }
    }
}
