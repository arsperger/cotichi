--[[
    Deduplicator Module

    Check Dedup with MD5

    Use:
        local Deduplicator = require("services.deduplicator")
        local dedup = Deduplicator.new()

        if not dedup:is_duplicate(image_data) then
            dedup:add_image(image_data)
        end

        -- After:
        dedup:reset()
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

--- Check
-- @param image_data string
-- @return boolean true if duplicate
function Deduplicator:is_duplicate(image_data)
    local img_hash = self:compute_hash(image_data)
    if img_hash == nil then
        return false
    end
    return self.seen_hashes[img_hash] ~= nil
end

--- Add to seen
-- @param image_data string
-- @return string Hash
function Deduplicator:add_image(image_data)
    local img_hash = self:compute_hash(image_data)
    if img_hash == nil then
        return nil
    end
    self.seen_hashes[img_hash] = true
    self.count = self.count + 1
    return img_hash
end

--- Check and add
-- @param image_data string
-- @return boolean true if unique and added
function Deduplicator:try_add(image_data)
    local img_hash = self:compute_hash(image_data)
    if img_hash == nil then
        return false
    end
    if self.seen_hashes[img_hash] then
        return false
    end
    self.seen_hashes[img_hash] = true
    self.count = self.count + 1
    return true
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
