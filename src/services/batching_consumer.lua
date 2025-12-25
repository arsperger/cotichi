--[[
    BatchingConsumer Module

    Consumes images from queue and batches them into archives.
    Every batch_size images:
    - Closes current archive
    - Uploads to server
    - Opens new archive

    Runs continuously until stopped.
]]

local copas = require("copas")
local StreamingArchive = require("services.streaming_archive")

local BatchingConsumer = {}
BatchingConsumer.__index = BatchingConsumer

function BatchingConsumer.new(queue, http_client, options)
    options = options or {}
    return setmetatable({
        queue = queue,
        http_client = http_client,
        batch_size = options.batch_size or 12,
        output_dir = options.output_dir or "/app/output",
        save_local = options.save_local or false,
        upload_enabled = options.upload_enabled ~= false,
        logger = options.logger,
        on_batch_complete = options.on_batch_complete,  -- callback(archive_num, stats)

        archive = nil,
        archive_num = 0,
        current_batch_count = 0,

        running = false,

        stats = {
            total_archives = 0,
            total_cats = 0,
            total_bytes = 0,
            upload_errors = 0,
            write_errors = 0
        }
    }, BatchingConsumer)
end

function BatchingConsumer:log(level, message, ...)
    if self.logger then
        self.logger[level](self.logger, message, ...)
    end
end

--- Create and open a new archive
function BatchingConsumer:open_new_archive()
    self.archive_num = self.archive_num + 1
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("cats_%s_%04d.zip", timestamp, self.archive_num)
    local filepath = self.output_dir .. "/" .. filename

    self.archive = StreamingArchive.new(filepath)
    local ok, err = self.archive:open()

    if not ok then
        self:log("error", "Failed to open archive #%d: %s", self.archive_num, err)
        return false, err
    end

    self.current_batch_count = 0
    self:log("debug", "Opened new archive #%d: %s", self.archive_num, filename)
    return true
end

--- Finalize current archive and upload
function BatchingConsumer:finalize_and_upload()
    if not self.archive then
        return false, "No archive to finalize"
    end

    local archive_stats = self.archive:get_stats()
    self.archive:close()

    local zip_data = self.archive:get_data()
    local zip_size = zip_data and #zip_data or 0

    self:log("info", "Archive #%d complete: %d cats, %d bytes",
             self.archive_num, archive_stats.files, zip_size)

    self.stats.total_archives = self.stats.total_archives + 1
    self.stats.total_cats = self.stats.total_cats + archive_stats.files
    self.stats.total_bytes = self.stats.total_bytes + zip_size

    -- Upload if enabled
    if self.upload_enabled and zip_data then
        self:log("debug", "Uploading archive #%d...", self.archive_num)

        local upload_ok, upload_err = pcall(function()
            return self.http_client:upload_archive(zip_data)
        end)

        if upload_ok then
            self:log("info", "Archive #%d uploaded successfully", self.archive_num)
        else
            self:log("warn", "Failed to upload archive #%d: %s", self.archive_num, tostring(upload_err))
            self.stats.upload_errors = self.stats.upload_errors + 1
        end
    end

    if not self.save_local then
        self.archive:cleanup()
    end

    if self.on_batch_complete then
        self.on_batch_complete(self.archive_num, {
            cats = archive_stats.files,
            bytes = zip_size
        })
    end

    self.archive = nil
    return true
end

--- Main consumer loop
function BatchingConsumer:run()
    self.running = true
    self:log("info", "BatchingConsumer started (batch_size=%d)", self.batch_size)

    -- Open first archive
    local ok, err = self:open_new_archive()
    if not ok then
        self:log("error", "Failed to start: %s", err)
        self.running = false
        return
    end

    while self.running do
        local item, pop_err = self.queue:pop(1)  -- 1 second timeout

        if not self.running then
            break
        end

        if item then

            local write_ok, write_err = self.archive:add_image(item.data, item.filename)

            if write_ok then
                self.current_batch_count = self.current_batch_count + 1
                self:log("debug", "Batch %d: Added %s (%d/%d)",
                         self.archive_num, item.filename,
                         self.current_batch_count, self.batch_size)

                if self.current_batch_count >= self.batch_size then
                    self:finalize_and_upload()
                    if self.running and not self.queue:is_closed() then
                        self:open_new_archive()
                    end
                end
            elseif write_err and write_err:match("already in archive") then
                -- Skip duplicates silently (can happen after deduplicator reset)
                self:log("debug", "Batch %d: Skipping duplicate %s", self.archive_num, item.filename)
            else
                self.stats.write_errors = self.stats.write_errors + 1
                self:log("error", "Failed to write %s: %s", item.filename, write_err)
            end

        elseif pop_err == "queue closed" then
            if self.queue:is_done() then
                self:log("debug", "Queue done, finalizing...")
                break
            end
        elseif pop_err == "timeout" then
            if self.queue:is_done() then
                break
            end
        end

        copas.pause(0)
    end

    -- Finalize last archive if it has any cats
    if self.archive and self.current_batch_count > 0 then
        self:log("info", "Finalizing partial archive with %d cats", self.current_batch_count)
        self:finalize_and_upload()
    elseif self.archive then
        self.archive:cleanup()
    end

    self.running = false
    self:log("info", "BatchingConsumer stopped: %d archives, %d cats total",
             self.stats.total_archives, self.stats.total_cats)
end

function BatchingConsumer:stop()
    self.running = false
end

function BatchingConsumer:is_running()
    return self.running
end

function BatchingConsumer:get_stats()
    return {
        total_archives = self.stats.total_archives,
        total_cats = self.stats.total_cats,
        total_bytes = self.stats.total_bytes,
        upload_errors = self.stats.upload_errors,
        write_errors = self.stats.write_errors,
        current_batch = self.current_batch_count
    }
end

function BatchingConsumer:get_archive_count()
    return self.stats.total_archives
end

return BatchingConsumer
