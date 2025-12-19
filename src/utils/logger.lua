--[[
    Logger Module

    Logger DEBUG, INFO, WARN, ERROR.
]]

local Logger = {}
Logger.__index = Logger

local LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

function Logger.new(level)
    level = level or "INFO"
    return setmetatable({
        level = LEVELS[level] or LEVELS.INFO
    }, Logger)
end

function Logger:_log(level, message, ...)
    if LEVELS[level] >= self.level then
        local timestamp = os.date("%Y-%m-%dT%H:%M:%S")
        print(string.format("[%s] [%s] " .. message, timestamp, level, ...))
    end
end

function Logger:debug(message, ...)
    self:_log("DEBUG", message, ...)
end

function Logger:info(message, ...)
    self:_log("INFO", message, ...)
end

function Logger:warn(message, ...)
    self:_log("WARN", message, ...)
end

function Logger:error(message, ...)
    self:_log("ERROR", message, ...)
end

return Logger
