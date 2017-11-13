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

    static VERSION = "2.1.0";

    static DATA_EVENT = "conctr_data";
    static LOCATION_REQ_EVENT = "conctr_get_location";
    static SOURCE_DEVICE = "impdevice";
    static SOURCE_AGENT = "impagent";
    static MIN_TIME = 946684801; // Epoch timestamp for 00:01 AM 01/01/2000 (used for timestamp sanity check)
    static MIN_RECONNECT_TIME = 5;
    static CONN_TIMEOUT=3590;

    // Request opt defaults
    static MAX_RETIES_DEFAULT = 3;
    static RETRIES_LIMIT = 10;
    static EXP_BACKOFF_DEFAULT = true;
    static RETRY_INTERVAL_DEFAULT = 5;
    static MAX_RETRY_INTERVAL = 60;

    // PUB/SUB consts
    static AMQP = "amqp";
    static MQTT = "mqtt";
    static STREAM_TERMINATOR = "\r\n";

    // protocol vars
    _protocol = null;
    _msgQueue = null;

    // Pending queue status
    _pendingReqs = null;
    _pendingTimer = null;
    _pollingReq = null;
    _wakeAndSubTimer = null;

    // Pub/sub endpoints
    _pubSubEndpoints = null;

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

    // Local testing using ngrok
    _LOCAL_MODE = false;
    _ngrokID = null;


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

        // pubsub debug opts
        _LOCAL_MODE = ("useLocalMode" in opts) ? opts.useLocalMode : false;
        _ngrokID = ("ngrokid" in opts) ? opts.ngrokid : null;

        _protocol = ("protocol" in opts) ? opts.protocol : MQTT;
        _pubSubEndpoints = _formPubSubEndpointUrls(_app_id, _device_id, _region, _env);

        // Set up msg queue
        _msgQueue = [];

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
    // Sets the protocal that should be used 
    // 
    // @param   {String}    protocol Either amqp or mqtt
    // @return  {String}    current protocal after change
    // 
    function setProtocol(protocol) {
        if (protocol == MQTT) {
            _protocol = protocol;
        } else {
            server.error(protocol + " is not a valid protocol.");
        }
        _pubSubEndpoints = _formPubSubEndpointUrls(_app_id, _api_key, _device_id, _region, _env);
        return _protocol
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
    // Publishes a message to a specific topic.
    // 
    // @param  {String/Array}   topics      List of Topics that message should be sent to
    // @param  {[type]}         msg         Data to be sent to be published
    // @param  {[String}        contentType Header specifying the content type of the msg
    // @param  {Function}       cb          Function called on completion of publish request
    // 
    function publish(topics, msg, contentType = null, cb = null) {
        local relativeUrl = "";
        _publish(relativeUrl, { "topics": topics }, msg, contentType, cb);

    }


    // 
    // Publishes a message to a specific device.
    // @param  {String/Array}   deviceId     Device id(s) the message should be sent to
    // @param  {[type]}         msg          Data to be sent to be published
    // @param  {[type]}         contentType  Header specifying the content type of the msg
    // @param  {Function}       cb           Function called on completion of publish request
    // 
    function publishToDevice(deviceIds, msg, contentType = null, cb = null) {
        local relativeUrl = "/dev/";
        _publish(relativeUrl, { "device_ids": deviceIds }, msg, contentType, cb);
    }


    // 
    // Subscribe to a single/list of topics
    // 
    // @param  {Array/String}   topics String or Array of string topic names to subscribe to
    // @param  {Function}       cb     Function called on receipt of data
    // 
    function subscribe(topics = [], cb = null) {

        // Check if only callback is subscribed to
        if (typeof topics == "function") {
            cb = topics;
            topics = [];
        }

        if (cb == null) {
            throw "Conctr: callback to subscribe is a required parameter";
        }

        // If no topics to subscribe to found, subscribe to this devices id
        if (topics.len() == 0) {
            topics = ["dev/" + _device_id];
        }

        if (typeof topics != "array") {
            topics = [topics];
        }

        local action = "subscribe";
        local headers = {};
        local payload = {};
        local chunks = "";
        local contentLength = null;
        local reqTime = time();


        // Http streaming callback
        local _streamCb = function(chunk) {

            // User called unsubscribe. Close connection.
            if (_pollingReq == null) return;

            // accumulate chuncks till we get a full msg
            chunks += chunk;

            // Check whether we have received the content length yet (sent as first line of msg)
            if (contentLength == null) {
                // Sweet, we want to extract it out, itll be
                // chilling just before the /r/n lets find it
                local eos = chunks.find(STREAM_TERMINATOR);
                // Got it! 
                if (eos != null) {
                    // Pull it out
                    contentLength = chunks.slice(0, eos);
                    try {
                        contentLength = contentLength.tointeger();
                    } catch (e) {
                        server.error(e);
                    }

                    // Leave the rest of the msg
                    chunks = chunks.slice(eos + STREAM_TERMINATOR.len());
                }
            }

            // Handle incorrect message i.e. 502 html returned
            if(typeof contentLength == "string"){
                server.error("Got invalid response from conctr: "+chunks)
                return subscribe(topics,cb);
            }

            if (contentLength != null && chunks.len() >= contentLength) {
                // Got a full msg, process it!
                _processData(chunks.slice(0, contentLength), cb);

                // Get any partial chunks if any and keep waiting for the end of new message
                chunks = chunks.slice(contentLength + STREAM_TERMINATOR.len());
                contentLength = null;
            }
        }

        // http done callback
        local _doneCb = function(resp) {

            // We dont allow non chunked requests. So if we recieve a message in this func
            // it is the last message of the steam and may contain the last chunk
            if (!(resp.body == null || resp.body == "")) {
                _streamCb(resp.body);
            }

            local wakeupTime = 0;
            local reconnect = function() {
                subscribe(topics, cb);
            }

            if (resp.statuscode >= 200 && resp.statuscode <= 300) {
                // wake up time is 0
            } else if (resp.statuscode == 429) {
                wakeupTime = 1;
            } else if (resp.statuscode == 401) {
                throw "Conctr: Authentication failed";
            } else {
                local conTime = time() - reqTime;
                if (conTime < MIN_RECONNECT_TIME) {
                    wakeupTime = MIN_RECONNECT_TIME - conTime;
                }
                server.error("Conctr: Subscribe failed with error code " + resp.statuscode + ". Retrying in " + wakeupTime + " seconds");
            }

            // Reconnect in a bit or now based on disconnection reason
            imp.wakeup(wakeupTime, reconnect.bindenv(this));
        };

        headers["Content-Type"] <- "application/json";
        headers["Connection"] <- "keep-alive";
        headers["Transfer-encoding"] <- "chunked";
        headers["Authorization"] <- _headers["Authorization"];
        payload["topics"] <- topics;

        // Check there isnt a current connection, close it if there is.
        if (_pollingReq) _pollingReq.cancel();
        if(_wakeAndSubTimer) imp.cancelwakeup(_wakeAndSubTimer);

        _wakeAndSubTimer = imp.wakeup(CONN_TIMEOUT, function(){
                subscribe(topics,cb);
            }.bindenv(this))

        _pollingReq = http.post(_pubSubEndpoints[action], headers, http.jsonencode(payload));

        // Call callback directly when not chucked response, handle chuncking in second arg to sendAsync
        _pollingReq.sendasync(_doneCb.bindenv(this), _streamCb.bindenv(this));
    }


    // 
    // Unsubscribe to a single/list of topics
    // 
    function unsubscribe() {
        if (_pollingReq) _pollingReq.cancel();
        if(_wakeAndSubTimer) imp.cancelwakeup(_wakeAndSubTimer);
        _pollingReq = null;
    }


    // 
    // Http GET request with conctr auth injected in automatically
    // 
    // @param  {String}     url       Url to hit
    // @param  {Table}      headers   Additional headers pass
    // @param  {Function}   cb        cb called with result
    // 
    function get(url, headers = {}, cb = null) {
        if (typeof headers == "function") {
            cb = headers;
            headers = {};
        }

        headers["Authorization"] <- _headers["Authorization"];

        _requestWithRetry("GET", url, headers, "", function(err, resp) {
            if (err) cb(err,null);
            else cb(null, resp);
        }.bindenv(this));
    }


    // 
    // Http POST request with conctr auth injected in automatically
    // 
    // @param  {String}     url       Url to hit
    // @param  {Table}      payload   Payload to send
    // @param  {Table}      headers   Additional headers pass
    // @param  {Function}   cb        cb called with result
    // 
    function post(url, payload, headers = {}, cb = null) {
        if (typeof headers == "function") {
            cb = headers;
            headers = {};
        }

        if (typeof payload != "string") {
            payload = http.jsonencode(payload);
        }

        headers["Authorization"] <- _headers["Authorization"];

        _requestWithRetry("POST", url, headers, payload, function(err, resp) {
            if (err) cb(err);
            else cb(resp);
        }.bindenv(this));
    }



    // 
    // Publishes a message to the correct url.
    // @param  {String}   relativeUrl   relative url that the message should be posted to
    // @param  {Table}    receivers     Object with either device_ids or topics
    // @param  {[type]}   msg           Data to be sent to be published
    // @param  {[type]}   contentType   Header specifying the content type of the msg
    // @param  {Function} cb            Function called on completion of publish request
    // 
    function _publish(relativeUrl, receivers, msg, contentType = null, cb = null) {
        local action = "publish";
        local headers = {};
        local reqTime = time();
        local payload = { "msg": msg };

        if (typeof contentType == "function") {
            cb = contentType;
            contentType = null;
        }

        if ("topics" in receivers) {
            payload["topics"] <- receivers.topics;
        } else if ("device_ids" in receivers) {
            payload["device_ids"] <- receivers.device_ids;
        }

        if (contentType != null) {
            payload["content-type"] <- contentType;
        }

        _requestWithRetry("post", _pubSubEndpoints[action] + relativeUrl, _headers, http.jsonencode(payload), cb);
    }


    // 
    // Processes a chunk of data received via poll
    // @param  {String}   chunks String chunk of data recieved from polling request
    // @param  {Function} cb     callback to call if a full message was found within chunk
    // 
    function _processData(chunks, cb) {
        local response = _decode(chunks);
        imp.wakeup(0, function() {
            cb(response);
        }.bindenv(this));
        return;
    }


    // 
    // Takes an encoded msg which contains headers and content and decodes it
    // @param  {String}  encodedMsg http encoded message
    // @return {Table}   decoded Table with keys headers and body
    // 
    function _decode(encodedMsg) {
        local decoded = {};
        local headerEnd = encodedMsg.find("\n\n");
        local encodedHeader = encodedMsg.slice(0, headerEnd);
        // get index of header end plus the two new line chars
        local encodedBody = encodedMsg.slice(headerEnd + "\n\n".len());
        decoded.headers <- _parseHeaders(encodedHeader);
        decoded.body <- _parseBody(encodedBody, decoded.headers);
        return decoded;
    }


    // 
    // Takes a http encoded string of header key value pairs and converts to a table of
    // @param  {String} encodedHeader http encoded string of header key value pairs
    // @return {Table}  Table of header key value pairs 
    // 
    function _parseHeaders(encodedHeader) {
        local headerArr = split(encodedHeader, "\n");
        local headers = {}
        foreach (i, header in headerArr) {
            local keyValArr = split(header, ":");
            keyValArr[0] = strip(keyValArr[0]);
            if (keyValArr[0].len() > 0) {
                headers[keyValArr[0].tolower()] <- strip(keyValArr[1]);
            }
        }
        return headers;
    }


    // 
    // Takes a http encoded string of the message body and a list of headers and parses the body based on Content-Type header.
    // @param  {String}   encodedBody http encoded string of header key value pairs
    // @param  {String}   encodedBody http encoded string of header key value pairs
    // @return {Table}    Table of header key value pairs 
    // 
    function _parseBody(encodedBody, headers) {

        local body = encodedBody;
        if ("content-type" in headers && headers["content-type"] == "application/json") {
            try {
                body = http.jsondecode(encodedBody);
            } catch (e) {
                server.error(e)
            }
        }
        return body;
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
            throw "Conctr: Invalid method, must be either POST or GET";
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
        return (_LOCAL_MODE == true) ? format("http://%s.ngrok.io/data/apps/%s/devices/%s", _ngrokID, _app_id, _device_id) : format("https://api.%s.conctr.com/data/apps/%s/devices/%s", _env, _app_id, _device_id);

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



    // 
    // Forms and returns the insert data API endpoint for the current device and Conctr application
    // 
    // @param  {String} appId
    // @param  {String} deviceId
    // @param  {String} region
    // @param  {String} env
    // @return {String} url endpoint that will accept the data payload
    // 
    function _formPubSubEndpointUrls(appId, deviceId, region, env) {

        local pubSubActions = ["subscribe", "publish"];
        local endpoints = {};
        foreach (idx, action in pubSubActions) {
            if (!_LOCAL_MODE) {
                endpoints[action] <- format("https://api.%s.conctr.com/%s/%s/%s", env, _protocol, appId, action);
            } else {
                server.log("CONCTR: Warning using localmode");
                endpoints[action] <- format("http://%s.ngrok.io/%s/%s/%s", _ngrokID, _protocol, appId, action);
            }
            // The data endpoint is made up of a region (e.g. us-west-2), an environment (production/core, staging, dev), an appId and a deviceId.
            // return format("https://api.%s.%s.conctr.com/data/apps/%s/devices/%s", region, env, appId, deviceId);
        }
        return endpoints;
    }


    function _useLocalmode(ngrokid) {
        _ngrokID = ngrokid;
        _LOCAL_MODE = true;
        _formPubSubEndpointUrls(_app_id, _device_id, _region, _env);
    }
}