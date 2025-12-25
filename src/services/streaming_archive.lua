--[[
    StreamingArchive Module

    Incremental ZIP archive writer for streaming pipeline.
    Allows adding files one by one as they arrive.
]]

local zip = require("brimworks.zip")

local StreamingArchive = {}
StreamingArchive.__index = StreamingArchive

function StreamingArchive.new(filename)
    local temp_path = filename or (os.tmpname() .. ".zip")
    return setmetatable({
        filename = temp_path,
        archive = nil,
        file_count = 0,
        total_bytes = 0,
        is_open = false,
        use_temp = (filename == nil)
    }, StreamingArchive)
end

function StreamingArchive:open()
    if self.is_open then
        return false, "Archive already open"
    end

    os.remove(self.filename)

    local archive, err = zip.open(self.filename, zip.CREATE)
    if not archive then
        return false, "Failed to create archive: " .. tostring(err)
    end

    self.archive = archive
    self.is_open = true
    self.file_count = 0
    self.total_bytes = 0
    self.added_files = {}  -- Track files added to this archive

    return true
end

--- Add image to archive Binary image data
function StreamingArchive:add_image(image_data, filename)
    if not self.is_open or not self.archive then
        return false, "Archive not open"
    end

    if not image_data or #image_data == 0 then
        return false, "Empty image data"
    end

    -- Check if file already exists in this archive
    if self.added_files[filename] then
        return false, "File already in archive: " .. filename
    end

    local ok, idx = pcall(function()
        return self.archive:add(filename, "string", image_data)
    end)

    if not ok then
        return false, "Failed to add file: " .. filename .. " - " .. tostring(idx)
    end

    self.added_files[filename] = true
    self.file_count = self.file_count + 1
    self.total_bytes = self.total_bytes + #image_data

    return true
end

--- Close archive (finalize)
function StreamingArchive:close()
    if not self.is_open then
        return false, "Archive not open"
    end

    if self.archive then
        self.archive:close()
        self.archive = nil
    end

    self.is_open = false
    return true
end

--- Get archive binary data
-- Must be called after close()
-- @return string|nil Binary ZIP data
-- @return string|nil Error message
function StreamingArchive:get_data()
    if self.is_open then
        return nil, "Archive still open, call close() first"
    end

    local f, err = io.open(self.filename, "rb")
    if not f then
        return nil, "Failed to read archive: " .. tostring(err)
    end

    local data = f:read("*a")
    f:close()

    return data
end

function StreamingArchive:get_path()
    return self.filename
end

function StreamingArchive:get_stats()
    return {
        files = self.file_count,
        bytes = self.total_bytes,
        is_open = self.is_open
    }
end

function StreamingArchive:is_opened()
    return self.is_open
end

function StreamingArchive:get_file_count()
    return self.file_count
end

function StreamingArchive:cleanup()
    if self.is_open and self.archive then
        self.archive:close()
        self.archive = nil
        self.is_open = false
    end

    -- Remove file from disk
    os.remove(self.filename)
end

return StreamingArchive
