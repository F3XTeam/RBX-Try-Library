-- A library for controlling the flow of error-prone, interdependent functions
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local function PackageProtectedCall(self, Success, ...)
	--- Packages (self, pcall()) updates Attempt self
	-- @returns Attempt self

	-- Update attempt state with execution information
	self.Success = Success;
	self.Results = {...};

	-- Get stack trace and start list of skipped operations on failure
	if not Success then
		self.Stack = debug.traceback();
		self.Skips = {};
	end;

	-- Return attempt for chaining
	return self;

end;

-- Define default Attempt properties
local Attempt = {};
Attempt.RetryCount = 0;
Attempt._IsAttempt = true;
Attempt.__index = Attempt;

local function Try(Function, ...)
	--- Calls Function with (...) in protected mode, and returns chainable Attempt
	-- @returns Attempt Object

	-- Initialize new attempt
	local self = {};
	self.Id = tostring(self);
	self.Function = Function;
	self.Arguments = {...};

	-- Run and return attempt for chaining
	return PackageProtectedCall(setmetatable(self, Attempt), pcall(Function, ...));

end;

-- Return attempt debugging ID when converted to string
function Attempt:__tostring()
	return self.Id:gsub('table', 'Attempt');
end;

function Attempt:Then(Callback)
	-- Passes attempt results to callback, and returns attempt for chaining

	if self.Success then

		-- Enter new attempt context if received
		if getmetatable(self.Results[1]) == Attempt then
			self = self.Results[1];
		end

		self.Function = Function;
		self.Arguments = self.Results;

		-- Execute callback with results of last attempt
		return PackageProtectedCall(self, pcall(Function, unpack(self.Results)));

	-- Skip callback if attempt failed
	else
		self.Skips[#self.Skips + 1] = Callback;
		return self;
	end;
	
end;

function Attempt:Catch(...)
	-- Passes errors in failed attempt to given callback, returns attempt for chaining

	local FirstResult = self.Results[1];

	-- Skip catching if attempt succeeded
	if self.Success then

		-- Enter new attempt context if received
		if getmetatable(FirstResult) == Attempt then
			return FirstResult;
		end

	-- Attempt failed, catch
	elseif not self.Handled then

		-- Get arguments
		local Arguments = { ... };

		-- Get predicate count and callback
		local PredicateCount = #Arguments - 1;
		local Callback = Arguments[PredicateCount + 1];

		-- Track catching operation for future retry attempts
		self.Skips[#self.Skips + 1] = Arguments;

		-- Get attempt error
		local HandleError = false;

		-- Handle any error if no predicates specified
		if PredicateCount == 0 then
			HandleError = true;

		-- Handle matching error if predicates specified
		elseif type(FirstResult) == 'string' then
			for PredicateId = 1, PredicateCount do
				if FirstResult:match(Arguments[PredicateId]) then
					HandleError = true;
					break;
				end;
			end;
		end;

		-- Attempt passing error to callback, and return attempt on success
		if HandleError then
			return Try(Callback, FirstResult, self.Stack, self):Then(function()
				self.Handled = true;
				return self;
			end);
		end;

	end;

	-- Return attempt for chaining
	return self;

end;

function Attempt:Retry()
	-- Retries attempt from first failure, applies skipped operations, and returns resulting attempt

	-- Skip retrying if attempt succeeded
	if not self.Success then

		-- Get skips after attempt failure
		local Skips = self.Skips;

		-- Reset attempt for reexecution
		self.Handled = nil;
		self.Skips = nil;
		self.Stack = nil;

		-- Increment retry counter
		self.RetryCount = self.RetryCount + 1;

		-- Retry attempt
		PackageProtectedCall(self, pcall(self.Function, unpack(self.Arguments)));

		-- Reset retry counter if retry succeded
		if self.Success then
			self.RetryCount = nil;
		end;

		-- Apply skipped operations
		for SkipIndex = 1, #Skips do
			local Skip = Skips[SkipIndex];
			local SkipMetatable = getmetatable(Skip);

			-- Apply callables as `then` operations
			if type(Skip) == 'function' or (SkipMetatable and SkipMetatable.__call) then
				self = self:Then(Skip);

			-- Apply non-callables as `catch` operations
			else
				self = self:Catch(unpack(Skip));
			end;
		end;

		-- Return attempt for chaining
		return self;
	end;

end;

return Try;
