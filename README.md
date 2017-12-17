# Try
An asynchronous pcall-wrapper library for controlling the flow of error-prone, interdependent functions. [Get a built module on Roblox here](https://www.roblox.com/library/987135020/Try-Library-from-F3X), or [install it through the RoStrap plugin.](https://www.roblox.com/library/725884332/RoStrap)

## How to use
Upon requiring the Library, it returns a function called Try:
```lua
-- Without RoStrap
local Try = require(TryLibrary)
```
```lua
-- With RoStrap
local Resources = require(ReplicatedStorage:WaitForChild("Resources"))

local Try = Resources:LoadLibrary("Try")
```

### API
`Attempt Try(Function, ...)`

`Try` calls `pcall(Function, ...)` **on a separate thread**, and returns a table Object called an `Attempt`.

#### Attempt
`Attempt :Then(Callback)`

This method takes a callback of the form `<function, callable table> Callback(...)`, and pcalls it **if the previous pcall didn't error**, with `...` being that which was returned by that `pcall`. This also returns the attempt, for further chaining.

```lua
local HttpService = game:GetService('HttpService')

Try(wait, 0.1)

    -- Try hashing the time
    :Then(function (Delta, ElapsedTime)
        return HttpService:GetAsync('http://md5.jsontest.com/?text=' .. Delta)
    end)

    -- Try decoding the response
    :Then(function (RawResponse)
        return HttpService:JSONDecode(RawResponse)
    end)

    -- Print the decoded response data
    :Then(function (Response)
        print('Input:', Response.original, '\nMD5:', Response.md5)
    end)
```

`Attempt :Catch([string Patterns...], Callback)`

This method takes a callback of the form `Variant Callback(string Error, string Stack, Attempt FailedAttempt)`, and pcalls it **if the previous pcall had an error**. Errors can be optionally filtered by providing a list of [patterns which the error should match](http://wiki.roblox.com/index.php?title=String_pattern#Simple_matching), otherwise all errors are caught by the function. Once an attempt's error is caught, it will not be caught by the next chained `:Catch` method, unless `Callback` itself has an error. The attempt is then returned for chaining.

If the first returned value from the attempt is an `Attempt`, it will be executed and the method will process its errors.

```lua
local HttpService = game:GetService('HttpService')

Try(HttpService.GetAsync, HttpService, 'http://httpstat.us/404')
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

[httpstat.us](http://httpstat.us/) is a good way to test Http request errors.

`Attempt :Retry()`

This method can only be called within a `Catch` callback. It retries the last function called in the chain before the error (with the same old arguments). `Attempt.RetryCount` is incremented each time the attempt is retried, and is reset after a `Retry` `pcall` doesn't error.

You can use this method to retry a sequence of interdependent function calls that fail, and even limit the number of, or space out, retries. For example:

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

`Attempt :Wait()`

This method yields until all of the pcalls before it have finished running.

```lua
Try(wait, 0.5)
    :Then(wait)
    :Wait()
print("Hello!") -- Runs after all of the threads finish
```

A `:Wait()` can go anywhere in the Chain:

```lua
local Attempt = Try(wait, 2)

print("Hey!") -- This runs immediately after Try is called on a separate thread

Attempt
    :Wait() -- Wait until this Attempt's thread finishes yielding
    :Then(function(...) -- This is still on a separate thread
        wait(1)
        print("This was returned by wait(2)", ...)
    end)
print("The Attempt has finished yielding!")
```
