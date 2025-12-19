--[[
    Configuration Module
    Use:
        local config = require("config")
        print(config.cat_api.base_url)
        print(config:get_cat_url())
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
        endpoint = os.getenv("UPLOAD_ENDPOINT") or "/cat"
    },

    async = {
        num_workers = tonumber(os.getenv("NUM_WORKERS")) or 12,
        timeout = tonumber(os.getenv("TIMEOUT")) or 20,
        fetch_timeout = tonumber(os.getenv("FETCH_TIMEOUT")) or 60,
        retry_count = tonumber(os.getenv("RETRY_COUNT")) or 3,
        retry_delay = tonumber(os.getenv("RETRY_DELAY")) or 1
    },

    archive = {
        target_count = tonumber(os.getenv("TARGET_COUNT")) or 12,
        filename_pattern = os.getenv("FILENAME_PATTERN") or "cat_%02d.jpg",
        output_dir = os.getenv("OUTPUT_DIR") or "/app/output",
        save_local = os.getenv("SAVE_LOCAL") == "true" or os.getenv("SAVE_LOCAL") == "1"
    },

    logging = {
        level = os.getenv("LOG_LEVEL") or "INFO",  -- DEBUG, INFO, WARN, ERROR
        -- timestamps = os.getenv("LOG_TIMESTAMPS") ~= "false",
        -- colors = os.getenv("LOG_COLORS") ~= "false"
    },

    service = {
        name = os.getenv("SERVICE_NAME") or "cotichi",
        -- Delay between archive cycles (seconds, 0 = no delay)
        cycle_delay = tonumber(os.getenv("CYCLE_DELAY")) or 0
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

--- Get URL for fetching cats
-- @return string Full cat fetch URL
function config:get_cat_url()
    return self:get_base_url() .. self.cat_api.endpoint
end

--- Get URL for uploading archives
-- @return string Full upload URL
function config:get_upload_url()
    return self:get_base_url() .. self.upload.endpoint
end


function config:dump()
    print("=== Configuration ===")
    print("Cat API URL: " .. self:get_cat_url())
    print("Upload URL: " .. self:get_upload_url())
    print("Use Debug API: " .. tostring(self.cat_api.use_debug))
    print("Num Workers: " .. self.async.num_workers)
    print("Target Count: " .. self.archive.target_count)
    print("Log Level: " .. self.logging.level)
    print("=====================")
end

return config
