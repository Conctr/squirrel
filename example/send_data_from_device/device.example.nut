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

#require "conctr.agent.lib.nut:2.0.0"
#require "bullwinkle.class.nut:2.3.2"

// Configure bullwinkle
bullOpts <- {
    "messageTimeout": 30, // If there is no response from a message in 5 seconds, consider it failed
    "retryTimeout": 30, // Calling package.retry() with no parameter will retry in 30 seconds
    "maxRetries": 10, // Limit to the number of retries to 10
    "autoRetry": true // Automatically retry 10 times
}

// Initialise bullwinkle

bull <- Bullwinkle(bullOpts);

// Configure Conctr
conctrOpts <- {
    "locEnabled": true,
    "locInterval": 3600,
    "locSendOnce": false,
    "locWakeReasons": [WAKEREASON_BLINKUP, WAKEREASON_PIN, WAKEREASON_NEW_SQUIRREL],
    "messageManager": bull
}

// Initialise conctr

conctr <- Conctr(conctrOpts);

// Example payload. This must contain fields relating to your conctr model.
payload <- {
    temperature: 32,
    humidity: 10
}

conctr.sendData(payload, function(err, resp) {
    if (err) server.log("Error sending data: " + err);
    else server.log("Successfully sent data");
});
