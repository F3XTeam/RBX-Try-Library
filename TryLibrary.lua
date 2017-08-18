function Try(Function, ...)

	-- Capture function execution response
	local Data = { pcall(Function, ...) };

	-- Determine whether execution succeeded or failed
	local Success = Data[1];
	
	-- Gather arguments to return from data
	local Arguments = { unpack(Data, 2) };

	-- Return attempt for chaining
	return setmetatable({
		_IsAttempt = true,
		Then = Then,
		Catch = Catch,
		Retry = Retry,
		Success = Success,
		Arguments = Arguments,
		Stack = debug.traceback(),
		LastArguments = { ... },
		Hops = (not Success) and { Function } or nil,
		RetryCount = 0,
		Start = true

	-- Indicate type when converted to string (to aid in debugging)
	}, { __tostring = function () return 'Attempt' end })

end;

function Then(Attempt, Callback)

	-- Update attempt state
	Attempt.Start = false;

	-- Enter new attempt contexts if received
	local FirstArgument = Attempt.Arguments[1];
	if Attempt.Success and type(FirstArgument) == 'table' and FirstArgument._IsAttempt then
		Attempt = FirstArgument;
	end;

	-- Skip processing if attempt failed
	if not Attempt.Success then
		table.insert(Attempt.Hops, Callback);
		return Attempt;
	end;

	-- Capture callback execution response
	local Data = { pcall(Callback, unpack(Attempt.Arguments)) };
	local Success = Data[1];
	local Arguments = { unpack(Data, 2) };

	-- Replace attempt state
	Attempt.Success = Success;
	Attempt.LastArguments = Attempt.Arguments;
	Attempt.Arguments = Arguments;
	Attempt.Stack = debug.traceback();

	-- Track hops on failure
	if not Success then
		Attempt.Hops = { Callback };
	end

	-- Return attempt for chaining
	return Attempt;

end;

function Catch(Attempt, ...)

	-- Capture all arguments
	local Arguments = { ... };

	-- Get target errors and the callback
	local TargetErrors = { unpack(Arguments, 1, #Arguments - 1) };
	local Callback = unpack(Arguments, #Arguments);

	-- Enter new attempt contexts if received
	local FirstArgument = Attempt.Arguments[1];
	if type(FirstArgument) == 'table' and FirstArgument._IsAttempt then
		Attempt = FirstArgument;
	end;

	-- Proceed upon unhandled failure
	if not Attempt.Success and not Attempt.Handled then

		-- Track hops
		table.insert(Attempt.Hops, Arguments);

		-- Get error from failed attempt
		local Error = Attempt.Arguments[1];

		-- Filter errors if target errors were specified
		if (#TargetErrors > 0) then
			for _, TargetError in pairs(TargetErrors) do
				if type(Error) == 'string' and Error:match(TargetError) then
					Attempt.Handled = true;
					return Try(Callback, Error, Attempt.Stack, Attempt);
				end;
			end;

		-- Pass any error if no target errors were specified
		elseif #TargetErrors == 0 then
			Attempt.Handled = true;
			return Try(Callback, Error, Attempt.Stack, Attempt);
		end;

	end;

	-- Return attempt for chaining
	return Attempt;

end;

function Retry(Attempt)

	-- Ensure attempt failed
	if Attempt.Success then
		return;
	end;

	-- Get hops and arguments
	local Hops = Attempt.Hops;
	local Arguments = Attempt.LastArguments;

	-- Reset attempt state
	Attempt.Hops = nil;
	Attempt.Success = true;
	Attempt.Arguments = Arguments;
	Attempt.Handled = nil;
	Attempt.RetryCount = Attempt.RetryCount and (Attempt.RetryCount + 1) or 1;

	-- Restart attempts that failed from the start
	if Attempt.Start then
		local NewAttempt = Try(Hops[1], Arguments);

		-- Reset retry counter if reattempt succeeds
		if NewAttempt.Success then
			NewAttempt.RetryCount = 0;
		else
			NewAttempt.RetryCount = Attempt.RetryCount;
		end;

		-- Apply each hop
		for HopIndex, Hop in ipairs(Hops) do
			if HopIndex > 1 then

				-- Apply `then` hops
				if type(Hop) == 'function' then
					NewAttempt:Then(Hop);
					
				-- Apply `catch` hops
				elseif type(Hop) == 'table' then
					NewAttempt:Catch(unpack(Hop));
				end;

			end;
		end;
		
		-- Return the new attempt
		return NewAttempt;
	
	-- Continue attempts that failed after the start
	else
		for HopIndex, Hop in ipairs(Hops) do

			-- Apply `then` hoops
			if type(Hop) == 'function' then
				Attempt:Then(Hop);

			-- Apply `catch` hops
			elseif type(Hop) == 'table' then
				Attempt:Catch(unpack(Hop));
			end;
			
			-- Reset retry counter if reattempt succeeds
			if HopIndex == 1 and Attempt.Success then
				Attempt.RetryCount = 0;
			end;

		end;

		-- Return the attempt
		return Attempt;
	end;

end;

return Try;