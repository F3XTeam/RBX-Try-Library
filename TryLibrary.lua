-- A library for controlling the flow of error-prone, interdependent functions
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

-- Attempt Object
local Attempt = {};

-- pcall Helper
local function PackageProtectedCall(...)
	return ..., { select(2, ...) };
end

-- Attempt Generator
local function Try(Function, ...)

	-- Capture function execution response
	local Success, Arguments = PackageProtectedCall(pcall(Function, ...))

	-- Create new Attempt for chaining
	local self = {}

	-- Gather arguments to return from data
	self.Arguments = Arguments;
	self.Success = Success;
	self.Stack = debug.traceback();
	self.LastArguments = { ... };
	self.Hops = (not Success) and { Function } or nil;
	self.Id = tostring(self);

	return setmetatable(self, Attempt);

end;

-- Default Values
Attempt.RetryCount = 0;
Attempt.Start = true;
Attempt.__index = Attempt;

-- Indicate type when converted to string (to aid in debugging)
function Attempt:__tostring()
	return self.Id:gsub('table', 'attempt');
end;

-- Attempt Methods
function Attempt:Then(Callback)

	-- Update attempt state
	self.Start = false;

	-- Enter new attempt contexts if received
	local FirstArgument = self.Arguments[1];
	if self.Success and type(FirstArgument) == 'table' and getmetatable(FirstArgument) == Attempt then
		self = FirstArgument;
	end;

	-- Skip processing if attempt failed
	if not self.Success then
		self.Hops[#self.Hops + 1] = Callback;
		return self;
	end;

	-- Capture callback execution response
	local Success, Arguments = PackageProtectedCall(pcall(Callback, unpack(self.Arguments)))

	-- Replace attempt state
	self.Stack = debug.traceback();
	self.Success = Success;
	self.Arguments = Arguments;
	self.LastArguments = self.Arguments;
	
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
	
	if type(FirstArgument) == 'table' and getmetatable(FirstArgument) == Attempt then
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
