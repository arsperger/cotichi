--[[
    Deduplicator Module

    Check Dedup with MD5
]]

local hash = require("utils.hash")

local Deduplicator = {}
Deduplicator.__index = Deduplicator

-- @return Deduplicator
function Deduplicator.new()
    return setmetatable({
        seen_hashes = {},
        count = 0
    }, Deduplicator)
end

--- Calc hash MD5
-- @param image_data string (binary data)
-- @return string MD5
function Deduplicator:compute_hash(image_data)
    if image_data == nil or #image_data == 0 then
        return nil
    end
    return hash.md5(image_data)
end

--- Check and add
-- @param image_data string
-- @return boolean true if unique and added
-- @return string|nil MD5 hash of image (returned even for duplicates)
function Deduplicator:try_add(image_data)
    local img_hash = self:compute_hash(image_data)
    if img_hash == nil then
        return false, nil
    end
    if self.seen_hashes[img_hash] then
        return false, img_hash
    end
    self.seen_hashes[img_hash] = true
    self.count = self.count + 1
    return true, img_hash
end

function Deduplicator:reset()
    self.seen_hashes = {}
    self.count = 0
end

--- Get unique count
-- @return number
function Deduplicator:get_count()
    return self.count
end

return Deduplicator
