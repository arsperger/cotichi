#!/usr/bin/env lua
--[[
    Archive Builder Test Suite
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local ArchiveBuilder = require("services.archive")
local zip = require("brimworks.zip")

local GREEN = "\27[32m"
local RED = "\27[31m"
local YELLOW = "\27[33m"
local RESET = "\27[0m"

local function log(color, ...)
    io.write(color)
    print(...)
    io.write(RESET)
    io.flush()
end

local function create_test_image(size)
    local data = {}
    for i = 1, size or 100 do
        data[i] = string.char(math.random(0, 255))
    end
    return table.concat(data)
end

local function generate_test_images(count)
    local images = {}
    for i = 1, count do
        math.randomseed(i * 12345)
        images[i] = create_test_image(100 + i * 10)
    end
    return images
end

local tests_passed = 0
local tests_failed = 0

-- ============== TEST 1: Creating ArchiveBuilder ==============
do
    print("\n" .. YELLOW .. "[TEST 1] Creating ArchiveBuilder..." .. RESET)
    local builder = ArchiveBuilder.new()
    assert(builder, "Builder should be created")
    assert(builder.filename_pattern == "cat_%02d.jpg", "Default pattern should be set")
    local custom = ArchiveBuilder.new({ filename_pattern = "image_%03d.png" })
    assert(custom.filename_pattern == "image_%03d.png", "Custom pattern should be used")
    log(GREEN, "[TEST 1] Builder creation - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 2: Filename generation ==============
do
    print("\n" .. YELLOW .. "[TEST 2] Filename generation..." .. RESET)
    local builder = ArchiveBuilder.new()
    assert(builder:get_filename(1) == "cat_01.jpg", "First file should be cat_01.jpg")
    assert(builder:get_filename(5) == "cat_05.jpg", "Fifth file should be cat_05.jpg")
    assert(builder:get_filename(12) == "cat_12.jpg", "Twelfth file should be cat_12.jpg")
    local custom = ArchiveBuilder.new({ filename_pattern = "kitty_%d.jpeg" })
    assert(custom:get_filename(1) == "kitty_1.jpeg", "Custom pattern should work")
    log(GREEN, "[TEST 2] Filename generation - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 3: Build ZIP in memory ==============
do
    print("\n" .. YELLOW .. "[TEST 3] Build ZIP in memory..." .. RESET)
    local builder = ArchiveBuilder.new()
    local images = generate_test_images(5)
    local zip_data, err = builder:build_zip(images)
    if not zip_data then
        log(RED, "[TEST 3] Build ZIP in memory - FAILED: " .. tostring(err))
        tests_failed = tests_failed + 1
    else
        assert(#zip_data > 0, "ZIP data should not be empty")
        assert(zip_data:sub(1, 2) == "PK", "ZIP should start with PK signature")
        log(GREEN, "[TEST 3] Build ZIP in memory - PASSED (size: " .. #zip_data .. " bytes)")
        tests_passed = tests_passed + 1
    end
end

-- ============== TEST 4: Save ZIP to file ==============
do
    print("\n" .. YELLOW .. "[TEST 4] Save ZIP to file..." .. RESET)
    local builder = ArchiveBuilder.new()
    local images = generate_test_images(3)
    local test_path = os.tmpname() .. "_test.zip"
    local path, err = builder:save_zip(images, test_path)
    if not path then
        log(RED, "[TEST 4] Save ZIP to file - FAILED: " .. tostring(err))
        tests_failed = tests_failed + 1
    else
        local f = io.open(path, "rb")
        assert(f, "ZIP file should exist")
        local content = f:read("*a")
        f:close()
        assert(#content > 0, "ZIP file should not be empty")
        assert(content:sub(1, 2) == "PK", "ZIP should have correct signature")
        os.remove(path)
        log(GREEN, "[TEST 4] Save ZIP to file - PASSED")
        tests_passed = tests_passed + 1
    end
end

-- ============== TEST 5: Verify ZIP contents ==============
do
    print("\n" .. YELLOW .. "[TEST 5] Verify ZIP contents..." .. RESET)
    local builder = ArchiveBuilder.new()
    local images = generate_test_images(4)
    local test_path = os.tmpname() .. "_verify.zip"
    local path, err = builder:save_zip(images, test_path)
    if not path then
        log(RED, "[TEST 5] Verify ZIP contents - FAILED: " .. tostring(err))
        tests_failed = tests_failed + 1
    else
        local archive, open_err = zip.open(path)
        if not archive then
            log(RED, "[TEST 5] Verify ZIP contents - FAILED: Cannot open archive: " .. tostring(open_err))
            tests_failed = tests_failed + 1
        else
            local file_count = 0
            local expected_names = {
                "cat_01.jpg", "cat_02.jpg", "cat_03.jpg", "cat_04.jpg"
            }
            local found_names = {}
            local num_files = archive:get_num_files()
            for i = 1, num_files do
                local stat = archive:stat(i)
                if stat then
                    file_count = file_count + 1
                    found_names[stat.name] = true
                end
            end
            archive:close()
            assert(file_count == 4, "Archive should contain 4 files, got " .. file_count)
            for _, name in ipairs(expected_names) do
                assert(found_names[name], "Archive should contain " .. name)
            end
            os.remove(path)
            log(GREEN, "[TEST 5] Verify ZIP contents - PASSED (4 files)")
            tests_passed = tests_passed + 1
        end
    end
end

-- ============== TEST 6: Handle empty images array ==============
do
    print("\n" .. YELLOW .. "[TEST 6] Handle empty images array..." .. RESET)
    local builder = ArchiveBuilder.new()
    local zip_data, err = builder:build_zip({})
    assert(zip_data == nil, "Should return nil for empty array")
    assert(err ~= nil, "Should return error message")
    local path, err2 = builder:save_zip({})
    assert(path == nil, "Should return nil for empty array")
    assert(err2 ~= nil, "Should return error message")
    log(GREEN, "[TEST 6] Handle empty images - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 7: Build ZIP with 12 cats (production size) ==============
do
    print("\n" .. YELLOW .. "[TEST 7] Build ZIP with 12 cats (production size)..." .. RESET)
    local builder = ArchiveBuilder.new()
    local images = generate_test_images(12)
    local test_path = os.tmpname() .. "_12cats.zip"
    local start_time = os.clock()
    local path, err = builder:save_zip(images, test_path)
    local elapsed = os.clock() - start_time
    if not path then
        log(RED, "[TEST 7] Build ZIP with 12 cats - FAILED: " .. tostring(err))
        tests_failed = tests_failed + 1
    else
        local archive = zip.open(path)
        local file_count = archive:get_num_files()
        archive:close()
        assert(file_count == 12, "Archive should contain 12 files, got " .. file_count)
        local f = io.open(path, "rb")
        local size = f:seek("end")
        f:close()
        os.remove(path)
        log(GREEN, string.format("[TEST 7] Build ZIP with 12 cats - PASSED (%.3fs, %d bytes)", elapsed, size))
        tests_passed = tests_passed + 1
    end
end

-- ============== SUMMARY ==============
print("\n" .. string.rep("=", 50))
if tests_failed == 0 then
    log(GREEN, string.format("All Archive Tests PASSED (%d/%d)", 
        tests_passed, tests_passed + tests_failed))
else
    log(RED, string.format("Archive Tests: %d PASSED, %d FAILED", 
        tests_passed, tests_failed))
    os.exit(1)
end
