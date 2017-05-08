// Squirrel class to interface with the Conctr platform

// Copyright (c) 2016 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Conctr {

    static VERSION = "2.0.0";

    // event to emit data payload
    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";
    static AGENT_OPTS_EVENT = "conctr_agent_options";
    static SOURCE_DEVICE = "impdevice";
    static AGENT_OPTS = ["sendLocInterval", "sendLocOnce", "sendLoc", "locationOnWakeReason"];

    // 1 hour in seconds
    static DEFAULT_LOC_INTERVAL = 3600;


    // Location recording parameters
    _locationRecording = true;
    _locationSent = false;
    _locationTimeout = 0;
    _sendLocInterval = 0;
    _sendLocOnce = false;
    _locationOnWakeReason = [];

    _DEBUG = false;
    _sender = null;


    // 
    // Constructor for Conctr
    // 
    // @param opts - location recording options 
    // {
    //   {Boolean}  sendLoc             Should location be sent with data
    //   {Integer}  sendLocInterval     Duration in seconds between location updates
    //   {Boolean}  sendLocOnce         Setting to true sends the location of the device only once when the device restarts 
    //   {Object}   sender optional     MessageManager object
    //  }
    // 
    // NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
    //       with the data until this flag is changed.
    // 
    constructor(opts = {}) {
        // TODO handle only one of the args passed in
        _sender = ("messageManager" in opts) ? opts.messageManager : agent;
        // Set up event listeners
        _setupListeners();
        // Set location recording options
        setLocationOpts(opts);
    }


    // 
    // Funtion to set location recording options
    // 
    // @param opts {Table} - location recording options 
    // {
    //   {Boolean}  sendLoc - Should location be sent with data
    //   {Integer}  sendLocInterval - Duration in milliseconds since last location update to wait before sending a new location
    //   {Boolean}  sendLocOnce - Setting to true sends the location of the device only once when the device restarts 
    //  }
    // 
    // NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
    //       with the data until this flag is changed.
    // 
    function setLocationOpts(opts = {}) {

        _sendLocInterval = ("sendLocInterval" in opts && opts.sendLocInterval != null) ? opts.sendLocInterval : DEFAULT_LOC_INTERVAL;
        _sendLocOnce = ("sendLocOnce" in opts && opts.sendLocOnce != null) ? opts.sendLocOnce : false;
        _locationRecording = ("sendLoc" in opts && opts.sendLoc != null) ? opts.sendLoc : _locationRecording;
        _locationOnWakeReason = ("locationOnWakeReason" in opts && opts.locationOnWakeReason != null) ? opts.locationOnWakeReason : [];

        // Convert wake reasons to an array
        if (typeof _locationOnWakeReason != "array") {
            _locationOnWakeReason = [_locationOnWakeReason];
            // Change the original so array check does not need to be done on agent
            opts.locationOnWakeReason = _locationOnWakeReason;
        }

        _locationTimeout = 0;
        _locationSent = false;

        if (_DEBUG) {
            server.log("Conctr: setting agent options from device");
        }

        setAgentOpts(opts);
    }


    // 
    // @param  {Table} options - Table containing options to be sent to the agent
    // 
    function setAgentOpts(opts) {
        local agent_opts = {};
        // Get only relevant opts
        foreach (opt in AGENT_OPTS) {
            if (opt in opts) {
                agent_opts[opt] <- opts[opt];
            }
        }
        _sender.send(AGENT_OPTS_EVENT, agent_opts);
    }


    // 
    // @param  {Table or Array} payload - Table or Array containing data to be persisted
    // @param  { {Function (err,response)} callback - Callback function on resp from Conctr through agent
    // 
    function sendData(payload, callback = null) {

        local locationAdded = false;

        // If it's a table, make it an array
        if (typeof payload == "table") {
            payload = [payload];
        }

        if (typeof payload == "array") {

            foreach (k, v in payload) {
                // set timestamp to now if not already set
                if (!("_ts" in v) || (v._ts == null)) {
                    v._ts <- time();
                }

                v._source <- SOURCE_DEVICE;

                // Add the location if required
                if (!("_location" in v) && _shouldSendLocation() && !locationAdded) {

                    local wifis = imp.scanwifinetworks();
                    if (wifis != null && wifis.len() > 0) {
                        v._location <- wifis;
                        locationAdded = true;
                        // update timeout
                        local now = (hardware.millis() / 1000);
                        _locationTimeout = now + _sendLocInterval;
                        _locationSent = true;
                    }
                }

                if (_DEBUG) {
                    server.log("Conctr: Sending data to agent");
                }
            }

            local handler = _sender.send(DATA_EVENT, payload);
            // Listen for a reply if using bullwinkle/message manager and theres a callback
            if (callback && "onReply" in handler) {
                handler.onReply(function(msg, response = null) {
                    // Bullwinkle will send response in msg
                    // messageManager will send response as second
                    // arg, handle it here
                    if (response != null) {
                        msg = response;
                    } else {
                        msg = msg.data;
                    }

                    callback(msg.err, msg.resp);
                });
            }

        } else {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }
    }

    // 
    // Alias for sendData function, allows for conctr.send() to accept the same arguements as _sender.send()
    // @param  {String} unusedKey - An unused string
    // @param  {Table or Array} payload - Table or Array containing data to be persisted
    // @param  {{Function (err,response)} callback - Callback function on resp from Conctr through agent
    // 
    function send(unusedKey, payload = null, callback = null) {
        sendData(payload, callback);
    }


    // 
    // Sets up event listeners
    // 
    function _setupListeners() {
        _sender.on(LOCATION_REQ_EVENT, function(msg, reply = null) {
            // Handle both agent.send and messageManager.send syntax
            msg = ("data" in msg) ? msg.data : msg;
            _handleLocReq(msg);
        }.bindenv(this));
    }


    // 
    // handles a location request from the agent and responsed with wifis.
    // @return {[type]} [description]
    // 
    function _handleLocReq(arg) {

        if (_DEBUG) {
            server.log("Conctr: recieved a location request from agent");
        }
        sendData({});
    }


    // 
    // Checks current location recording options and returns true if location should be sent
    // 
    // @return {Boolean} - Returns true if location should be sent with the data.
    // 
    // 
    function _shouldSendLocation() {

        if (!_locationRecording) {

            // not recording location 
            return false;

        } else {

            // check new location scan conditions are met and search for proximal wifi networks
            local now = (hardware.millis() / 1000);
            // If there are no wakereasons set under which to send loc send loc. or if there are and a matach to specified reasons found send loc.
            local sendLocDueToWakeReason = (_locationOnWakeReason.len() == 0 || (_locationOnWakeReason.len() > 0 && _locationOnWakeReason.find(hardware.wakereason()) != null))

            if (((_locationSent == false) && sendLocDueToWakeReason) || ((_sendLocOnce == false) && (_locationTimeout - now < 0) && sendLocDueToWakeReason)) {

                return true;

            } else {
                // conditions for new location search (using wifi networks) not met
                return false;

            }
        }
    }
}
