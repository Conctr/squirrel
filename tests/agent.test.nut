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

// http status codes
const CONCTR_TEST_HTTP_CREATED = 201;
const CONCTR_TEST_HTTP_UNAUTHORIZED = 401;
const CONCTR_TEST_HTTP_BAD_REQUEST = 400;


class AgentTestCase extends ImpTestCase {

    function setUp() {
        return "Hi from #{__FILE__}!";
    }


    // test the sendData function sent correctly checks for a http created response
    function testSendData() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = {
                "temperature": 15,
                "humidity": 80,
            };

            // Send the payload
            conctr.sendData(payload, function(err, resp) {
                if (err) reject(err);

                // assert the data was accepted
                try {
                    this.assertEqual(CONCTR_TEST_HTTP_CREATED, resp.statuscode);
                    resolve();
                } catch (error) {
                    reject(error);
                }

            }.bindenv(this))

        }.bindenv(this))
    }


    // test the sendData function sent correctly checks for a http created response
    function testSendArrayData() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = [{
                            "temperature": 15,
                            "humidity": 80,
                        },{
                            "temperature": 25,
                            "humidity": 70,
                        }];

            // Send the payload
            conctr.sendData(payload, function(err, resp) {
                if (err) reject(err);

                // assert the data was accepted
                try {
                    this.assertEqual(CONCTR_TEST_HTTP_CREATED, resp.statuscode);
                    resolve();
                } catch (error) {
                    reject(error);
                }

            }.bindenv(this))

        }.bindenv(this))
    }



    // test the sendData function where the payload contains fields not in
    // the conctr model
    // checks for a http bad request response
    function testSendInvalidPayload() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = {
                    "FIELD_NOT_IN_MODEL": 15,
                };

                // Send the payload
            conctr.sendData(payload, function(err, resp) {
                // assert the data was not accepted
                try {
                    this.assertEqual(CONCTR_TEST_HTTP_BAD_REQUEST, resp.statuscode);
                    resolve();
                } catch (error) {
                    reject(error);
                }
            }.bindenv(this))
        }.bindenv(this))
    }



    // tests the setting the device's id, checks that value changed successfully
    function testSetDeviceId() {

        return Promise(function(resolve, reject) {

            local newDeviceId = "testDevice";

            try {
                // Ensure that the device ids do not already match
                this.assertTrue(conctr._device_id != newDeviceId);

                // Change the device id
                conctr.setDeviceId("testDevice");

                // Check new device id was set
                this.assertEqual(conctr._device_id, newDeviceId);
                resolve();
            } catch (error) {
                reject(error);
            }

        }.bindenv(this))
    }


    // test the publish function sent correctly checks for a http created response
    function testPublishToDevice() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local msg = "hello world";

            conctr.publishToDevice(conctr._device_id, msg, function(err, resp) {
                if (err) reject(err);
                resolve();
            });
        }.bindenv(this))
    }

    function testPublish() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local msg = "hello world";

            conctr.publish("test_topic", msg, function(err, resp) {
                if (err) reject(err);
                resolve();
            });

        }.bindenv(this))
    }

    // test the publish function sent correctly checks for a http created response
    function testSubscribe() {
        return Promise(function(resolve, reject) {
            
            // Message to publih
            local msg = "hello world";
            
            conctr.subscribe("test_topic",function(resp) {
                local received = resp.body;
                // Ensure that the device ids do not already match
                this.assertTrue(received == msg);
                resolve();
            }.bindenv(this))

            this.info("Published a message")
            conctr.publish("test_topic", msg, function(err, resp) {
                if (err) reject(err);
            });
        }.bindenv(this))
    }



    // tests the rocky endpoints
    // currently not set to run
    function xtestRockyEndpoints() {

        return Promise(function(resolve, reject) {

            local endpoint = http.agenturl() + "/conctr/claim";

            local req = http.request("POST", endpoint, {}, http.jsonencode({}));

            req.sendasync(function(resp) {

                try {
                    this.assertEqual(CONCTR_TEST_HTTP_UNAUTHORIZED, resp.statuscode);
                    resolve();
                } catch (error) {
                    reject(error);
                }

            }.bindenv(this));

        }.bindenv(this))
    }

    function tearDown() {
        return "Test finished";
    }
}