# Test Instructions

The instructions will show you how to set up the tests for the Conctr.

## Setting up a Conctr model
1. Go to [Conctr](https://staging.conctr.com/signin) if you have an account login otherwise sign up
1. You should be at Dashboard if not please navigate to the Dashboard and click "Create Application"
1. Enter "Test" in the Application Name box then press the "Create" button
1. You will be returned to the Dashboard. Click on the "Test" application
1. Click on the "Models" tab
1. Click on the "Create Model" button
1. In the model Name box write "testModel"
1. In the "Add Standard Field" dropdown box select temperature
1. Click "Create Model"
1. You should be at View Models tab if not please navigate to the View Models Tabs
1. Click "Example" next your "testModel" model
1. In the Payload Example Click the "Squirrel" tab
1. In the agent section note you APP_ID, API_KEY and MODEL   

Within the agent.test.nut there are 3 constants that need to be configured.

Parameter      | Description
-------------- | -----------
APP_ID         | Your Conctr application id       
API_KEY        | Your Conctr api key
MODEL          | Your Conctr Application model name


# License

 The Conctr library is licensed under the [MIT License](../LICENSE).
