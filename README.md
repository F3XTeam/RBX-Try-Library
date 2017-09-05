# RBX.Lua Try Library
A library for controlling the flow of error-prone, interdependent functions. [Get a built module on Roblox here.](https://www.roblox.com/library/987135020/Try-Library-from-F3X)

## How to use
Include the library's Try function by requiring the module.

```lua
local Try = require(TryLibrary)
```

### Try(Function, Arguments...) → Attempt
This function attempts calling `Function` with the given list of `Arguments...`, and returns an `Attempt`, which :Then and :Catch methods can be chained to.

### Attempt:Then(Function `Callback`) → Attempt
This method takes a callback of the form `Variant Callback(ReturnValues...)`, and calls it **if the attempt succeeded**, with `ReturnValues...` being the list of values returned in the attempt. The attempt is then returned for chaining.

If the first value in `ReturnValues...` is an `Attempt`, it will be executed and the method will process its return values. This allows for chaining, such as in:

```lua
local HttpService = game:GetService('HttpService')

Try(wait, 0.1)

    -- Try hashing the time
    :Then(function (Delta, ElapsedTime)
        return Try(HttpService.GetAsync, HttpService, 'http://md5.jsontest.com/?text=' .. Delta)
    end)

    -- Try decoding the response
    :Then(function (RawResponse)
        return Try(HttpService.JSONDecode, HttpService, RawResponse)
    end)

    -- Print the decoded response data
    :Then(function (Response)
        print('Input:', Response.original, '\nMD5:', Response.md5)
    end)
```

### Attempt:Catch([String `Predicates...`], Function `Callback`) → Attempt
This method takes a callback of the form `Variant Callback(String Error, String Stack, Attempt FailedAttempt)`, and calls it **if the attempt had an error**. Errors can be optionally filtered by providing a list of [patterns which the error should match](http://wiki.roblox.com/index.php?title=String_pattern#Simple_matching), otherwise all errors are caught by the function. Once an attempt's error is caught, it will not be caught by the next chained :Catch method, unless `Callback` itself has an error. The attempt is then returned for chaining.

If the first returned value from the attempt is an `Attempt`, it will be executed and the method will process its errors.

```lua
local HttpService = game:GetService('HttpService')

Try(HttpService.GetAsync, HttpService, 'http://google.com/fakeurl')
    :Then(function (Data)
        print('Found', Data)
    end)

    -- Catch when the URL doesn't exist
    :Catch('HTTP 404', function (Error, Stack, Attempt)
        warn('Not found, error:', Error)
    end)

    -- Catch any other error
    :Catch(function (Error, Stack, Attempt)
        warn('Unknown error:', Error)
    end)
```

### Attempt:Retry() → Attempt
This method retries the attempt if it failed, and executes any methods that were chained to it. `Attempt.RetryCount` is incremented each time the attempt is retried, and is reset if a retry succeeds.

You can use this method in combination with an attempt's :Catch method to retry a sequence of interdependent function calls that fail, and even limit the number of, or space out, retries. For example:

```lua
local HttpService = game:GetService('HttpService')

Try(HttpService.GetAsync, HttpService, 'http://httpstat.us/503')
    :Then(function (Data)
        print('Found', Data)
    end)

    -- Catch when the server is having issues and retry
    :Catch('HTTP 503', 'Timeout was reached', function (Error, Stack, Attempt)

        -- Limit the number of retries to 3
        if Attempt.RetryCount < 3 then

            -- Space out each retry
            local BackoffTime = Attempt.RetryCount * 3 + 3
            warn('Retrying in', BackoffTime, 'seconds...')
            wait(BackoffTime)

            -- Retry the attempt
            return Attempt:Retry()

        -- Give up if retry limit reached
        else
            warn('Failed')
        end

    end)

    -- Catch any other errors
    :Catch(function (Error, Stack, Attempt)
        warn('Unknown error:', Error)
    end)
```
