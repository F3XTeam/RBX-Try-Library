-- A library for controlling the flow of error-prone, interdependent functions
-- @author Validark
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local function Package(self, Position, Success, Error, ...)
	if Success then
		-- Don't enter `Then` from a `Catch`
		if self[Position] ~= 2 then
			for Position = Position + 3, self.Count, 3 do
				-- Enter next `Then` function
				if self[Position] == 1 then
					self.LastArguments = {Error, ...}
					self.Traceback = self.Traceback .. self[Position + 2]
					return Package(self, Position, pcall(self[Position + 1], Error, ...)) -- Call next Then with arguments
				end
			end
		end
	else
		self.ErrorPosition = Position
		for Position = Position + 3, self.Count, 3 do
			-- Enter next `Catch` function
			if self[Position] == 2 then
				-- Get arguments and predicate count
				local Arguments = self[Position + 1]
				local PredicateCount = #Arguments - 1

				-- Handle any error if no predicates specified
				if PredicateCount == 0 then
					self.Traceback = self.Traceback .. self[Position + 2]
					return Package(self, Position, pcall(Arguments[PredicateCount + 1], Error, self.Traceback .. "Stack End", self))

				-- Handle matching error if predicates specified
				elseif type(Error) == 'string' then
					for Predicate = 1, PredicateCount do
						if Error:match(Arguments[Predicate]) then
							self.Traceback = self.Traceback .. self[Position + 2]
							return Package(self, Position, pcall(Arguments[PredicateCount + 1], Error, self.Traceback .. "Stack End", self))
						end
					end
				end
			end
		end
	end
	return {self, Position, Success, Error, ...}
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
		[-1] = Function;
		Bindable = Bindable;
		Traceback = "Stack Begin\n" .. debug.traceback():match("Try[\n\r]([^\n\r]+)") .. " - upvalue Try\n";
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

	Bindable:Fire(-2)

	return self
end

function Attempt:__tostring()
	if not self.Id then
		self.Id = tostring{}:gsub('table', 'Attempt')
	end
	return self.Id
end

function Attempt:Then(Function)
	local Count = self.Count + 3
	self.Count = Count
	self[Count - 2] = 1
	self[Count - 1] = Function
	self[Count] = debug.traceback():match("%- method Then[\n\r]([^\n\r]+)") .. " - method Then\n"

	if self.Resolved then
		self.Resolved = false
		self.Bindable:Fire()
	end

	return self
end

function Attempt:Catch(...)
	local Count = self.Count + 3
	self.Count = Count
	self[Count - 2] = 2
	self[Count - 1] = {...}
	self[Count] = debug.traceback():match("%- method Catch[\n\r]([^\n\r]+)") .. " - method Catch\n"

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
