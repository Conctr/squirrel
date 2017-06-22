// MIT License

// Copyright (c) 2016-2017 Mystic Pants Pty Ltd

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

class Conctr {

    static VERSION = "2.0.0";

    // Events
    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";

    // Data source label
    static SOURCE_DEVICE = "impdevice";

    // Default location recording opts
    static DEFAULT_LOC_ENABLED = true;
    static DEFAULT_LOC_INTERVAL = 3600;
    static DEFAULT_LOC_SEND_ONCE = true;
    static DEFAULT_WAKE_REASONS = [WAKEREASON_NEW_SQUIRREL, WAKEREASON_POWER_ON];


    // Location recording parameters
    _locEnabled = null; // Boolean to enable/disable location sending
    _locInterval = null; // Integer time interval between location updates
    _locSendOnce = null; // Boolean to send location only once
    _locWakeReasons = null; // Array of hardware.wakereasons()

    // Location state
    _locSent = false;   // location sent
    _locTimeout = 0;    // location data time out

    // Source of the data
    _sender = null;

    DEBUG = false;


    //
    // Constructor for Conctr
    //
    // @param opts - location recording options
    // {
    //   {Boolean}  locEnabled        Should location be sent with data
    //   {Integer}  locInterval         Duration in seconds between location updates
    //   {Boolean}  locSendOnce         Setting to true sends the location of the device only once when the device restarts
    //   {Object}   sender optional     MessageManager object
    //  }
    //
    // NOTE: locEnabled takes precedence over locSendOnce. Meaning if locEnabled is set to false location will never be sent
    //       with the data until this flag is changed.
    //
    constructor(opts = {}) {
        _locWakeReasons = [];

        // Grab any constructor options
        _sender = ("messageManager" in opts) ? opts.messageManager : agent;

        // Set the default values for the location options and then override them
        _locInterval = DEFAULT_LOC_INTERVAL;
        _locSendOnce = DEFAULT_LOC_SEND_ONCE;
        _locEnabled = DEFAULT_LOC_ENABLED;
        _locWakeReasons = DEFAULT_WAKE_REASONS;
        setLocationOpts(opts);

        _setupListeners();
    }


    //
    // Function to set location recording options
    //
    // @param opts {Table} - location recording options
    // {
    //   {Boolean}       locEnabled - Should location be sent with data
    //   {Integer}       locInterval - Duration in milliseconds since last location update to wait before sending a new location
    //   {Boolean}       locSendOnce - Setting to true sends the location of the device only once when the device restarts
    //   {Array/Integer} locWakeReasons - Send the location only when the imp.wakereason() is one of these values
    //  }
    //
    // NOTE: locEnabled takes precedence over all other options. Meaning if locEnabled is set to false location will never be sent automatically.
    //
    function setLocationOpts(opts = {}) {

        _locInterval = ("locInterval" in opts && opts.locInterval != null) ? opts.locInterval : _locInterval;
        _locSendOnce = ("locSendOnce" in opts && opts.locSendOnce != null) ? opts.locSendOnce : _locSendOnce;
        _locEnabled = ("locEnabled" in opts && opts.locEnabled != null) ? opts.locEnabled : _locEnabled;
        _locWakeReasons = ("locWakeReasons" in opts && opts.locWakeReasons != null) ? opts.locWakeReasons : _locWakeReasons;

        // Convert wake reasons to an array
        if (typeof _locWakeReasons != "array") {
            _locWakeReasons = [_locWakeReasons];
        }

        _locTimeout = 0;
        _locSent = false;

    }


