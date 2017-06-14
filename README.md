# Conctr

Conctr is a one stop platform that takes care of IoT complexity and lets you focus on what’s important.
The Conctr library allows you to easily integrate your agent and device code with the [Conctr IoT Platform](https://conctr.com). This library provides an easy way to send data to a Conctr application.

Click [here](https://api.staging.conctr.com/docs) for the full documentation of the Conctr API.

### Setup

To use this library you will need to:
- [Register](https://staging.conctr.com/signup) for an account on the Conctr platform.
- Create an application.
- Create a model within the application.

**To add this library to your project, add** `#require "conctr.agent.lib.nut:2.0.0"` **to the top of your agent code and add** `#require "conctr.device.lib.nut:2.0.0"` **to the top of your device code**

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
| *options.rocky*           | Object    | No       | `null`        | An instantiated [Rocky](https://electricimp.com/docs/libraries/utilities/rocky/) object |
| *options.messageManager*  | Object    | No       | `null`        | An instantiated [MessageManager](https://electricimp.com/docs/libraries/utilities/messagemanager/) or [Bullwinkle](https://electricimp.com/docs/libraries/utilities/bullwinkle/#bullwinkle) object |


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
| *callback* | Function   | No       | Function to be called on response from Conctr. The function should take two arguements, *error* and *response*. See table below for more info |

| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error* | String | An error message if there was a problem, or null if successful |
| *connection* | Object | An http response object |

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

## Device Class Usage
**NOTE:** The device class is optional. It provides utility functions for interfacing with the agent class like automating the location sending process and provide queueing and error handling for sending data to conctr.
### Constructor: Conctr(*[options]*)

Instantiates the Conctr device class. It takes an optional table used to set the configuration of the class. *options* may contain any of the following keys:

| Key                      | Data Type     | Default Value  | Description |
| ------------------------ | ------------- | -------------- | ----------- |
| *options.locEnabled*     | Boolean       | `true`         | When enabled, location data will be automatically included with the data payload |
| *options.locInterval*    | Integer       | `3600`         | Duration in seconds between location updates |
| *options.locSendOnce*    | Boolean       | `true`         | Setting to `true` sends the location of the device only once |
| *options.locWakeReasons* | Array/Integer | `[WAKEREASON_NEW_SQUIRREL, WAKEREASON_POWER_ON]` | Send location on a specific [wake reason](https://electricimp.com/docs/api/hardware/wakereason/) only |
| *options.messageManager* | Object        |`agent`         | An instantiated [MessageManager](https://electricimp.com/docs/libraries/utilities/messagemanager/), [Bullwinkle](https://electricimp.com/docs/libraries/utilities/bullwinkle/#bullwinkle) or [ImpPager](https://github.com/electricimp/ReplayMessenger) object |

### setLocationOpts(*[options]*)

Allows you to override the current location options. Calling the method without any arguements sets location recording to defaults.


| Key                       | Data Type     | Default Value | Description |
| ------------------------- | ------------- | ------------- | ----------- |
| *options.locEnabled*      | Boolean       | `true`        | When enabled, location data will be automatically included with the data payload |
| *options.locInterval*     | Integer       | `3600`        | Duration in seconds between location updates |
| *options.locSendOnce*     | Boolean       | `false`       | Setting to `true` sends the location of the device only once, when the device boots if other criteria are met |
| *options.locWakeReasons*  | Array/Integer | `[WAKEREASON_NEW_SQUIRREL, WAKEREASON_POWER_ON]` | Send location on a specific [wake reason](https://electricimp.com/docs/api/hardware/wakereason/) only |

#### Example

```squirrel
// change options to disable location sending altogether
local opts = {
    "locEnabled" : false,
    };
conctr.setLocationOpts(opts)
```

### sendData(*payload[, callback]*)

The *sendData()* method is used to send a data payload to Conctr via the agent.

**Note** To recieve a response to the http request in the callback you must have passed in a value for the `options.messageManager` optional parameter in the device constructor. If not the callback will be called as soon as the payload has been sent to the agent.

| Key        | Data Type | Required | Description |
| ---------- | --------- | -------- | ----------- |
| *payload*  | Table     | Yes      | A table containing the data to be sent to Conctr. This keys in the table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function  | No       | Function to be called on response from Conctr. The function should take two arguements, *error* and *response*. When no error occurred, the first arguement will be null |


| Callback Parameter | Data Type | Description |
| ------------------ | --------- | ----------- |
| *error*            | String    | An error message if there was a problem, or null if successful |
| *connection*       | Object    | An http response object or null if messageManager or equivalent not passed in |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        server.error("Failed to deliver to Conctr: " + error);
    } else {
        server.log("Data was successfully received from the device by Conctr");
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

## License

The Conctr library is licensed under [MIT License](./LICENSE).
