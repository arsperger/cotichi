--[[
    Fetcher Module
]]

local copas = require("copas")

local Fetcher = {}
Fetcher.__index = Fetcher

--- New Fetcher
-- @param config table {http_client, deduplicator, logger}
-- @return Fetcher
function Fetcher.new(config)
    config = config or {}
    return setmetatable({
        http_client = config.http_client,
        deduplicator = config.deduplicator,
        logger = config.logger,
        results = {},
        running = false,
        stop_flag = false
    }, Fetcher)
end

function Fetcher:log(level, message, ...)
    if self.logger then
        self.logger[level](self.logger, message, ...)
    end
end

--- Worker for cats fetching
-- @param worker_id number ID
-- @param target_count number of cats
function Fetcher:worker(worker_id, target_count)
    self:log("debug", "Worker %d started", worker_id)

    while not self.stop_flag do

        local current_count = #self.results

        if current_count >= target_count then
            self:log("debug", "Worker %d stopping (target reached)", worker_id)
            break
        end

        local image_data, err = self.http_client:fetch_cat()

        if image_data then

            -- atomic as no yield

            if #self.results >= target_count then
                break
            end

            local is_unique = self.deduplicator:try_add(image_data)

            if is_unique then
                table.insert(self.results, image_data)
                local count = #self.results

                self:log("info", "Worker %d: Got unique cat #%d (%d bytes)",
                         worker_id, count, #image_data)
                print(string.format("  [Worker %d] Cat #%d (%d bytes)",
                      worker_id, count, #image_data))
            else
                self:log("debug", "Worker %d: Duplicate detected, skipping", worker_id)
            end
        else
            self:log("warn", "Worker %d: Error - %s", worker_id, err or "unknown")
        end

        copas.sleep(0.01)
    end

    self:log("debug", "Worker %d finished", worker_id)
end

--- fetch unique cats
-- @param target_count number (default 12)
-- @param num_workers number (default 12)
-- @param timeout number (default 60)
-- @return table binary array with images
function Fetcher:fetch_unique(target_count, num_workers, timeout)
    target_count = target_count or 12
    num_workers = num_workers or 12
    timeout = timeout or 60

    -- reset
    self.results = {}
    self.stop_flag = false
    self.running = true

    print(string.format("Starting %d workers to fetch %d unique cats...",
          num_workers, target_count))

    local start_time = os.time()

    -- run workers
    for i = 1, num_workers do
        copas.addthread(function()
            self:worker(i, target_count)
        end)
    end

    while #self.results < target_count and not self.stop_flag do
        if os.time() - start_time > timeout then
            self:log("warn", "Fetch timeout after %d seconds, got %d/%d cats",
                     timeout, #self.results, target_count)
            break
        end
        copas.sleep(0.1)
    end

    self.stop_flag = true

    -- wait all to finish
    copas.sleep(0.2)

    self.running = false

    print(string.format("Fetched %d unique cats", #self.results))

    return self.results
end

function Fetcher:stop()
    self.stop_flag = true
end

function Fetcher:is_running()
    return self.running
end

function Fetcher:get_count()
    return #self.results
end

return Fetcher
