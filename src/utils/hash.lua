--[[
    Hash Module
]]

local md5_lib = require("md5")

local hash = {}

-- @param data string
-- @return string hex MD5
function hash.md5(data)
    if data == nil then
        return nil
    end
    return md5_lib.sumhexa(data)
end

--- calc hash in binary
-- @param data string
-- @return string binary MD5 16 bytes
--[[
function hash.md5_binary(data)
    if data == nil then
        return nil
    end
    return md5_lib.sum(data)
end
]]--

return hash
