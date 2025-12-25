--[[
    Configuration Module
]]

local config = {

    cat_api = {
        base_url = os.getenv("CAT_API_URL") or "http://algisothal.ru:8889",
        debug_url = os.getenv("CAT_API_DEBUG_URL") or "http://algisothal.ru:8890",
        endpoint = "/cat",
        use_debug = os.getenv("USE_DEBUG_API") == "true" or os.getenv("USE_DEBUG_API") == "1"
    },

    upload = {
        enabled = os.getenv("UPLOAD_ENABLED") ~= "false",
    },

    async = {
        num_workers = tonumber(os.getenv("NUM_WORKERS")) or 24,
        timeout = tonumber(os.getenv("TIMEOUT")) or 20,
        retry_count = tonumber(os.getenv("RETRY_COUNT")) or 3,
        retry_delay = tonumber(os.getenv("RETRY_DELAY")) or 1
    },

    archive = {
        target_count = tonumber(os.getenv("TARGET_COUNT")) or 12,
        output_dir = os.getenv("OUTPUT_DIR") or "/app/output",
        save_local = os.getenv("SAVE_LOCAL") == "true" or os.getenv("SAVE_LOCAL") == "1"
    },

    logging = {
        level = os.getenv("LOG_LEVEL") or "INFO",  -- DEBUG, INFO, WARN, ERROR
    },

    streaming = {
        -- Optimal: ~2x target_count for buffering
        queue_size = tonumber(os.getenv("QUEUE_SIZE")) or 25
    }
}

--- Get API base URL (production or debug)
-- @return string Base URL for cat API
function config:get_base_url()
    if self.cat_api.use_debug then
        return self.cat_api.debug_url
    end
    return self.cat_api.base_url
end

--- Get full API URL (fetch and upload use the same endpoint)
-- @return string Full API URL
function config:get_api_url()
    return self:get_base_url() .. self.cat_api.endpoint
end


function config:dump()
    print("=== Configuration ===")
    print("API URL: " .. self:get_api_url())
    print("Use Debug API: " .. tostring(self.cat_api.use_debug))
    print("Num Workers: " .. self.async.num_workers)
    print("Target Count: " .. self.archive.target_count)
    print("Queue Size: " .. self.streaming.queue_size)
    print("Log Level: " .. self.logging.level)
    print("=====================")
end

return config
