// Squirrel class to interface with the Conctr platform (http://conctr.com)

// Copyright (c) 2016-2017 Mystic Pants Pty Ltd
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

const CONCTR_MIN_RECONNECT_TIME = 5;

class Conctr {

    static VERSION = "2.0.0";

    // change these to consts, name them in a namespace
    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";
    static AGENT_OPTS_EVENT = "conctr_agent_options";
    static SOURCE_DEVICE = "impdevice";
    static SOURCE_AGENT = "impagent";
    static MIN_TIME = 946684801; // Epoch timestamp for 00:01 AM 01/01/2000 (used for timestamp sanity check)
    static DEFAULT_LOC_INTERVAL = 3600; // One hour in seconds    

    // Request opt defaults
    static MAX_RETIES_DEFAULT = 3;
    static RETRIES_LIMIT = 10;
    static EXP_BACKOFF_DEFAULT = true;
    static RETRY_INTERVAL_DEFAULT = 5;
    static MAX_RETRY_INTERVAL = 60;


    _api_key = null;
    _app_id = null;
    _device_id = null;
    _region = null;
    _env = null;
    _model = null;
    _rocky = null;
    _dataApiEndpoint = null;
    _sender = null;

    // Location recording options
    _locationRecording = true;
    _locationSent = false;
    _locationTimeout = 0;
    _locationOnWakeReason = [];
    _sendLocInterval = 0;
    _sendLocOnce = false;

    _DEBUG = false;


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

        _app_id = appId;
        _api_key = (apiKey.find("api:") == null) ? "api:" + apiKey : apiKey;
        _model = model_ref;

        _env = ("env" in opts) ? opts.env : "staging";
        _region = ("region" in opts) ? opts.region : "us-west-2";
        _device_id = ("useAgentId" in opts && opts.useAgentId == true) ? split(http.agenturl(), "/").pop() : imp.configparams.deviceid;
        _rocky = ("rocky" in opts) ? opts.rocky : null;
        _sender = ("messageManager" in opts) ? opts.messageManager : device;

        // Setup the endpoint url
        _dataApiEndpoint = _formDataEndpointUrl(_app_id, _device_id, _region, _env);

        // Set up agen
        if (_rocky != null) {
            _setupAgentApi(_rocky);
        }

