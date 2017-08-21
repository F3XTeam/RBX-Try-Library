-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local Attempt = {
	_IsAttempt = true;	
	RetryCount = 0;
	Start = true;
}
Attempt.__index = Attempt

-- Indicate type when converted to string (to aid in debugging)
function Attempt:__tostring()
	return self.Id
end

local function Try(Function, ...)
	-- Capture function execution response
	local Arguments = { pcall(Function, ...) };

	-- Determine whether execution succeeded or failed
	local Success = table.remove(Arguments, 1);

	-- Create new Attempt for chaining
	local self = {
		-- Gather arguments to return from data
		Arguments = Arguments,
		Success = Success,		
		Stack = debug.traceback(),
		LastArguments = { ... },
		Hops = (not Success) and { Function } or nil
	}
	self.Id = tostring(self):gsub('table', 'attempt');
	return setmetatable(self, Attempt);
end;

function Attempt:Then(Callback)

	-- Update attempt state
	self.Start = false;

	-- Enter new attempt contexts if received
	local FirstArgument = self.Arguments[1];
	if self.Success and type(FirstArgument) == 'table' and FirstArgument._IsAttempt then
		self = FirstArgument;
	end;

	-- Skip processing if attempt failed
	if not self.Success then
		table.insert(self.Hops, Callback);
		return self;
	end;

	-- Capture callback execution response
	local Arguments = { pcall(Callback, unpack(self.Arguments)) };
	local Success = table.remove(Arguments, 1);

	-- Replace attempt state
	self.Success = Success;
	self.LastArguments = self.Arguments;
	self.Arguments = Arguments;
	self.Stack = debug.traceback();

	-- Track hops on failure
	if not Success then
		self.Hops = { Callback };
	end

	-- Return attempt for chaining
	return self;
end;

function Attempt:Catch(...)

	-- Capture all arguments
	local Arguments = { ... };

	-- Get error count so callback = ErrorCount + 1
	local ErrorCount = #Arguments - 1;

	-- Enter new attempt contexts if received
	local FirstArgument = self.Arguments[1];
	if type(FirstArgument) == 'table' and FirstArgument._IsAttempt then
		self = FirstArgument;
	end;

	-- Proceed upon unhandled failure
	if not self.Success and not self.Handled then

		-- Track hops
		self.Hops[#self.Hops + 1] = Arguments;

		-- Get error from failed attempt
		local Error = self.Arguments[1];

		-- Pass any error if no target errors were specified
		if ErrorCount == 0 then
			self.Handled = true;
			return Try(Arguments[ErrorCount + 1], Error, self.Stack, self);

		-- Filter errors if target errors were specified
		elseif type(Error) == 'string' then
			for a = 1, ErrorCount do
				if Error:match(Arguments[a]) then
					self.Handled = true;
					return Try(Arguments[ErrorCount + 1], Error, self.Stack, self);
				end;
			end;
		end;

	end;

	-- Return attempt for chaining
	return self;
end;

function Attempt:Retry()

	-- Ensure attempt failed
	if not self.Success then
		-- Get hops and arguments
		local Hops = self.Hops;
		local Arguments = self.LastArguments;
		local RetryCount = self.RetryCount + 1;

		-- Reset attempt state		
		self.Arguments = Arguments;
		self.RetryCount = RetryCount;
		self.Success, self.Hops, self.Handled = true;

		-- Restart attempts that failed from the start
		if self.Start then
			self = Try(Hops[1], Arguments);

		-- Continue attempts that failed after the start
		else
			local Hop = Hops[1];
			local HopMetatable = getmetatable(Hop);

			-- Apply `catch` hops
			if type(Hop) == 'table' and (not HopMetatable or not HopMetatable.__call) then
				self:Catch(unpack(Hop));
			
			-- Apply `then` hops
			else
				self:Then(Hop);
			end;
		end

		-- Reset retry counter if reattempt succeeds
		self.RetryCount = self.Success and 0 or RetryCount;

		-- Apply each hop
		for HopIndex = 2, #Hops do
			local Hop = Hops[HopIndex];
			local HopMetatable = getmetatable(Hop);

			-- Apply `catch` hops
			if type(Hop) == 'table' and (not HopMetatable or not HopMetatable.__call) then
				self:Catch(unpack(Hop));
			
			-- Apply `then` hops
			else
				self:Then(Hop);
			end;

		end;

		-- Return the attempt
		return self;
	end;
end;

return Try;
