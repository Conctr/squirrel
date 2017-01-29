# Conctr

The Conctr library allows you to easily integrate your agent and device code with the [Conctr IoT Platform](https://conctr.com). This library provides an easy way to send data to a Conctr application. 

Click [here](https://api.staging.conctr.com/docs) for the full documentation of the Conctr API.

### Setup

To use this library you will need to:
- [Register](https://staging.conctr.com/signup) for an account on the Conctr platform.
- Create an application.
- Create a model within the application.

**To add this library to your project, add** `#require "conctr.agent.class.nut:1.1.0"` **to the top of your agent code and add** `#require "conctr.device.class.nut:1.1.0"` **to the top of your device code**

## Agent Class Usage

### Constructor: Conctr(*appId, apiKey, model[, options]*)

The constructor takes three required parameters: your application ID, API key and model. These details can be found by navigating into your application on the Conctr platform, selecting on the *Models* tab in the left side menu then click on the *Example* button under the model you wish to use and chose the tab marked *Squirrel*. There are also three optional parameters: the region to be used (defaults to `"us-west-2"`), the environment (defaults to `"staging"`) and the *useAgentId* (defaults to `false`) which can be passed in within a table as the *Options* parameter.

| Key | Data Type | Required | Default Value | Description |
| --- | --------- | -------- | ------------- | ----------- |
| *appId* | String | Yes | N/A | The ID used to uniquely identify the application |
| *apiKey* | String | Yes  | N/A | The API key that will be used to authenticate requests to Conctr |
| *model* | String | Yes  | N/A | The model created within the application that defines the data structure Conctr will expect from the device and will validate against |
| *options.useAgentId* | Boolean | No | false | Flag used to determine whether the imp agent ID or device ID should be used as the primary identifier to Conctr for the data sent. See *setDeviceId()* to set a custom ID |
| *options.region* | String | No | `"us-west-2"` |  Region of the instance to use |
| *options.environment* | String | No | `"staging"` | Conctr environment to send data to |

#### Example

```squirrel
#require "conctr.agent.class.nut:1.1.0"

const API_KEY = "<YOUR API KEY>";
const APP_ID = "<YOUR AUTHENTICATION TOKEN>";
const MODEL = "<YOUR MODEL>";

conctr <- Conctr(APP_ID, API_KEY, MODEL);
```

## Agent Class Methods

### setDeviceId(*[deviceId]*)

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

The *sendData()* method sends a data payload to Conctr via the data ingeston endpoint. It is called by the data event listener when the device sends data using the Conctr device class. It can also be used directly to send data to Conctr via the agent alone.

| Key | Data Type | Required | Description |
| --- | --------- | -------- | ----------- |
| *payload* | Table | Yes | A table containing the data to be sent to Conctr. The keys in the table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function | No | Function to be called on response from Conctr. The function should take two arguements, *error* and *response*. When no error occurred, the first arguement will be null |

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

### Constructor: Conctr(*[options]*)

Instantiates the Conctr device class. It takes an optional table, *options*, to override default behaviour. *options* may contain any of the following keys:

| Key | Data Type | Default Value | Description |
| --- | --------- | ------------- | ----------- |
| *options.sendLoc* | Boolean | `true` | When enabled, location data will be automatically included with the data payload |
| *options.sendLocInterval* | Integer | 3600 | Duration in seconds between location updates |
| *options.sendLocOnce* | Boolean | `false` | Setting to `true` sends the location of the device only once, when the device restarts |
 
**Note** The *sendLoc* option takes precedence over *sendLocOnce*, ie. if *sendLoc* is set to `false` the device’s location will never be sent with the data until this flag is changed, even if *sendLocOnce* is set to `true`.
 
#### Example

```squirrel
#require "conctr.device.class.nut:1.1.0"

// Options to override default location interval duration of 1 hour to 1 minute
local opts = { "sendLocInterval" : 60 };
conctr <- Conctr(opts);
```
 
### setOpts(*[options]*)

This method overrides the default options of the Conctr device class. Takes an optional table *options*. Any keys *(see Constructor, above)* that aren’t included will be set to their default values.

### sendData(*payload[, callback]*)

The *sendData()* method is used to send a data payload to Conctr. This function emits the payload to as a "conctr_data" event. The agents sendData() function is called by the corresponding event listener and the payload is sent to Conctr via the data ingeston endpoint. 

| Key | Data Type | Required | Description |
| --- | --------- | -------- | ----------- |
| *payload* | Table | Yes | A table containing the data to be sent to Conctr. This keys in the table should correspond to fields from the model and the keys should be of type specified in the model |
| *callback* | Function | No | Function to be called on response from Conctr. The function should take two arguements, *error* and *response*. When no error occurred, the first arguement will be null |

#### Example

```squirrel
local currentTempAndPressure = { "temperature" : 29, "pressure" : 1032};

conctr.sendData(currentTempAndPressure, function(error, response) {
    if (error) {
        server.error("Failed to deliver to Conctr: " + error);
    } else {
        server.log("Data was successfully recieved from the device by Conctr");
    }
}.bindenv(this));
```

## License

The Conctr library is licensed under [MIT License](./LICENSE).