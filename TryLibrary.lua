-- An asynchronous pcall-wrapper for interdependent error-prone functions
-- @author Validark
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local function Continue(self, Position, HistoryCount, Success, Error, ...)
	if Success then
		for Position = Position + 3, self.Count, 3 do
			-- Enter next `Then` function
			if self[Position] == 1 then
				self.LastArguments = {Error, ...}
				self.History[HistoryCount + 1] = Position
				return Continue(self, Position, HistoryCount + 1, pcall(self[Position + 1], Error, ...)) -- Call next Then with arguments
			end
		end
	else
		for Position = Position + 3, self.Count, 3 do
			-- Enter next `Catch` function
			if self[Position] == 2 then
				-- Get arguments and predicate count
				local Arguments = self[Position + 1]
				local PredicateCount = #Arguments - 1
				local Caught = PredicateCount == 0

				-- Handle matching error if strings were passed into Catch
				if not Caught and type(Error) == "string" then
					for Predicate = 1, PredicateCount do
						if Error:match(Arguments[Predicate]) then
							Caught = true
							break
						end
					end
				end
				
				if Caught then
					local History = self.History
					HistoryCount = HistoryCount + 1					
					History[HistoryCount] = Position

					-- Compile Traceback
					local Traceback = "Stack Begin\n"
					for a = 1, HistoryCount do
						local Position = History[a]
						local Type = self[Position]
						local Message = (
							Type == 0 and self[Position + 2]:match("Try.-[\n\r]([^\n\r]+)") .. " - upvalue Try\n" or
							Type == 1 and self[Position + 2]:match("%- method Then[\n\r]([^\n\r]+)") .. " - method Then\n" or
							self[Position + 2]:match("%- method Catch[\n\r]([^\n\r]+)") .. " - method Catch\n"
						)
						if Message then
							Traceback = Traceback .. Message
						end						
					end
					return Continue(self, Position, HistoryCount, pcall(Arguments[PredicateCount + 1], Error, Traceback .. "Stack End", self))
				end
			end
		end
	end

	-- This is what we are reduced to because Roblox refuses to fix coroutine.yield
	-- https://devforum.roblox.com/t/wait-breaks-coroutine-yield/52881
	self.Data = {Position, HistoryCount, Success, Error, ...}

	-- Don't resolve thread if `Retry` was initiated
	if self.PreviousRetryCount == self.RetryCount then
		self.Resolved, self.RetryCount = true
	else
		self.PreviousRetryCount = self.RetryCount
	end
end

local function Start(self, Position, HistoryCount, ...)
	Continue(self, Position, HistoryCount, pcall(self[Position + 1], ...))
end

local Attempt = {
	[0] = 0;
	Count = 2;
	RetryCount = 0;
	HistoryCount = 1;
	PreviousRetryCount = 0;
}

Attempt.__index = Attempt

function Attempt:__tostring()
	if not self.Id then
		self.Id = tostring{}:gsub("table", "attempt")
	end
	return self.Id
end

function Attempt:Then(Function)
	local Count = self.Count + 3
	self.Count = Count
	self[Count - 2], self[Count - 1], self[Count] = 1, Function, debug.traceback()
	if self.Resolved then
		self.Resolved = false
		coroutine.resume(coroutine.create(Continue), self, unpack(self.Data))
	end
	return self
end

function Attempt:Catch(...)
	local Count = self.Count + 3
	self.Count = Count	
	self[Count - 2], self[Count - 1], self[Count] = 2, {...}, debug.traceback()
	if self.Resolved then
		self.Resolved = false
		coroutine.resume(coroutine.create(Continue), self, unpack(self.Data))
	end
	return self
end

function Attempt:Wait()
	while not self.Resolved do wait() end
	return self
end

function Attempt:Retry()
	self.RetryCount = self.RetryCount + 1
	local HistoryCount = #self.History
	for a = HistoryCount, 1, -1 do
		-- Find the last `Then` function and start it back up
		local ErrorPosition = self.History[a]
		if self[ErrorPosition] == 1 then
			coroutine.resume(coroutine.create(Start), self, ErrorPosition, HistoryCount, unpack(self.LastArguments))
			return self
		end
	end
	error("[Try] Attempt has nothing to `Retry`")
end

local function Try(Function, ...)
	--- Calls Function with (...) in protected mode, and returns chainable Attempt
	-- @returns Attempt Object

	local self = setmetatable({
		Function, debug.traceback();
		History = {0};
		LastArguments = {...};
	}, Attempt)
	coroutine.resume(coroutine.create(Start), self, 0, 1, ...)
	return self
end

return Try