        // Set to location to defaults
        _setLocationOpts();

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
        _dataApiEndpoint = _formDataEndpointUrl(_app_id, _device_id, _region, _env);
        return this;
    }

    // 
    // returns current location opts
    // @return {Table} recording opts
    // 
    function getLocationOpts() {
        return {
            "sendLocOnce": _sendLocOnce,
            "sendLoc": _locationRecording,
            "sendLocInterval": _sendLocInterval,
            "locationOnWakeReason": _locationOnWakeReason
        }
    }


    // 
    // Sends data for persistance to Conctr
    // 
    // @param  {Table or Array} payload - Table or Array containing data to be persisted
    // @param  {Function (err,response)} callback - Callback function on http resp from Conctr
    // @return {Null}
    // @throws {Exception} -
    // 
    function sendData(payload, callback = null) {

        // If it's a table, make it an array
        if (typeof payload == "table") {
            payload = [payload];
        }

        local getLocation = true;

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

                if ("_location" in v) {

                    // We have a location, we don't need another one
                    getLocation = false;

                    if (!_locationSent) {
                        // If we have a new location the don't request another one unti the timeout
                        _locationSent = true;
                        _locationTimeout = time() + _sendLocInterval;
                    }

                }

            }

            // Send data to Conctr
            _postToConctr(payload, _dataApiEndpoint, callback);

            // Request the location
            if (getLocation) _getLocation();

        } else {
            // This is not valid input
            throw "Conctr: Payload must contain a table or an array of tables";
        }
    }


    // 
    // Takes a http request and retries request in specific scenarios like 429 or curl errors
    // @param  {Object}   req       Http request
    // @param  {Function} cb        Function to call on response. Takes args (err, resp)
    // @param  {Table}    opts      Table to specify retry opts. 
    // 
    function _requestWithRetry(method, url, headers, payload, opts = {}, cb = null) {
        // Currently only supporting GET and POST requests
        local HTTP_METHODS = ["GET", "POST"];

        if (opts == null || typeof opts == "function") {
            cb = opts;
            opts = {};
        }

        // Method must be upper case
        method = method.toupper();

        // Reject invalid methods
        if (HTTP_METHODS.find(method) == null) {
            throw "Invalid method, must be either POST or GET";
        }
        local req = http.request(method, url, headers, payload);
        // local req = http.post(url, headers, payload);
        req.sendasync(function(resp) {
            local wakeupTime = 0;
            // Get set opts
            local maxRetries = ("maxRetries" in opts && opts.maxRetries < RETRIES_LIMIT) ? opts.maxRetries : MAX_RETIES_DEFAULT;
            local expBackoff = ("expBackoff" in opts) ? opts.expBackoff : EXP_BACKOFF_DEFAULT;
            local retryInterval = ("retryInterval" in opts) ? opts.retryInterval : RETRY_INTERVAL_DEFAULT;

            // Get state opts
            local retryNum = ("_retryNum" in opts) ? opts._retryNum : 1;

            // set state 
            opts["_retryNum"] <- retryNum;

            if (resp.statuscode >= 200 && resp.statuscode <= 300) {
                // All good return
                if (cb) return cb(null, resp);
            } else if (resp.statuscode == 429 || resp.statuscode < 200 || resp.statuscode > 500) {
                // Want to retry these codes
                // Exponential back off or use a set interval
                if (expBackoff == true) {
                    wakeupTime = (math.pow(2, retryNum - 1) < MAX_RETRY_INTERVAL) ? math.pow(2, retryNum - 1) : MAX_RETRY_INTERVAL;
                } else {
                    wakeupTime = retryInterval;
                }
            } else {
                // Unrecoverable error, dont bother retrying let the user handle it.
                local error = "HTTP status code: " + resp.statuscode;
                if (cb) return cb(error, resp);
            }
            // Increment retry count for next round
            opts._retryNum++;
            // Max retries exceeded send the error to the user and end
            if (opts._retryNum > maxRetries) {
                local error = "HTTP status code: " + resp.statuscode;
                if (cb) return cb(error, resp);
            }

            // Retry in wakeupTime seconds
            if (wakeupTime) {
                imp.wakeup(wakeupTime, function() {
                    _requestWithRetry(method, url, headers, payload, opts, cb);
                }.bindenv(this));
            }
        }.bindenv(this));
    }


    // 
    // Posts data payload to Conctr.
    // @param  {Table}      payload    Data to be sent to Conctr
    // @param  {String}     endpoint   Url to post to
    // @param  {Function}   callback   Optional callback for result
    // 
    function _postToConctr(payload, endpoint, callback = null) {

        local headers = {};
        headers["Content-Type"] <- "application/json";
        headers["Authorization"] <- _api_key;

        // Send the payload(s) to the endpoint
        if (_DEBUG) {
            server.log(format("Conctr: sending to %s", endpoint));
            server.log(format("Conctr: %s", http.jsonencode(payload)));
        }

        _requestWithRetry("post", endpoint, headers, http.jsonencode(payload), callback);

    }


    // 
    // Sends a request to the device to send its current location (array of wifis) if conditions in current location sending opts are met. 
    // Note: device will send through using its internal sendData function, we will not wait and send location within the current payload.
    // 
    // 
    function _getLocation() {

        if (!_locationRecording) {

            if (_DEBUG) {
                server.log("Conctr: location recording is not enabled");
            }

            // not recording location 
            return;

        } else {

            // check new location scan conditions are met and search for proximal wifi networks
            local now = time();
            if ((_locationSent == false) || ((_sendLocOnce == false) && (_locationTimeout - now < 0))) {

                if (_DEBUG) {
                    server.log("Conctr: requesting location from device");
                }

                // Update timeout 
                _locationTimeout = time() + _sendLocInterval;

                // Update flagg to show we sent location.
                _locationSent = true;

                // Request location from device
                _sender.send(LOCATION_REQ_EVENT, "");

            } else {
                // Conditions for new location search (using wifi networks) not met
                return;
            }
        }
    }


    // 
    // Funtion to set location recording options
    // 
    // @param opts {Table} - location recording options 
    // {
    //   {Boolean}  sendLoc - Should location be sent with data
    //   {Integer}  sendLocInterval - Duration in seconds between location updates
    //   {Boolean}  sendLocOnce - Setting to true sends the location of the device only once when the device restarts 
    //  }
    // 
    // NOTE: sendLoc takes precedence over sendLocOnce. Meaning if sendLoc is set to false location will never be sent 
    //       with the data until this flag is changed.
    // 
    function _setLocationOpts(opts = {}) {

        if (_DEBUG) {
            server.log("Conctr: setting agent opts to: " + http.jsonencode(opts));
        }

        // Set default sendLocInterval between location updates
        _sendLocInterval = ("sendLocInterval" in opts && opts.sendLocInterval != null) ? opts.sendLocInterval : DEFAULT_LOC_INTERVAL;

        _sendLocOnce = ("sendLocOnce" in opts && opts.sendLocOnce != null) ? opts.sendLocOnce : false;
        _locationRecording = ("sendLoc" in opts && opts.sendLoc != null) ? opts.sendLoc : _locationRecording;
        _locationOnWakeReason = ("locationOnWakeReason" in opts && opts.locationOnWakeReason != null) ? opts.locationOnWakeReason : [];
        _locationSent = false;
    }

    // 
    // Sets up event listeners
    // 
    function _setupListeners() {
        // Listen for data events from the device
        _sender.on(DATA_EVENT, function(msg, reply = null) {
            // Reply is only null when we are not using messageManager
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
        // Listen for location recording opts from the device
        _sender.on(AGENT_OPTS_EVENT, function(msg, reply = null) {
            // Handle both agent.send and messageManager.send syntax
            msg = ("data" in msg) ? msg.data : msg;
            _setLocationOpts(msg);
        }.bindenv(this));
    }

    // 
    // Sets up endpoints for this agent
    // @param  {Object} rocky Instantiated instance of the Rocky class
    // 
    function _setupAgentApi(rocky) {
        server.log("Conctr: Set up agent endpoints");
        rocky.post("/conctr/claim", _handleClaimReq.bindenv(this));
    }

    // 
    // Handles device claim response from Conctr
    // @param  {Object} context Rocky context
    // 
    function _handleClaimReq(context) {

        if (!("consumer_jwt" in context.req.body)) {
            return _sendResponse(context, 401, { "error": "'consumer_jwt' is a required paramater for this request" });
        }

        _claimDevice(_app_id, _device_id, context.req.body.consumer_jwt, _region, _env, function(err, resp) {
            if (err != null) {
                return _sendResponse(context, 400, { "error": err });
            }
            server.log("Conctr: Device claimed");
            _sendResponse(context, 200, resp);
        });

    }

    // 
    // Send a response using rocky
    // 
    // @param  {Object}  context    Rocky context
    // @param  {Integer} code       Http status code to send 
    // @param  {Table}   obj        Data to send
    // 
    function _sendResponse(context, code, obj = {}) {
        context.send(code, obj)
    }

    // 
    // Claims a device for a consumer
    // 
    // @param  {String} appId
    // @param  {String} deviceId
    // @param  {String} consumer_jwt 
    // @param  {String} region
    // @param  {String} env
    // @param  {Function} cb
    // 
    function _claimDevice(appId, deviceId, consumer_jwt, region, env, cb = null) {

        local _claimEndpoint = format("https://api.%s.conctr.com/admin/apps/%s/devices/%s/claim", env, appId, deviceId);
        local payload = {};

        payload["consumer_jwt"] <- consumer_jwt;

        _postToConctr(payload, _claimEndpoint, cb)
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
    function _formDataEndpointUrl(appId, deviceId, region, env) {

        // This is the temporary value of the data endpoint.
        return format("https://api.%s.conctr.com/data/apps/%s/devices/%s", env, appId, deviceId);

        // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
        // return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s", region, env, appId, deviceId);
    }
}
