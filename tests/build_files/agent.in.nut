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

    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";
    static SOURCE_DEVICE = "impdevice";
    static SOURCE_AGENT = "impagent";
    static MIN_TIME = 946684801; // Epoch timestamp for 00:01 AM 01/01/2000 (used for timestamp sanity check)
    static MIN_RECONNECT_TIME = 5;

    // Request opt defaults
    static MAX_RETIES_DEFAULT = 3;
    static RETRIES_LIMIT = 10;
    static EXP_BACKOFF_DEFAULT = true;
    static RETRY_INTERVAL_DEFAULT = 5;
    static MAX_RETRY_INTERVAL = 60;

    // Conctr Variables
    _api_key = null; // application programming interface key
    _app_id = null; // application id
    _device_id = null; // id of the device
    _headers = null; // headers for posting to conctr
    _region = null; // aws region
    _env = null; // environment staging or dev
    _model = null; // conctr model
    _rocky = null; // rocky library object
    _sender = null; // messaging object
    _location = null; // the last known location

    // Pending queue status
    _pendingReqs = null; // pending a request 
    _pendingTimer = null; // timer for pending a request

    // Debug flag. If set, stuff will log
    DEBUG = false;


    // 
    // Constructor
    // 
    // @param  {String}  appId       Conctr application identifier
    // @param  {String}  apiKey      Application specific api key from Conctr
    // @param  {String}  model_ref   Model reference used to validate data payloads by Conctr, including the version number
    // @param  {Table}   opts        Optional config parameters:-
    // {
    //   {Boolean} useAgentId       Flag on whether to use agent id or device id as identifier to Conctr (defaults to false)
    //   {String}  region           Which region is application in (defaults to "us-west-2")
    //   {String}  env              What Conctr environment should be used(defaults to "staging")}
    //   {Object}  rocky            Model reference used to validate data payloads by Conctr, including the version number
    //   {Object}  messageManager   MessageManager object
    // }
    // 
    constructor(appId, apiKey, model_ref, opts = {}) {
        assert(typeof appId == "string");
        assert(typeof apiKey == "string");
        assert(typeof model_ref == "string");
        assert(typeof opts == "table");

        _app_id = appId;
        _api_key = apiKey;
        _model = model_ref;

        _headers = {}


        _headers["Content-Type"] <- "application/json";
        _headers["Authorization"] <-(_api_key.find("api:") == null) ? "api:" + _api_key : _api_key;

        _env = ("env" in opts) ? opts.env : "staging";
        _region = ("region" in opts) ? opts.region : "us-west-2";
        _device_id = ("useAgentId" in opts && opts.useAgentId == true) ? split(http.agenturl(), "/").pop() : imp.configparams.deviceid;
        _rocky = ("rocky" in opts) ? opts.rocky : null;
        _sender = ("messageManager" in opts) ? opts.messageManager : device;

        // Set up agent endpoints
        if (_rocky != null) {
            _setupAgentApi(_rocky);
        }

        // Set up listeners for device events
        _setupListeners();
    }


    // 
    // Set device unique identifier
    // 
    // @param {String} deviceId - Unique identifier for associated device. (Defaults to imp device id)
    // 
    function setDeviceId(deviceId = null) {
        _device_id = (deviceId == null) ? imp.configparams.deviceid : deviceId;
        return this;
    }


    // 
    // Sends data for persistance to Conctr
    // 
    // @param  {Table or Array}          payload  - Table or Array containing data to be persisted
    // @param  {Function (err,response)} callback - Callback function on http resp from Conctr
    // @return {Null}
    // 
    function sendData(payload, callback = null) {

        // If it's a table, make it an array
        if (typeof payload == "table") {
            payload = [payload];
        }

        if (typeof payload != "array") {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }

        // It's an array of tables
        foreach (k, v in payload) {
            if (typeof v != "table") {
                throw "Conctr: Payload must contain a table or an array of tables";
            }

            // Set the source of data
            if (!("_source" in v)) {
                v._source <- SOURCE_AGENT;
            }

            // Set the model
            v._model <- _model;

            // Validate the timestamp if set, else set it
            local shortTime = false;
            if (("_ts" in v) && (typeof v._ts == "integer")) {

                // Invalid numerical timestamp? Replace it.
                if (v._ts < MIN_TIME) {
                    shortTime = true;
                }
            } else if (("_ts" in v) && (typeof v._ts == "string")) {

                local isNumRegex = regexp("^[0-9]*$");

                // check whether ts is a string of numbers only
                local isNumerical = (isNumRegex.capture(v._ts) != null);

                if (isNumerical == true) {
                    // Invalid string timestamp? Replace it.
                    if (v._ts.len() <= 10 && v._ts.tointeger() < MIN_TIME) {
                        shortTime = true;
                    } else if (v._ts.len() > 10 && v._ts.tointeger() / 1000 < MIN_TIME) {
                        shortTime = true;
                    }
                }
            } else {
                // No timestamp? Add it now.
                v._ts <- time();
            }

            if (shortTime) {
                server.log("Conctr: Warning _ts must be after 1st Jan 2000. Setting to imps time() function.")
                v._ts <- time();
            }

            // Add the location if we have it
            if (!("_location" in v) && (_location != null)) {
                v._location <- _location;
            }
            _location = null;

        }

        // Post data straight through if nothing queued else add to queue
        _postToIngestion(payload, callback);
    }


    //
    // Requests the device sends its current location to the agent or to Conctr
    //
    // @param  {Boolean} sendToConctr - If true the location will be sent to Conctr. If false, it will be cached on the agent.
    //
    function sendLocation(sendToConctr = true) {

        if (DEBUG) server.log("Conctr: requesting location be sent to " + (sendToConctr ? "conctr" : "agent"));
        _sender.send(LOCATION_REQ_EVENT, sendToConctr);

    }
    

    // 
    // Posts a sendData payload to conctrs ingestion engine
    // 
    // @param {Array}       payload    The data payload
    // @param {Function}    cb         Optional callback
    // 
    function _postToIngestion(payload, cb = null) {

        // Store up requests if we have an active queue
        if (_pendingReqs != null) {
            _pendingReqs.payloads.extend(payload);
            _pendingReqs.callbacks.push(cb);
            return;
        }

        local url = _formDataEndpointUrl();
        local req = http.request("POST", url, _headers, http.jsonencode(payload));

        req.sendasync(function(resp) {

            if (resp.statuscode >= 200 && resp.statuscode < 300) {

                // All good return
                if (cb) {
                    // Call all callbacks
                    local err = null;
                    if (typeof cb != "array") cb = [cb];
                    foreach (func in cb) {
                        func(err, resp);
                    }
                }
                return;

            } else if (resp.statuscode == 429 || resp.statuscode < 200 || resp.statuscode >= 500) {

                // Create a new pending queue or append to an existing one
                if (_pendingReqs == null) {
                    _pendingReqs = { "payloads": [], "callbacks": [] };
                    if (DEBUG) server.log("Conctr: Starting to queue data in batch");
                }
                _pendingReqs.payloads.extend(payload);
                _pendingReqs.callbacks.push(cb);

                // Wait a second for the agent to cool off after an error
                // Don't pass if there is another timer running
                if (_pendingTimer != null) return;
                _pendingTimer = imp.wakeup(1, function() {
                    if (DEBUG) server.log("Conctr: Sending queued data in batch");
                    // backup and release the pending queue before retrying to post it
                    _pendingTimer = null;
                    local pendingReqs = _pendingReqs;
                    _pendingReqs = null;
                    return _postToIngestion(pendingReqs.payloads, pendingReqs.callbacks);
                }.bindenv(this))
                return;

            } else {

                // Unrecoverable error or max retries, dont bother retrying let the user handle it.
                local err = "HTTP error code: " + resp.statuscode;
                if (cb == null) {
                    server.error("Conctr: " + err);
                } else {
                    // Call all callbacks
                    if (typeof cb != "array") cb = [cb];
                    foreach (func in cb) {
                        func(err, resp);
                    }
                }
                return;

            }

        }.bindenv(this))
    }


    // 
    // Takes a http request and retries request in specific scenarios like 429 or curl errors
    // 
    // @param  {Object}   req       Http request
    // @param  {Function} cb        Function to call on response. Takes args (err, resp)
    // @param  {Table}    opts      Table to specify retry opts.
    // 
    function _requestWithRetry(method, url, headers, payload, opts = {}, cb = null) {

        if (opts == null || typeof opts == "function") {
            cb = opts;
            opts = {};
        }

        // Method must be upper case
        method = method.toupper();

        // Reject invalid methods
        if (["GET", "POST"].find(method) == null) {
            throw "Invalid method, must be either POST or GET";
        }

        local req = http.request(method, url, headers, payload);

        req.sendasync(function(resp) {
            local wakeupTime = 1;
            // Get set opts
            local maxRetries = ("maxRetries" in opts && opts.maxRetries < RETRIES_LIMIT) ? opts.maxRetries : MAX_RETIES_DEFAULT;
            local expBackoff = ("expBackoff" in opts) ? opts.expBackoff : EXP_BACKOFF_DEFAULT;
            local retryInterval = ("retryInterval" in opts) ? opts.retryInterval : RETRY_INTERVAL_DEFAULT;

            // Get state opts
            local retryNum = ("_retryNum" in opts) ? opts._retryNum : 1;

            if (resp.statuscode >= 200 && resp.statuscode < 300) {
                // All good return
                if (cb) cb(null, resp);
                return;
            } else if (resp.statuscode == 429 || resp.statuscode < 200 || resp.statuscode >= 500) {
                // Want to retry these ^ codes
                // Exponential back off or use a set interval
                if (expBackoff == true) {
                    wakeupTime = math.pow(2, retryNum - 1);
                    if (wakeupTime > MAX_RETRY_INTERVAL) {
                        wakeupTime = MAX_RETRY_INTERVAL;
                    }
                } else {
                    wakeupTime = retryInterval;
                }
            }

            if (retryNum >= maxRetries || !(resp.statuscode == 429 || resp.statuscode < 200 || resp.statuscode >= 500)) {
                // Unrecoverable error or max retries, dont bother retrying let the user handle it.
                local error = "HTTP error code: " + resp.statuscode;
                if (cb) cb(error, resp);
                else server.error("Conctr: " + error);
                return;
            }

            // Increment retry count for next round
            opts._retryNum <- retryNum + 1;

            // Retry in wakeupTime seconds
            imp.wakeup(wakeupTime, function() {
                _requestWithRetry(method, url, headers, payload, opts, cb);
            }.bindenv(this));
        }.bindenv(this));
    }


    // 
    // Sets up event listeners
    // 
    function _setupListeners() {

        // Listen for data events from the device
        _sender.on(DATA_EVENT, function(msg, reply = null) {

            // Reply is null when we are agent.on
            msg = (reply == null) ? msg : msg.data;

            // Check if the device is waiting for a response
            if (reply == null) {
                sendData(msg)
            } else {
                // Send response back to the device
                sendData(msg, function(err, resp) {
                    // Send both err and resp so callback can
                    // can be called with both params on device
                    reply({ "err": err, "resp": resp })
                }.bindenv(this))
            }

        }.bindenv(this));


        // Listen for location data from the device
        _sender.on(LOCATION_REQ_EVENT, function(msg, reply = null) {

            // Reply is null when we are agent.on
            msg = (reply == null) ? msg : msg.data;

            if (typeof msg == "table" && "_location" in msg && msg._location != null) {
                // Grab the location payload
                _location = msg._location;
                if ("sendToConctr" in msg && msg.sendToConctr == true) {
                    // And send it to Conctr
                    if (DEBUG) server.log("Conctr: sending location to conctr");
                    sendData({});
                } else {
                    if (DEBUG) server.log("Conctr: cached location in agent");
                }
            }

        }.bindenv(this));

    }


    // 
    // Sets up endpoints for this agent
    // 
    // @param  {Object} rocky Instantiated instance of the Rocky class
    // 
    function _setupAgentApi(rocky) {
        if (DEBUG) server.log("Conctr: Set up agent endpoints");
        rocky.post("/conctr/claim", _handleClaimReq.bindenv(this));
    }


    // 
    // Handles device claim response from Conctr
    // 
    // @param  {Object} context Rocky context
    // 
    function _handleClaimReq(context) {

        if (!("consumer_jwt" in context.req.body)) {
            return context.send(401, { "error": "'consumer_jwt' is a required parameter" });
        }

        local url = _formClaimEndpointUrl();
        local payload = { "consumer_jwt": context.req.body.consumer_jwt };
        _requestWithRetry("post", url, _headers, http.jsonencode(payload), function(err, resp) {
            if (err != null) {
                return context.send(400, { "error": err });
            }
            if (DEBUG) server.log("Conctr: Device claimed");
            return context.send(200, resp);
        }.bindenv(this));

    }


    // 
    // Forms and returns the insert data API endpoint for the current device and Conctr application
    // 
    // @param  {String} appId
    // @param  {String} deviceId
    // @param  {String} region
    // @param  {String} env
    // @return {String} url endpoint that will accept the data payload
    // 
    function _formDataEndpointUrl() {

        // This is the temporary value of the data endpoint.
        return format("https://api.%s.conctr.com/data/apps/%s/devices/%s", _env, _app_id, _device_id);

        // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
        // return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s", region, env, appId, deviceId);
    }


    // 
    // Forms and returns the claim device API endpoint for the current device and Conctr application
    // 
    // @param  {String} appId
    // @param  {String} deviceId
    // @param  {String} region
    // @param  {String} env
    // @return {String} url endpoint that will accept the data payload
    // 
    function _formClaimEndpointUrl() {

        // This is the temporary value of the data endpoint.
        return format("https://api.%s.conctr.com/admin/apps/%s/devices/%s/claim", _env, _app_id, _device_id);

        // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
        // return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s/claim", region, env, appId, deviceId);
    }
}



APP_ID <- "ENTER_YOUR_APP_ID_HERE";
API_KEY <- "ENTER_YOUR_API_KEY_HERE";
MODEL <- "ENTER_YOUR_MODEL_HERE";

// mmOpts <- {
//     "retryInterval": 15,
//     "messageTimeout": 20,
//     "autoRetry": true,
//     "maxAutoRetries": 10,
// };

// mm <- MessageManager(mmOpts);
// rocky <- Rocky()

conctrOpts <- {
    // "messageManager": mm,
    // "rocky": rocky
}

conctr <- Conctr(APP_ID, API_KEY, MODEL, conctrOpts);
