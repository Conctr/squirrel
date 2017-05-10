// Squirrel class to interface with the Conctr platform

// Copyright (c) 2016-2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Conctr {

    static VERSION = "2.0.0";

    // event to emit data payload
    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";
    static AGENT_OPTS_EVENT = "conctr_agent_options";
    static SOURCE_DEVICE = "impdevice";
    static AGENT_OPTS = ["locInterval", "locSendOnce", "locRecording", "locOnWakeReason"];

    // 1 hour in seconds
    static DEFAULT_LOC_INTERVAL = 3600;


    // Location recording parameters
    _locRecording = true;
    _locationSent = false;
    _locationTimeout = 0;
    _locInterval = 0;
    _locSendOnce = false;
    _locOnWakeReason = [];

    _DEBUG = false;
    _sender = null;


    // 
    // Constructor for Conctr
    // 
    // @param opts - location recording options 
    // {
    //   {Boolean}  locRecording        Should location be sent with data
    //   {Integer}  locInterval         Duration in seconds between location updates
    //   {Boolean}  locSendOnce         Setting to true sends the location of the device only once when the device restarts 
    //   {Object}   sender optional     MessageManager object
    //  }
    // 
    // NOTE: locRecording takes precedence over locSendOnce. Meaning if locRecording is set to false location will never be sent 
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
    //   {Boolean}  locRecording - Should location be sent with data
    //   {Integer}  locInterval - Duration in milliseconds since last location update to wait before sending a new location
    //   {Boolean}  locSendOnce - Setting to true sends the location of the device only once when the device restarts 
    //  }
    // 
    // NOTE: locRecording takes precedence over locSendOnce. Meaning if locRecording is set to false location will never be sent 
    //       with the data until this flag is changed.
    // 
    function setLocationOpts(opts = {}) {

        _locInterval = ("locInterval" in opts && opts.locInterval != null) ? opts.locInterval : DEFAULT_LOC_INTERVAL;
        _locSendOnce = ("locSendOnce" in opts && opts.locSendOnce != null) ? opts.locSendOnce : false;
        _locRecording = ("locRecording" in opts && opts.locRecording != null) ? opts.locRecording : _locRecording;
        _locOnWakeReason = ("locOnWakeReason" in opts && opts.locOnWakeReason != null) ? opts.locOnWakeReason : [];

        // Convert wake reasons to an array
        if (typeof _locOnWakeReason != "array") {
            _locOnWakeReason = [_locOnWakeReason];
            // Change the original so array check does not need to be done on agent
            opts.locOnWakeReason = _locOnWakeReason;
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
                if (!("_location" in v) && _shouldlocRecordingation() && !locationAdded) {

                    local wifis = imp.scanwifinetworks();
                    if (wifis != null && wifis.len() > 0) {
                        v._location <- wifis;
                        locationAdded = true;
                        // update timeout
                        local now = (hardware.millis() / 1000);
                        _locationTimeout = now + _locInterval;
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
    function _shouldlocRecordingation() {

        if (!_locRecording) {

            // not recording location 
            return false;

        } else {

            // check new location scan conditions are met and search for proximal wifi networks
            local now = (hardware.millis() / 1000);
            // If there are no wakereasons set under which to send loc send loc. or if there are and a matach to specified reasons found send loc.
            local locRecordingDueToWakeReason = (_locOnWakeReason.len() == 0 || (_locOnWakeReason.len() > 0 && _locOnWakeReason.find(hardware.wakereason()) != null))

            if (((_locationSent == false) && locRecordingDueToWakeReason) || ((_locSendOnce == false) && (_locationTimeout - now < 0) && locRecordingDueToWakeReason)) {

                return true;

            } else {
                // conditions for new location search (using wifi networks) not met
                return false;

            }
        }
    }
}
