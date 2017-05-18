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

class DeviceTestCase extends ImpTestCase {

    function setUp() {
        return "Hi from #{__FILE__}!";
    }


    function testSendData() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = {
                "temperature": 15,
                "humidity": 80,
            }

            // Send the payload
            conctr.sendData(payload, function(err, resp) {
                if (err) reject(err);
                // Check if sender has reply capability
                if ("onReply" in conctr._sender) {
                    // assert the data was accepted
                    this.assertEqual(201, resp.statuscode);
                } else {
                    // resp will be null as there is no messageManager to get a response from
                    this.assertTrue(resp == null);
                }
                resolve();
            }.bindenv(this))
        }.bindenv(this))
    }

    function testSend() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = {
                "temperature": 15,
                "humidity": 80,
            }

            // Send the payload
            local resp = conctr.send(null, payload);

            this.assertEqual(resp, 0);
            resolve();
        }.bindenv(this))
    }

    function testSetLocationSendingOpts() {
        return Promise(function(resolve, reject) {

            local newOpts = {
                "locEnabled": false,
                "locInterval": 7200,
                "locSendOnce": true,
                "locWakeReasons": [],
            }

            // Ensure the opts are different
            foreach (k, v in newOpts) {
                this.assertTrue(conctr["_" + k] != v);
            }

            // Change the options
            conctr.setLocationOpts(newOpts);

            // Ensure the opts are now all set to new vals
            foreach (k, v in newOpts) {
                this.assertDeepEqual(conctr["_" + k], v);
            }

            resolve();
        }.bindenv(this))
    }


    function xtestMessageManagerReply() {
        return Promise(function(resolve, reject) {
            // Ensure this payload matches your model
            local payload = {
                "temperature": 15,
                "humidity": 80,
            }

            // Send the payload
            conctr.sendData(payload, function(err, resp) {
                if (err) reject(err);
                // Check if sender has reply capability
                this.assertTrue("onReply" in conctr._sender);
                // assert the data was accepted
                this.assertEqual(201, resp.statuscode);
                resolve();
            }.bindenv(this))
        }.bindenv(this))
    }

    function tearDown() {
        return "Test finished";
    }
}
