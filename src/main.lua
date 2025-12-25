#!/usr/bin/env lua
--[[
    Cat Archive Service - Main Entry Point
    Forever fetch cats , zip them and upload to remote host

    Use:
        lua src/main.lua
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local copas = require("copas")
local config = require("config")
local Logger = require("utils.logger")
local HttpClient = require("client.http_client")
local ImageQueue = require("services.image_queue")
local StreamingFetcher = require("services.streaming_fetcher")
local BatchingConsumer = require("services.batching_consumer")

local shutdown_requested = false
local current_archive_num = 0

local stats = {
    total_archives = 0,
    total_cats = 0,
    total_errors = 0,
    fetch_errors = 0,
    zip_errors = 0,
    upload_errors = 0,
    partial_archives = 0,
    start_time = os.time()
}

local log = Logger.new(config.logging.level)

local COLORS = {
    RESET = "\27[0m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    CYAN = "\27[36m",
    BOLD = "\27[1m"
}

local function print_banner()
    print(COLORS.CYAN .. [[
   ___      _   _      _     _
  / __\__ _| |_(_) ___| |__ (_)
 / /  / _` | __| |/ __| '_ \| |
/ /__| (_| | |_| | (__| | | | |
\____/\__,_|\__|_|\___|_| |_|_|

    ]] .. COLORS.RESET)
    print(COLORS.BOLD .. "Cat Archive Service v1.0" .. COLORS.RESET)
    print("Collecting cats and creating ZIP archives\n")
end

local function print_stats(archive_num, cats_count, duration, zip_size)
    print(string.format(
        COLORS.GREEN .. "[Archive #%d]" .. COLORS.RESET ..
        " %d cats | %.2fs | %d bytes",
        archive_num, cats_count, duration, zip_size
    ))
end

local function print_final_stats()
    local uptime = os.time() - stats.start_time
    local hours = math.floor(uptime / 3600)
    local mins = math.floor((uptime % 3600) / 60)
    local secs = uptime % 60

    print("\n" .. COLORS.CYAN .. "=== Final Statistics ===" .. COLORS.RESET)
    print(string.format("  Uptime: %02d:%02d:%02d", hours, mins, secs))
    print(string.format("  Total archives: %d", stats.total_archives))
    print(string.format("  Total cats collected: %d", stats.total_cats))
    print(string.format("  Partial archives: %d", stats.partial_archives))
    print(string.format("  Total errors: %d (fetch: %d, zip: %d, upload: %d)",
        stats.total_errors, stats.fetch_errors, stats.zip_errors, stats.upload_errors))
    if stats.total_archives > 0 then
        print(string.format("  Avg cats per archive: %.1f", stats.total_cats / stats.total_archives))
        print(string.format("  Archives per minute: %.2f", stats.total_archives / (uptime / 60)))
    end
    print(COLORS.CYAN .. "=========================" .. COLORS.RESET)
end

local function save_stats_to_file()
    local uptime = os.time() - stats.start_time
    local hours = math.floor(uptime / 3600)
    local mins = math.floor((uptime % 3600) / 60)
    local secs = uptime % 60

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    -- Use fixed filename so it gets overwritten each time
    local filename = config.archive.output_dir .. "/stats.txt"

    local content = string.format([[
=== Cotichi Service Statistics ===
Generated: %s

Uptime: %02d:%02d:%02d
Total archives created: %d
Total cats collected: %d
Partial archives (< 12 cats): %d

Errors:
  Total: %d
  Fetch errors: %d
  ZIP errors: %d
  Upload errors: %d

Performance:
  Avg cats per archive: %.1f
  Archives per minute: %.2f

=====================================
]],
        timestamp,
        hours, mins, secs,
        stats.total_archives,
        stats.total_cats,
        stats.partial_archives,
        stats.total_errors,
        stats.fetch_errors,
        stats.zip_errors,
        stats.upload_errors,
        stats.total_archives > 0 and (stats.total_cats / stats.total_archives) or 0,
        uptime > 0 and (stats.total_archives / (uptime / 60)) or 0
    )

    local file, err = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        log:info("Statistics saved to: %s", filename)
        return filename
    else
        log:error("Failed to save statistics: %s", tostring(err))
        return nil
    end
end

local MIN_CATS_FOR_ARCHIVE = 1

--- Continuous streaming pipeline (workers + batching consumer)
local function run_service_streaming()

    log:info("Initializing continuous streaming pipeline...")

    local http_client = HttpClient.new(
        config:get_base_url(),
        {
            endpoint = config.cat_api.endpoint,
            timeout = config.async.timeout,
            retry_count = config.async.retry_count,
            retry_delay = config.async.retry_delay
        }
    )

    local target_count = config.archive.target_count
    local num_workers = config.async.num_workers

    log:info("Streaming Configuration:")
    log:info("  API URL: %s", config:get_api_url())
    log:info("  Batch size: %d cats per archive", target_count)
    log:info("  Workers: %d (continuous fetching)", num_workers)
    log:info("  Queue size: %d", config.streaming.queue_size)

    print("\n" .. COLORS.YELLOW .. "Starting continuous streaming... Press Ctrl+C to stop" .. COLORS.RESET .. "\n")

    -- Create shared queue
    local queue = ImageQueue.new(config.streaming.queue_size)

    -- Create fetcher (workers)
    local fetcher = StreamingFetcher.new(http_client, {
        num_workers = num_workers,
        logger = log
    })

    -- Create batching consumer (handles archive creation, upload, cycling)
    local consumer = BatchingConsumer.new(queue, http_client, {
        batch_size = target_count,
        output_dir = config.archive.output_dir,
        save_local = config.archive.save_local,
        upload_enabled = config.upload.enabled,
        logger = log,
        on_batch_complete = function(archive_num, batch_stats)
            -- Update global stats
            stats.total_archives = stats.total_archives + 1
            stats.total_cats = stats.total_cats + batch_stats.cats

            -- Reset deduplicator for next archive (allow duplicates between archives)
            fetcher:reset_deduplicator()

            -- Print progress
            print_stats(archive_num, batch_stats.cats, 0, batch_stats.bytes)

            -- Save stats after every archive (in case of crash/kill)
            save_stats_to_file()

            -- Periodic console stats dump
            if stats.total_archives % 10 == 0 then
                print_final_stats()
            end
        end
    })

    -- Start fetcher (workers run continuously)
    fetcher:start(queue)
    log:info("Started %d workers (continuous fetching)", num_workers)

    -- Monitor for shutdown in separate coroutine
    copas.addthread(function()
        while not shutdown_requested do
            copas.pause(0.5)
        end
        log:info("Shutdown requested, stopping pipeline...")
        consumer:stop()
        queue:close()
        fetcher:stop()

        -- Wait for components to finish, with timeout
        local timeout = 5
        local start = os.time()
        while (consumer:is_running() or fetcher:is_running()) and (os.time() - start < timeout) do
            copas.pause(0.2)
        end

        -- Force exit copas loop
        log:info("Exiting event loop...")
    end)

    -- Run consumer (blocks until stopped)
    copas.addthread(function()
        consumer:run()
    end)

    -- Run event loop
    copas.loop()

    -- Sync stats from components
    local consumer_stats = consumer:get_stats()
    local fetcher_stats = fetcher:get_stats()

    stats.total_archives = consumer_stats.total_archives
    stats.total_cats = consumer_stats.total_cats
    stats.upload_errors = consumer_stats.upload_errors or 0
    stats.zip_errors = consumer_stats.write_errors or 0
    stats.fetch_errors = fetcher_stats.errors or 0
    stats.total_errors = stats.fetch_errors + stats.zip_errors + stats.upload_errors

    log:info("Streaming stopped:")
    log:info("  Archives created: %d", consumer_stats.total_archives)
    log:info("  Total cats: %d", consumer_stats.total_cats)
    log:info("  Fetched: %d, Duplicates: %d, Errors: %d",
             fetcher_stats.fetched, fetcher_stats.duplicates, fetcher_stats.errors)

    print_final_stats()
    save_stats_to_file()
end

--- helpers

local function handle_shutdown(signum)
    local signame = signum == 2 and "SIGINT" or signum == 15 and "SIGTERM" or tostring(signum)

    if shutdown_requested then
        log:warn("Force shutdown requested (%s), exiting immediately", signame)
        print("\nForce exit! Saving stats...")
        print_final_stats()
        save_stats_to_file()
        os.exit(1)
    end

    shutdown_requested = true
    print("\n" .. COLORS.YELLOW .. string.format("Signal %s received, graceful shutdown...", signame) .. COLORS.RESET)
    log:info("Graceful shutdown initiated (signal: %s)", signame)

    -- Save stats immediately in case we don't get to clean exit
    print_final_stats()
    save_stats_to_file()
end

--- Entry
local function main()
    print_banner()
    config:dump()

    local signal_ok, signal = pcall(require, "posix.signal")
    if signal_ok and signal then
        signal.signal(signal.SIGINT, handle_shutdown)
        signal.signal(signal.SIGTERM, handle_shutdown)
        log:info("Signal handlers installed (SIGINT, SIGTERM)")
    else
        log:warn("posix.signal not available, Ctrl+C will terminate immediately")
    end

    log:info("Using streaming pipeline mode")

    -- run the cats ^^
    copas.addthread(function()
        local ok, err = pcall(run_service_streaming)
        if not ok then
            log:error("Service error: %s", tostring(err))
            print_final_stats()
            save_stats_to_file()
        end
    end)

    -- run event loop
    log:info("Starting copas event loop...")
    copas.loop()

    print(COLORS.GREEN .. "\nGoodbye! [Cotichi]" .. COLORS.RESET)
end

-- Start
main()
