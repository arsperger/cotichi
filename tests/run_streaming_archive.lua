#!/usr/bin/env lua
--[[
    Unit tests for StreamingArchive module
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local StreamingArchive = require("services.streaming_archive")
local zip = require("brimworks.zip")

local tests_run = 0
local tests_passed = 0

local function test(name, func)
    tests_run = tests_run + 1
    local ok, err = pcall(func)
    if ok then
        tests_passed = tests_passed + 1
        print("✓ " .. name)
    else
        print("✗ " .. name .. ": " .. tostring(err))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
              msg or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, msg)
    if not value then
        error(msg or "Expected true, got false")
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "Expected false, got true")
    end
end

local function assert_nil(value, msg)
    if value ~= nil then
        error(msg or "Expected nil, got " .. tostring(value))
    end
end

-- Helper: create fake image data
local function fake_image(size)
    size = size or 1024
    local data = {}
    for i = 1, size do
        data[i] = string.char(math.random(0, 255))
    end
    return table.concat(data)
end

print("\n=== StreamingArchive Tests ===\n")

-- Test 1: Constructor
test("new() creates archive object", function()
    local archive = StreamingArchive.new("/tmp/test_archive.zip")
    assert_false(archive:is_opened(), "not opened initially")
    assert_eq(archive:get_file_count(), 0, "no files initially")
    archive:cleanup()
end)

-- Test 2: Constructor with temp file
test("new() without path uses temp file", function()
    local archive = StreamingArchive.new()
    assert_true(archive.use_temp, "uses temp file")
    assert_true(archive.filename:match("%.zip$"), "has .zip extension")
    archive:cleanup()
end)

-- Test 3: Open archive
test("open() creates archive file", function()
    local path = "/tmp/test_open.zip"
    local archive = StreamingArchive.new(path)

    local ok, err = archive:open()
    assert_true(ok, "open should succeed")
    assert_nil(err, "no error")
    assert_true(archive:is_opened(), "is opened")

    archive:close()
    archive:cleanup()
end)

-- Test 4: Double open fails
test("open() twice fails", function()
    local archive = StreamingArchive.new("/tmp/test_double.zip")
    archive:open()

    local ok, err = archive:open()
    assert_false(ok, "second open should fail")
    assert_eq(err, "Archive already open", "error message")

    archive:close()
    archive:cleanup()
end)

-- Test 5: Add image
test("add_image() adds file to archive", function()
    local archive = StreamingArchive.new("/tmp/test_add.zip")
    archive:open()

    local ok, err = archive:add_image("fake_image_data", "cat_01.jpg")
    assert_true(ok, "add should succeed")
    assert_nil(err, "no error")
    assert_eq(archive:get_file_count(), 1, "file count")

    archive:close()
    archive:cleanup()
end)

-- Test 6: Add multiple images
test("add_image() adds multiple files", function()
    local archive = StreamingArchive.new("/tmp/test_multi.zip")
    archive:open()

    archive:add_image("data1", "cat_01.jpg")
    archive:add_image("data2", "cat_02.jpg")
    archive:add_image("data3", "cat_03.jpg")

    assert_eq(archive:get_file_count(), 3, "file count")

    local stats = archive:get_stats()
    assert_eq(stats.files, 3, "stats.files")
    assert_eq(stats.bytes, 15, "stats.bytes")  -- "data1" + "data2" + "data3" = 5+5+5

    archive:close()
    archive:cleanup()
end)

-- Test 7: Add to closed archive fails
test("add_image() to closed archive fails", function()
    local archive = StreamingArchive.new("/tmp/test_closed.zip")
    -- Not opened

    local ok, err = archive:add_image("data", "file.jpg")
    assert_false(ok, "add should fail")
    assert_eq(err, "Archive not open", "error message")
end)

-- Test 8: Add empty data fails
test("add_image() with empty data fails", function()
    local archive = StreamingArchive.new("/tmp/test_empty.zip")
    archive:open()

    local ok, err = archive:add_image("", "empty.jpg")
    assert_false(ok, "add empty should fail")
    assert_eq(err, "Empty image data", "error message")

    archive:close()
    archive:cleanup()
end)

-- Test 9: Close archive
test("close() finalizes archive", function()
    local archive = StreamingArchive.new("/tmp/test_close.zip")
    archive:open()
    archive:add_image("test", "test.jpg")

    local ok, err = archive:close()
    assert_true(ok, "close should succeed")
    assert_false(archive:is_opened(), "not opened after close")

    archive:cleanup()
end)

-- Test 10: Get data after close
test("get_data() returns ZIP binary after close", function()
    local path = "/tmp/test_getdata.zip"
    local archive = StreamingArchive.new(path)
    archive:open()
    archive:add_image("hello_world", "test.txt")
    archive:close()

    local data, err = archive:get_data()
    assert_true(data ~= nil, "data should exist")
    assert_true(#data > 0, "data should have content")
    -- ZIP signature: PK (0x50, 0x4B)
    assert_eq(data:byte(1), 0x50, "ZIP signature P")
    assert_eq(data:byte(2), 0x4B, "ZIP signature K")

    archive:cleanup()
end)

-- Test 11: Get data while open fails
test("get_data() while open fails", function()
    local archive = StreamingArchive.new("/tmp/test_getdata_open.zip")
    archive:open()

    local data, err = archive:get_data()
    assert_nil(data, "data should be nil")
    assert_true(err:match("still open"), "error about open state")

    archive:close()
    archive:cleanup()
end)

-- Test 12: Created archive is valid ZIP
test("created archive is valid ZIP", function()
    local path = "/tmp/test_valid.zip"
    local archive = StreamingArchive.new(path)
    archive:open()
    archive:add_image("image_content_1", "cat_01.jpg")
    archive:add_image("image_content_2", "cat_02.jpg")
    archive:close()

    -- Verify with brimworks.zip
    local reader = zip.open(path)
    assert_true(reader ~= nil, "can open created ZIP")

    local count = reader:get_num_files()
    assert_eq(count, 2, "ZIP contains 2 files")

    reader:close()
    archive:cleanup()
end)

-- Test 13: get_stats()
test("get_stats() returns correct info", function()
    local archive = StreamingArchive.new("/tmp/test_stats.zip")
    archive:open()
    archive:add_image("12345", "a.jpg")  -- 5 bytes
    archive:add_image("67890", "b.jpg")  -- 5 bytes

    local stats = archive:get_stats()
    assert_eq(stats.files, 2, "files count")
    assert_eq(stats.bytes, 10, "total bytes")
    assert_true(stats.is_open, "is_open")

    archive:close()

    stats = archive:get_stats()
    assert_false(stats.is_open, "not open after close")

    archive:cleanup()
end)

-- Test 14: get_path()
test("get_path() returns file path", function()
    local path = "/tmp/test_path.zip"
    local archive = StreamingArchive.new(path)
    assert_eq(archive:get_path(), path, "path matches")
    archive:cleanup()
end)

-- Summary
print(string.format("\n=== Results: %d/%d tests passed ===\n", tests_passed, tests_run))

if tests_passed == tests_run then
    os.exit(0)
else
    os.exit(1)
end
