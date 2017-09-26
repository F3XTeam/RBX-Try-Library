-- A library for controlling the flow of error-prone, interdependent functions
-- @author Validark
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local function Package(self, Position, Success, Error, ...)
	local Count = self.Count
	if Success then
		-- Don't enter `Then` from a `Catch`
		if self[Position] == 2 then
			-- Make sure we don't ever resume
			Count = Position + 1
		else
			for Position = Position + 2, Count, 2 do
				-- Enter next `Then` function
				if self[Position] == 1 then
					self.LastArguments = {Error, ...}
					return Package(self, Position, pcall(self[Position + 1], Error, ...)) -- Call next Then with arguments
				end
			end
		end
	else
		self.ErrorPosition = Position
		for Position = Position + 2, Count, 2 do
			-- Enter next `Catch` function
			if self[Position] == 2 then
				-- Get arguments and predicate count
				local Arguments = self[Position + 1]
				local PredicateCount = #Arguments - 1

				-- Handle any error if no predicates specified
				if PredicateCount == 0 then
					return Package(self, Position, pcall(Arguments[PredicateCount + 1], Error, debug.traceback(), self))

				-- Handle matching error if predicates specified
				elseif type(Error) == 'string' then
					for PredicateId = 1, PredicateCount do
						if Error:match(Arguments[PredicateId]) then
							return Package(self, Position, pcall(Arguments[PredicateCount + 1], Error, debug.traceback(), self))
						end
					end
				end

			end
		end
	end
	return {self, Count - 1, Success, Error, ...}
end

-- Define default Attempt properties
local Attempt = {}
Attempt.Count = 0
Attempt.RetryCount = 0
Attempt.__index = Attempt

local function Try(Function, ...)
	--- Calls Function with (...) in protected mode, and returns chainable Attempt
	-- @returns Attempt Object

	local Bindable = Instance.new("BindableEvent")

	local self = setmetatable({
		[0] = Function;
		Bindable = Bindable;
		LastArguments = {...};
	}, Attempt)

	local PreviousRetryCount, Results = 0

	Bindable.Event:Connect(function(ErrorPosition)
		-- Resume Thread and Cache results
		if ErrorPosition then
			Results = Package(self, ErrorPosition, pcall(self[ErrorPosition + 1], unpack(self.LastArguments)))
		else
			Results = Package(unpack(Results))
		end

		-- Don't resolve thread if `Retry` was initiated
		if PreviousRetryCount == self.RetryCount then
			self.Resolved, self.RetryCount = true
		else
			PreviousRetryCount = self.RetryCount
		end
	end)

	Bindable:Fire(-1)

	return self
end

function Attempt:__tostring()
	if not self.Id then
		self.Id = tostring{}:gsub('table', 'Attempt')
	end
	return self.Id
end

function Attempt:Then(Function)
	local Count = self.Count + 2
	self.Count = Count
	self[Count - 1] = 1
	self[Count] = Function

	if self.Resolved then
		self.Resolved = false
		self.Bindable:Fire()
	end

	return self
end

function Attempt:Catch(...)
	local Count = self.Count + 2
	self.Count = Count
	self[Count - 1] = 2
	self[Count] = {...}

	if self.Resolved and self.ErrorPosition then
		self.Resolved = false
		self.Bindable:Fire()
	end

	return self
end

function Attempt:Wait()
	while not self.Resolved do wait() end
	return self
end

function Attempt:Retry()
	self.RetryCount = self.RetryCount + 1
	self.Bindable:Fire(self.ErrorPosition)
	return self
end

return Try
