--[[
    StreamingFetcher Module

    Fetches cat images and pushes them to ImageQueue for streaming pipeline.
    Supports two modes:
    - count: fetch exactly N unique images
    - duration: fetch for T seconds (as many as possible)
]]

local copas = require("copas")
local Deduplicator = require("services.deduplicator")

local StreamingFetcher = {}
StreamingFetcher.__index = StreamingFetcher

function StreamingFetcher.new(http_client, options)
    options = options or {}
    return setmetatable({
        http_client = http_client,
        deduplicator = Deduplicator.new(),
        num_workers = options.num_workers or 12,
        logger = options.logger,
        running = false,
        stats = {
            fetched = 0,
            duplicates = 0,
            errors = 0
        }
    }, StreamingFetcher)
end

--- Log helper
function StreamingFetcher:log(level, message, ...)
    if self.logger then
        self.logger[level](self.logger, message, ...)
    end
end

function StreamingFetcher:worker(worker_id, queue)
    self:log("debug", "Worker %d started", worker_id)

    while self.running do

        if queue:is_closed() then
            self:log("debug", "Worker %d stopping (queue closed)", worker_id)
            break
        end

        -- get a cat ^^
        local image_data, err = self.http_client:fetch_cat()

        if image_data then

            -- Check again after fetch (queue may have been closed)
            if queue:is_closed() then
                break
            end

            -- Atomic dedup check and add
            local is_unique, md5_hash = self.deduplicator:try_add(image_data)

            if is_unique then

                local filename = string.format("cat_%s.jpg", md5_hash:sub(1, 8))

                local ok, push_err = queue:push(image_data, filename)

                if ok then
                    self.stats.fetched = self.stats.fetched + 1
                    self:log("info", "Worker %d: Got cat #%d (%d bytes) -> %s",
                             worker_id, self.stats.fetched, #image_data, filename)
                else
                    self:log("warn", "Worker %d: Queue push failed: %s", worker_id, push_err)
                end
            else
                self.stats.duplicates = self.stats.duplicates + 1
                self:log("debug", "Worker %d: Duplicate detected (hash: %s...)",
                         worker_id, md5_hash:sub(1, 8))
            end
        else
            self.stats.errors = self.stats.errors + 1
            self:log("warn", "Worker %d: Fetch error - %s", worker_id, err or "unknown")
        end

        copas.pause(0.01)
    end

    self:log("debug", "Worker %d finished", worker_id)
end

--- Start workers (they run until stop() is called or queue is closed)
function StreamingFetcher:start(queue)
    self:reset()
    self.running = true

    self:log("info", "Starting %d workers...", self.num_workers)

    for i = 1, self.num_workers do
        copas.addthread(function()
            self:worker(i, queue)
        end)
    end
end

function StreamingFetcher:stop()
    self.running = false
end

function StreamingFetcher:is_running()
    return self.running
end

function StreamingFetcher:get_stats()
    return {
        fetched = self.stats.fetched,
        duplicates = self.stats.duplicates,
        errors = self.stats.errors
    }
end

function StreamingFetcher:get_count()
    return self.stats.fetched
end

function StreamingFetcher:reset_deduplicator()
    self.deduplicator:reset()
    self:log("debug", "Deduplicator reset (new archive cycle)")
end

function StreamingFetcher:reset()
    self.stats = {
        fetched = 0,
        duplicates = 0,
        errors = 0
    }
    self.deduplicator:reset()
    self.running = false
end

return StreamingFetcher
