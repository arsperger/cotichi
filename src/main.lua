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
local Deduplicator = require("services.deduplicator")
local Fetcher = require("services.fetcher")
local ArchiveBuilder = require("services.archive")

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
    MAGENTA = "\27[35m",
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
    local filename = config.archive.output_dir .. "/stats_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"

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

--- main service cycle
local function run_service()

    log:info("Initializing components...")

    local http_client = HttpClient.new(
        config:get_base_url(),
        {
            timeout = config.async.timeout,
            retry_count = config.async.retry_count,
            retry_delay = config.async.retry_delay
        }
    )

    local deduplicator = Deduplicator.new()

    local fetcher = Fetcher.new({
        http_client = http_client,
        deduplicator = deduplicator
    })

    local archive_builder = ArchiveBuilder.new({
        filename_pattern = config.archive.filename_pattern
    })

    local target_count = config.archive.target_count
    local num_workers = config.async.num_workers

    log:info("Configuration:")
    log:info("  API URL: %s", config:get_cat_url())
    log:info("  Target count: %d cats per archive", target_count)
    log:info("  Workers: %d (max concurrent connections)", num_workers)

    print("\n" .. COLORS.YELLOW .. "Starting infinite loop... Press Ctrl+C to stop" .. COLORS.RESET .. "\n")

    -- forever
    while not shutdown_requested do

        current_archive_num = current_archive_num + 1
        local start_time = os.clock()

        log:info("=== Starting archive #%d ===", current_archive_num)

        deduplicator:reset()

        log:debug("Fetching %d unique cats with %d workers (timeout: %ds)...",
                  target_count, num_workers, config.async.fetch_timeout)

        local fetch_ok, images_or_err, fetch_err = pcall(function()
            return fetcher:fetch_unique(target_count, num_workers, config.async.fetch_timeout)
        end)

        local images
        if not fetch_ok then
            log:error("Fetch crashed: %s", tostring(images_or_err))
            stats.fetch_errors = stats.fetch_errors + 1
            stats.total_errors = stats.total_errors + 1
            copas.sleep(5)
            goto continue
        end

        images = images_or_err

        if not images or #images < MIN_CATS_FOR_ARCHIVE then
            log:error("Failed to fetch enough cats: got %d, need %d",
                      images and #images or 0, MIN_CATS_FOR_ARCHIVE)
            stats.fetch_errors = stats.fetch_errors + 1
            stats.total_errors = stats.total_errors + 1
            copas.sleep(5)
            goto continue
        end

        -- Graceful degradation: got less than target_count
        if #images < target_count then
            log:warn("Partial fetch: got %d/%d cats (graceful degradation)", #images, target_count)
            stats.partial_archives = stats.partial_archives + 1
        end

        log:info("Fetched %d unique cats", #images)
        stats.total_cats = stats.total_cats + #images

        -- stopped?
        if shutdown_requested then
            log:info("Shutdown requested, skipping archive creation")
            break
        end

        log:debug("Building ZIP archive...")
        local zip_ok, zip_data_or_err, zip_err = pcall(function()
            return archive_builder:build_zip(images)
        end)

        local zip_data
        if not zip_ok then
            log:error("ZIP creation crashed: %s", tostring(zip_data_or_err))
            stats.zip_errors = stats.zip_errors + 1
            stats.total_errors = stats.total_errors + 1
            goto continue
        end

        zip_data = zip_data_or_err

        if not zip_data then
            log:error("Failed to create ZIP: %s", tostring(zip_err))
            stats.zip_errors = stats.zip_errors + 1
            stats.total_errors = stats.total_errors + 1
            goto continue
        end

        local elapsed = os.clock() - start_time
        print_stats(current_archive_num, #images, elapsed, #zip_data)
        stats.total_archives = stats.total_archives + 1

        -- save localy if enabled
        if config.archive.save_local then
            local timestamp = os.date("%Y%m%d_%H%M%S")
            local filename = string.format("cats_%s_%04d.zip", timestamp, current_archive_num)
            local filepath = config.archive.output_dir .. "/" .. filename

            local file, file_err = io.open(filepath, "wb")
            if file then
                file:write(zip_data)
                file:close()
                log:info("Archive saved locally: %s", filename)
            else
                log:warn("Failed to save archive locally: %s", tostring(file_err))
            end
        end

        -- send zipped cats back
        if config.upload.enabled then
            log:debug("Uploading archive to server...")

            local upload_pcall_ok, upload_ok, upload_err = pcall(function()
                return http_client:upload_archive(zip_data)
            end)

            if not upload_pcall_ok then
                log:error("Upload crashed: %s", tostring(upload_ok))
                stats.upload_errors = stats.upload_errors + 1
                stats.total_errors = stats.total_errors + 1
            elseif upload_ok then
                log:info("Archive #%d uploaded successfully", current_archive_num)
            else
                log:warn("Failed to upload archive: %s", tostring(upload_err))
                stats.upload_errors = stats.upload_errors + 1
                stats.total_errors = stats.total_errors + 1
            end
        end

        -- info
        if stats.total_archives % 10 == 0 then
            print_final_stats()
        end

        -- take a break if needed
        if config.service.cycle_delay > 0 and not shutdown_requested then
            log:debug("Waiting %d seconds before next cycle...", config.service.cycle_delay)
            copas.sleep(config.service.cycle_delay)
        end

        ::continue::
    end

    log:info("Service stopped. Total archives created: %d", stats.total_archives)
    print_final_stats()
    save_stats_to_file()
end

--- helpers

local function handle_shutdown(signum)
    local signame = signum == 2 and "SIGINT" or signum == 15 and "SIGTERM" or tostring(signum)

    if shutdown_requested then
        log:warn("Force shutdown requested (%s), exiting immediately", signame)
        print(COLORS.RED .. "\nForce exit! Saving stats..." .. COLORS.RESET)
        print_final_stats()
        save_stats_to_file()
        os.exit(1)
    end

    shutdown_requested = true
    print("\n" .. COLORS.YELLOW .. string.format("Signal %s received, finishing current archive...", signame) .. COLORS.RESET)
    log:info("Graceful shutdown initiated (signal: %s)", signame)
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

    -- run the cats ^^
    copas.addthread(function()
        local ok, err = pcall(run_service)
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
