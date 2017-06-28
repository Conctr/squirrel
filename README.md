# Conctr

The Conctr library allows you to easily integrate your agent and device code with the [Conctr IoT Platform](https://conctr.com). This library provides an easy way to send data to a Conctr application.

Click [here](https://api.staging.conctr.com/docs) for the full documentation of the Conctr API.

**This library is supported by [Mystic Pants](https://mysticpants.com/) not by Electric Imp. If you have questions about or issues with the library, please contact Mystic Pants at [support@conctr.com](mailto:support@conctr.com)**

### Setup

To use this library you will need to:

- [Register](https://staging.conctr.com/signup) for an account on the Conctr platform.
- Create an application.
- Create a model within the application.

#### Example

```squirrel
// Enable debug mode
conctr.DEBUG = true;
```

**To add this library to your project, add** `#require "conctr.agent.lib.nut:2.0.0"` **to the top of your agent code and add** `#require "conctr.device.lib.nut:2.0.0"` **to the top of your device code**

## Agent Class Usage

### Constructor: Conctr(*appId, apiKey, model[, options]*)

The constructor takes three required parameters: *appId, apiKey* and *model*. These details can be found by navigating into your application on the Conctr platform, selecting the ‘models’ tab in the left-side menu then clicking on the ‘example’ button under the model you wish to use and chose the tab marked ‘Squirrel’. 

| Key                       | Data Type | Required | Default Value | Description |
| ------------------------- | --------- | -------- | ------------- | ----------- |
| *appId*                   | String    | Yes      | N/A           | The ID used to uniquely identify the application |
| *apiKey*                  | String    | Yes      | N/A           | The API key that will be used to authenticate requests to Conctr |
| *model*                   | String    | Yes      | N/A           | The model created within the application that defines the data structure Conctr will expect from the device and will validate against |

There are also some configuration options parameters that can be set if you wish:

| Key                       | Data Type | Required | Default Value | Description |
| ------------------------- | --------- | -------- | ------------- | ----------- |
| *options.useAgentId*      | Boolean   | No       | `false`       | Boolean flag used to determine whether to use the imp agent ID instead of the device ID as the primary identifier to Conctr for the data sent. See *setDeviceId()* to set a custom ID |
| *options.region*          | String    | No       | `"us-west-2"` |  Region of the instance to use. Currently only `"us-west-2"` is supported |
| *options.environment*     | String    | No       | `"staging"`   | Conctr environment to send data to |
| *options.rocky*           | Object    | No       | `null`        | An instantiated [Rocky](https://electricimp.com/docs/libraries/utilities/rocky/) object to be used for accepting claim requests via HTTPS |
| *options.messageManager*  | Object    | No       | `null`        | An instantiated [MessageManager](https://electricimp.com/docs/libraries/utilities/messagemanager/) or [Bullwinkle](https://electricimp.com/docs/libraries/utilities/bullwinkle/#bullwinkle) object to be used for guaranteeing message delivery from the device to the agent |

#### Example

```squirrel
#require "conctr.agent.lib.nut:2.0.0"

const API_KEY = "<YOUR API KEY>";
const APP_ID = "<YOUR AUTHENTICATION TOKEN>";
const MODEL = "<YOUR MODEL>";

conctr <- Conctr(APP_ID, API_KEY, MODEL);
```

## Agent Class Methods

### setDeviceId(*deviceId*)

The *setDeviceId()* allows you the set the unique identifier that will be used by Conctr to identify the current device.

**Note** Changing the device ID after data has already been set previously will create a new device in Conctr. There will be no link between any data from this newly created device and the device data linked to the previous device ID.

| Key | Data Type | Required | Default Value | Description |
| --- | --------- | -------- | ------------- | ----------- |
| *deviceId* | String | No | `"imp.configparams.deviceid"` | Custom unique identifier that Conctr should store data against for this device |

#### Example

```squirrel
const CUSTOM_DEVICE_ID = "device-1";

conctr.setDeviceId(CUSTOM_DEVICE_ID);
```

### sendData(*payload[, callback]*)

The *sendData()* method sends a data payload to Conctr via the data ingestion endpoint. It is called by the data event listener when the device sends data using the Conctr device class. It can also be used directly to send data to Conctr via the agent alone.

| Key       | Data Type   | Required | Description |
| --------- | ----------- | -------- | ----------- |
| *payload* | Table/Array | Yes      | A table or array of tables containing the data to be sent to Conctr. The keys in this table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function   | No       | Function to be called on response from Conctr. The function should take two arguments, *error* and *response*. See table below for more info |

The callback will be called with the following arguments:

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error* | String | An error message if there was a problem, or `null` if successful |
| *response* | Object | An imp API *httpresponse* object |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        // Handle error
    } else {
        server.log("Data was successfully received by Conctr");
    }
}.bindenv(this));
```

### sendLocation(*[sendToConctr]*)

Retrieves the current location from the device and sends it to Conctr. This manual request ignores all location options.

| Key             | Data Type | Required | Default Value  | Description |
| --------------- | --------- | -------- | -------------- | ----------- |
| *sendToConctr*  | Boolean   | No       | `true`           | If `true` the location will be sent to Conctr. If `false`, it will be cached on the agent and sent with the next *sendData()* invocation |

#### Example

```squirrel
// Send location to conctr
conctr.sendLocation();
```

## Device Class Usage

The device class is optional. It provides utility functions for interfacing with the agent class, such as automating the location-sending process, and provide queueing and error handling for sending data to Conctr.

### Constructor: Conctr(*[options]*)

Instantiates the Conctr device class. It takes an optional table used to set the location sending configuration of the class. See the *setLocationOpts()* below for details on the options keys.

| Key                      | Data Type     | Default Value  | Description |
| ------------------------ | ------------- | -------------- | ----------- |
| *options*                | Table         | `null`           | Options to be send to the `setLocationOpts()` function |

#### Example

```squirrel
conctr <- Conctr();
```

### setLocationOpts(*[options]*)

Allows you to override the current location options. Calling the method without any arguments sets location recording to defaults. The table passed into *options* can contain any of the following keys:

| Key                       | Data Type     | Default Value | Description |
| ------------------------- | ------------- | ------------- | ----------- |
| *locEnabled*      | Boolean       | `true`        | When enabled, location data will be automatically included with the data payload |
| *locInterval*     | Integer       | `3600`        | Duration in seconds between location updates |
| *locSendOnce*     | Boolean       | `false`       | Setting to `true` sends the location of the device only once, when the device boots if other criteria are met |
| *locWakeReasons*  | Array/Integer | `[WAKEREASON_NEW_SQUIRREL, WAKEREASON_POWER_ON]` | Only send location on one or more specific [wake reasons](https://electricimp.com/docs/api/hardware/wakereason/) |

#### Example

```squirrel
// Change options to disable location sending altogether
local opts = { "locEnabled" : false };
conctr.setLocationOpts(opts);
```

### sendData(*payload[, callback]*)

The *sendData()* method is used to send a data payload to Conctr via the agent.

**Note** To receive a response to the HTTP request in the callback you must have passed in a value for the *options.messageManager* optional parameter in the agent constructor. If not, the callback will be called as soon as the payload has been sent to the agent.

| Key        | Data Type | Required | Description |
| ---------- | --------- | -------- | ----------- |
| *payload*  | Table     | Yes      | A table containing the data to be sent to Conctr. The keys in this table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function  | No       | Function to be called on response from Conctr. The function should take two arguments, *error* and *response*. When no error occurred, the first argument will be `null`. If an instance of *MessageManager* is in use, the callback will be fired when the Conctr platform has accepted/rejected the message. If no *MessageManager* is in use, the callback will fire immediately upon sending |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        // Handle error
    } else {
        server.log("Data was successfully received from the device by Conctr");
    }
}.bindenv(this));
```

### send(*ignoredString, payload*)

This is an alias for the *sendData()* method above that uses the same format as the impa APO method *agent.send()*, ie. `agent,send("event name", payload);`.

| Key             | Data Type | Required | Description |
| --------------- | --------- | -------- | ----------- |
| *ignoredString* | String    | Yes      | A string that will be ignored, can be `null` |
| *payload*       | Table     | Yes      | A table containing the data to be sent to Conctr. The keys in this table should correspond to fields from the model and the keys should be of type specified in the model |

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
conctr.sendLocation();
```

## Claiming the device

A mobile application can claim the device on behalf of a consumer, once they are logged into their account. The application should retrieve the *consumer_jwt* value from the Conctr platform using the consumer OAuth process. The application should then POST to the device’s agent URL, appending `/conctr/claim` to the end of the URL. The POST body should be a JSON table with the key *consumer_jwt*. The `Content-Type` header must be set to `application/json` for this to succeed.

## Troubleshooting

Both the agent and the device libraries have a debug mode. Setting a Conctr instance’s *DEBUG* property to `true` will enable extra logging to help troubleshoot any issues you may encounter. 

## License

The Conctr library is licensed under [MIT License](./LICENSE).