    //
    // Sends data to conctr
    //
    // @param  {Table or Array} payload - Table or Array containing data to be persisted
    // @param  { {Function (err,response)} callback - Callback function on resp from Conctr through agent
    //
    function sendData(payload, callback = null) {

        // If it's a table, make it an array
        if (typeof payload == "table") {
            payload = [payload];
        }

        if (typeof payload == "array") {

            local locationAdded = false;
            foreach (k, v in payload) {
                // set timestamp to now if not already set
                if (!("_ts" in v) || (v._ts == null)) {
                    v._ts <- time();
                }

                v._source <- SOURCE_DEVICE;

                // Have we already added the location
                if ("_location" in v) {
                    locationAdded = true;
                } else if (!locationAdded) {

                    // Add the location if required
                    if (_shouldRecordLocation()) {
                        if (DEBUG) server.log("Conctr: Conditions met. Sending location.")
                        local wifis = imp.scanwifinetworks();
                        if (wifis != null && wifis.len() > 0) {
                            // Add the location to the data
                            v._location <- wifis;
                            locationAdded = true;
                            // update timeout for future location requests
                            _locTimeout = (hardware.millis() / 1000) + _locInterval;
                            _locSent = true;
                        }
                    }
                }
            }

            if (DEBUG) server.log("Conctr: Sending data to agent");

            // Listen for a reply if using bullwinkle/message manager and theres a callback
            local handler = _sender.send(DATA_EVENT, payload);
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
                }.bindenv(this));
            } else if (callback) {
                // We are asked to callback but we don't have an real callback
                local err = (handler == 0) ? null : "Conctr: Send error: " + handler;
                local res = (typeof handler == "integer") ? handler : null;
                imp.wakeup(0, function() {
                    callback(err, res);
                }.bindenv(this));
            }

        } else {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }
    }


    //
    // Alias for sendData function, allows for conctr.send() to accept the same arguements as agent.send()
    //
    // @param  {String}         unusedKey   An unused string
    // @param  {Table or Array} payload     Table or Array containing data to be persisted
    // @return {Integer}                    Zero on success the same as agent.send
    //
    function send(unusedKey, payload) {
        sendData(payload, null);
        return 0;
    }


    //
    // Sends current location to the agent or to Conctr
    //
    // @param  {Boolean} sendToConctr - If true the location will be sent to Conctr. If false, it will be cached on the agent.
    //
    function sendLocation(sendToConctr = true) {

        if (DEBUG) server.log("Conctr: sending location to " + (sendToConctr ? "conctr" : "agent"));
        _sender.send(LOCATION_REQ_EVENT, { "_location": imp.scanwifinetworks(), "sendToConctr": sendToConctr });
        _locTimeout = (hardware.millis() / 1000) + _locInterval;
        _locSent = true;

    }


    //
    // Sets up event listeners
    //
    function _setupListeners() {

        // Listen for location requests from the agent
        _sender.on(LOCATION_REQ_EVENT, function(msg, reply = null) {
            // Handle both agent.send and messageManager.send syntax
            if (DEBUG) server.log("Conctr: received a location request from agent");
            msg = ("data" in msg) ? msg.data : msg;
            sendLocation(msg == true);
        }.bindenv(this));

    }


    //
    // Checks current location recording options and returns true if location should be sent
    //
    // @return {Boolean} - Returns true if location should be sent with the data.
    //
    function _shouldRecordLocation() {

        // not recording location
        if (!_locEnabled) return false;

        // Send the location when there are no wake reasons set or when there is a match in the provided array of wake reasons.
        local matchedWakeReason = (_locWakeReasons.len() == 0 || _locWakeReasons.find(hardware.wakereason()) != null)
        if (!matchedWakeReason) return false;

        // Only send the location once if set
        if (_locSendOnce && _locSent) return false;

        // Don't send another location if the previous one was to recent
        local now = (hardware.millis() / 1000);
        if (_locTimeout - now >= 0) return false;

        // All conditions have passed, send the location.
        return true;

    }
}

// MessageManager options
// mmOpts <- {
//     "retryInterval": 15,
//     "messageTimeout": 20,
//     "autoRetry": true,
//     "maxAutoRetries": 10,
// };

// mm <- MessageManager(mmOpts);

// Conctr options
conctrOpts <- {
    "locEnabled": true,
    "locInterval": 3600,
    "locSendOnce": false,
    "locWakeReasons": [WAKEREASON_BLINKUP, WAKEREASON_PIN, WAKEREASON_NEW_SQUIRREL],
    // "messageManager": mm
}

conctr <- Conctr(conctrOpts);
