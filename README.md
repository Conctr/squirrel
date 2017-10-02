# Conctr

Conctr is a one stop platform that takes care of IoT complexity and lets you focus on what’s important.
The Conctr library allows you to easily integrate your agent and device code with the [Conctr IoT Platform](https://conctr.com). This library provides an easy way to send data to a Conctr application.

Click [here](https://api.staging.conctr.com/docs) for the full documentation of the Conctr API.

### Setup

To use this library you will need to:
- [Register](https://staging.conctr.com/signup) for an account on the Conctr platform.
- Create an application.
- Create a model within the application.

**To add this library to your project, add** `#require "conctr.agent.lib.nut:2.1.0"` **to the top of your agent code and add** `#require "conctr.device.lib.nut:2.1.0"` **to the top of your device code**

## Agent Class Usage
### Constructor: Conctr(*appId, apiKey, model[, options]*)

The constructor takes three required parameters: *appId, apiKey* and *model*. These details can be found by navigating into your application on the Conctr platform, selecting the *models* tab in the left side menu then clicking on the *example* button under the model you wish to use and chose the tab marked *Squirrel*. There are also some configuration options parameters that can be set.

| Key                       | Data Type | Required | Default Value | Description |
| ------------------------- | --------- | -------- | ------------- | ----------- |
| *appId*                   | String    | Yes      | N/A           | The ID used to uniquely identify the application |
| *apiKey*                  | String    | Yes      | N/A           | The API key that will be used to authenticate requests to Conctr |
| *model*                   | String    | Yes      | N/A           | The model created within the application that defines the data structure Conctr will expect from the device and will validate against |
| *options.useAgentId*      | Boolean   | No       | `false`       | Boolean flag used to determine whether to use the imp agent ID instead of the device ID as the primary identifier to Conctr for the data sent. See *setDeviceId()* to set a custom ID |
| *options.region*          | String    | No       | `"us-west-2"` |  Region of the instance to use. Currently only `"us-west-2"` is supported |
| *options.environment*     | String    | No       | `"staging"`   | Conctr environment to send data to |
| *options.protocol*     | `conctr.MQTT`| No       | `conctr.MQTT`   | Protocol to use to send message NOTE: Currently only MQTT is supported. |
| *options.rocky*           | Object    | No       | `null`        | An instantiated [Rocky](https://electricimp.com/docs/libraries/utilities/rocky/) object to be used for accepting claim requests via HTTPS |
| *options.messageManager*  | Object    | No       | `null`        | An instantiated [MessageManager](https://electricimp.com/docs/libraries/utilities/messagemanager/) or [Bullwinkle](https://electricimp.com/docs/libraries/utilities/bullwinkle/#bullwinkle) object to be used for guaranteeing message delivery from the device to the agent |


#### Example

```squirrel
#require "conctr.agent.lib.nut:2.1.0"

const API_KEY = "<YOUR API KEY>";
const APP_ID = "<YOUR AUTHENTICATION TOKEN>";
const MODEL = "<YOUR MODEL>";

conctr <- Conctr(APP_ID, API_KEY, MODEL);
```

## Agent Class Methods

### setDeviceId(*[deviceId]*)

The *setDeviceId()* method allows you the set the unique identifier that will be used by Conctr to identify the current device. 

**Note** Changing the device ID after data has already been sent at least once before will create a new device in Conctr. There will be no link between any data from this newly created device and the device data linked to the previous device ID.

| Key | Data Type | Required | Default Value | Description |
| --- | --------- | -------- | ------------- | ----------- |
| *deviceId* | String | No | `imp.configparams.deviceid` | Custom unique identifier that Conctr should store data against for this device |

#### Example

```squirrel
const CUSTOM_DEVICE_ID = "device-1";

conctr.setDeviceId(CUSTOM_DEVICE_ID);
```


### sendData(*payload[, callback]*)

The *sendData()* method sends a data payload to Conctr via the data ingeston endpoint.

| Key       | Data Type   | Required | Description |
| --------- | ----------- | -------- | ----------- |
| *payload* | Table/Array | Yes      | A table or array of tables containing the data to be sent to Conctr. The keys in the table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function   | No       | Function to be called on response from Conctr. The function should take two arguments, *error* and *response*. See table below for more info |

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error* | String | An error message if there was a problem, or null if successful |
| *response* | Object | An http response object |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        server.error("Failed to deliver to Conctr: " + error);
    } else {
        server.log("Data was successfully recieved by Conctr");
    }
}.bindenv(this));
```

### sendLocation(*[sendToConctr]*)

Retrieves the current location from the device and sends it to Conctr. This manual request ignores all location options.

| Key             | Data Type | Required | Default Value  | Description |
| --------------- | --------- | -------- | -------------- | ----------- |
| *sendToConctr*  | Boolean   | No       | True           | If true the location will be sent to Conctr. If false, it will be cached on the agent and sent with the next *sendData* invocation. |

#### Example

```squirrel
// Send location to conctr
conctr.sendLocation()
```

### publish(*topics, msg [, contentType] [, cb]*)

Publishes a message to a specific topic.

| Key             | Data Type | Required  | Description |
| --------------- | --------- | -------- | ----------- |
| *topics*  | Array   | Yes | List of Topics that message should be sent to. |
| *msg*  | Any   | Yes  |Data to be published. If anything other than a string is sent, it will be json encoded.|
| *contentType*  | String   | No       |Header specifying the content type of the msg. If a contentType is not provided the msg will be json encoded by default|
| *cb*  | Function   | No       | Function called on completion of publish request. |

#### Example

```squirrel
local msg = "Hello World";

// publish message to topic 'test'
conctr.publish(["test"], msg, function(err){

    if(err) server.error("Error"+err);
    else server.log("Successfully published message");

}.bindenv(this));
```

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error* | String | An error message if there was a problem, or null if successful |


### publishToDevice(*deviceIds, msg [, contentType] [, cb]*)
Publishes a message to a specific device.

| Key             | Data Type | Required  | Description |
| --------------- | --------- | -------- | ----------- |
| *deviceIds*  | Array   | Yes | List of device ids that the message should be sent to. |
| *msg*  | Any   | Yes  |Data to be published. If anything other than a string is sent, it will be json encoded.|
| *contentType*  | String   | No       |Header specifying the content type of the msg. If a contentType is not provided the msg will be json encoded by default|
| *cb*  | Function   | No       | Function called on completion of publish request. |

#### Example

```squirrel
local msg = "Hello World";

// publish message to this device
conctr.publishToDevice([imp.configparams.deviceid], msg, function(err){

    if(err) server.error("Error"+err);
    else server.log("Successfully published message");

}.bindenv(this));
```

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error* | String | An error message if there was a problem, or null if successful |


### subscribe(*[, topics][, cb]*)

Subscribe to a single/list of topics. NOTE: Calling subscribe again with a new set of topics will cancel any previous subscription requests.

| Key             | Data Type | Required | Default Value  | Description |
| --------------- | --------- | -------- | -------------- | ----------- |
| *topics*  | Array   | Yes       | Currently set device id           | List of Topics to subscribe to. |
| *cb*  | Function   | No       | True           | Function called on message receipt. |

#### Example

```squirrel
// Subscribe to default topics
conctr.subscribe(function(response){
    server.log("Got message:"+response.body)
}.bindenv(this))

// Publish in 2 seconds to ensure subscription is connected
imp.wakeup(2, function(){
    local msg = "Hello World";
    
    // publish message
    conctr.publishToDevice(imp.configparams.deviceid, msg, function(err){
    
        if(err) server.error("Error"+err);
        else server.error("Successfully published message");
        
    }.bindenv(this));
}.bindenv(this))

```

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *response* | Table | The http response received from Conctr. The message will be in `response.msg`. |

### unsubscribe()

unsubscribes from all topics.

#### Example

```squirrel
// Unsubscribe 
conctr.subscribe()
```


## Device Class Usage
**NOTE:** The device class is optional. It provides utility functions for interfacing with the agent class like automating the location sending process and provide queueing and error handling for sending data to Conctr.
### Constructor: Conctr(*[options]*)

Instantiates the Conctr device class. It takes an optional table used to set the location sending configuration of the class. See the *setLocationOpts()* below for details on the options keys.

| Key                      | Data Type     | Default Value  | Description |
| ------------------------ | ------------- | -------------- | ----------- |
| *options*                | Table         | null           | Options to be send to the `setLocationOpts()` function |

#### Example

```squirrel
conctr <- Conctr();
```

### setLocationOpts(*[options]*)

Allows you to override the current location options. Calling the method without any arguments sets location recording to defaults.


| Key                       | Data Type     | Default Value | Description |
| ------------------------- | ------------- | ------------- | ----------- |
| *options.locEnabled*      | Boolean       | `true`        | When enabled, location data will be automatically included with the data payload |
| *options.locInterval*     | Integer       | `3600`        | Duration in seconds between location updates |
| *options.locSendOnce*     | Boolean       | `false`       | Setting to `true` sends the location of the device only once, when the device boots if other criteria are met |
| *options.locWakeReasons*  | Array/Integer | `[WAKEREASON_NEW_SQUIRREL, WAKEREASON_POWER_ON]` | Only send location on one or more specific [wake reasons](https://electricimp.com/docs/api/hardware/wakereason/) |

#### Example

```squirrel
// change options to disable location sending altogether
local opts = { "locEnabled" : false };
conctr.setLocationOpts(opts);
```

### sendData(*payload[, callback]*)

The *sendData()* method is used to send a data payload to Conctr via the agent.

**Note** To recieve a response to the http request in the callback you must have passed in a value for the `options.messageManager` optional parameter in the device constructor. If not the callback will be called as soon as the payload has been sent to the agent.

| Key        | Data Type | Required | Description |
| ---------- | --------- | -------- | ----------- |
| *payload*  | Table     | Yes      | A table containing the data to be sent to Conctr. This keys in the table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function  | No       | Function to be called on response from Conctr. The function should take two arguments, *error* and *response*. When no error occurred, the first argument will be null. If a messageManager is in use then the callback will be fired when the Conctr platform has accepted/rejected the message. If no messageManager is in use then the callback will fire immediately upon sending. |

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error*            | String    | An error message if there was a problem, or null if successful |
| *response*       | Object    | An http response object if messageManager (or equivalent) is in use or an Imp [Send Error Code](https://electricimp.com/docs/api/agent/send/#senderror) if not  |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        server.error("Failed to deliver to Conctr: " + error);
    } else {
        server.log("Data was successfully send");
    }
}.bindenv(this));
```

### send(*ignoredString, payload*)
This is an alias for the sendData function above that uses the same format as agent.send("event name",payload)

| Key             | Data Type | Required | Description |
| --------------- | --------- | -------- | ----------- |
| *ignoredString* | String    | Yes      | A string that will be ignored, can be null |
| *payload*       | Table     | Yes      | A table containing the data to be sent to Conctr. This keys in the table should correspond to fields from the model and the keys should be of type specified in the model |

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.send("Send a Packet", currentTempAndPressure);
```

### sendLocation(*[sendToConctr]*)

Retrieves the current location from the device and sends it to Conctr. This manual request ignores all location options.

| Key             | Data Type | Required | Default Value  | Description |
| --------------- | --------- | -------- | -------------- | ----------- |
| *sendToConctr*  | Boolean   | No       | True           | If true the location will be sent to Conctr. If false, it will be cached on the agent and sent with the next *sendData* invocation. |

#### Example

```squirrel
// Send location to conctr
conctr.sendLocation()
```

## Claiming the device
A mobile application can claim the device on behalf a consumer, once they are logged into their account. The application should retrieve the `consumer_jwt` from the Conctr platform using the consumer OAuth process. The application should then POST to the device's agentURL, appending `/conctr/claim` to the end of the URL. The POST body should be a JSON table with the key `consumer_jwt`. The `Content-Type` header must be set to `application/json` for this to succeed.

## Troubleshooting
Both the agent and the device libraries have a DEBUG mode. Setting `DEBUG` to `true` will enable extra logging to help troubleshoot any issues you may run into. 

#### Example

```squirrel
// Enable debug mode
conctr.DEBUG = true;
```

In case of any questions/issues with the library please contact us at <support@conctr.com>
## License

The Conctr library is licensed under [MIT License](./LICENSE).