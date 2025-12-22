--[[
    Archive Builder Module

    ZIP for Cats
]]

local zip = require("brimworks.zip")

local ArchiveBuilder = {}
ArchiveBuilder.__index = ArchiveBuilder

--- New ArchiveBuilder
-- @param config table Configuration
-- @return ArchiveBuilder
function ArchiveBuilder.new(config)
    config = config or {}
    return setmetatable({
        filename_pattern = config.filename_pattern or "cat_%02d.jpg"
    }, ArchiveBuilder)
end

--- creates in mememory ZIP with cats
-- @param images table array with bin data
-- @return string bin data ZIP archive
function ArchiveBuilder:build_zip(images)
    if not images or #images == 0 then
        return nil, "No images provided"
    end

    local temp_path = os.tmpname() .. ".zip"
    -- TRUNCATE
    os.remove(temp_path)

    local archive, err = zip.open(temp_path, zip.CREATE)
    if not archive then
        return nil, "Failed to create archive: " .. tostring(err)
    end

    -- add images
    for i, image_data in ipairs(images) do
        local filename = string.format(self.filename_pattern, i)
        local idx = archive:add(filename, "string", image_data)
        if not idx then
            archive:close()
            os.remove(temp_path)
            return nil, "Failed to add file: " .. filename
        end
    end

    archive:close()

    local f = io.open(temp_path, "rb")
    if not f then
        os.remove(temp_path)
        return nil, "Failed to read created archive"
    end

    local zip_data = f:read("*a")
    f:close()

    os.remove(temp_path)

    return zip_data
end

--- Save ZIP with cats to file
-- @param images table array with binary data (images)
-- @param output_path string
-- @return string path to created archive
-- @return string|nil error msg
function ArchiveBuilder:save_zip(images, output_path)
    if not images or #images == 0 then
        return nil, "No images provided"
    end

    output_path = output_path or "cats.zip"

    -- TRUNCATE
    os.remove(output_path)

    local archive, err = zip.open(output_path, zip.CREATE)
    if not archive then
        return nil, "Failed to create archive: " .. tostring(err)
    end

    for i, image_data in ipairs(images) do
        local filename = string.format(self.filename_pattern, i)
        local idx = archive:add(filename, "string", image_data)
        if not idx then
            archive:close()
            os.remove(output_path)
            return nil, "Failed to add file: " .. filename
        end
    end

    archive:close()

    return output_path
end

return ArchiveBuilder
