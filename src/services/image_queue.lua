--[[
    ImageQueue Module

    Producer-Consumer queue for streaming pipeline.
    Workers (producers) push images, ArchiveConsumer (consumer) pops them.

    Features:
    - Bounded queue with backpressure
    - Blocking pop with timeout
    - Close signal for graceful shutdown
]]

local copas = require("copas")

local ImageQueue = {}
ImageQueue.__index = ImageQueue

function ImageQueue.new(max_size)
    return setmetatable({
        queue = {},
        max_size = max_size or 50,
        closed = false,
        total_pushed = 0,
        total_popped = 0
    }, ImageQueue)
end

--- Push image
function ImageQueue:push(image_data, filename)
    if self.closed then
        return false, "queue closed"
    end

    -- wait if queue is full
    while #self.queue >= self.max_size and not self.closed do
        copas.pause(0.05)
    end

    if self.closed then
        return false, "queue closed"
    end

    table.insert(self.queue, {
        data = image_data,
        filename = filename,
        timestamp = os.time()
    })

    self.total_pushed = self.total_pushed + 1
    return true
end

--- Pop image from queue
-- Blocks until item available or timeout
function ImageQueue:pop(timeout)
    timeout = timeout or 5
    local start_time = os.time()

    while #self.queue == 0 and not self.closed do
        if os.time() - start_time >= timeout then
            return nil, "timeout"
        end
        copas.pause(0.05)
    end

    if #self.queue > 0 then
        local item = table.remove(self.queue, 1)
        self.total_popped = self.total_popped + 1
        return item
    end

    return nil, "queue closed"
end

--- Try to pop without blocking
-- @return table|nil Item or nil if empty
function ImageQueue:try_pop()
    if #self.queue > 0 then
        local item = table.remove(self.queue, 1)
        self.total_popped = self.total_popped + 1
        return item
    end
    return nil
end

function ImageQueue:close()
    self.closed = true
end

function ImageQueue:is_done()
    return self.closed and #self.queue == 0
end

function ImageQueue:is_closed()
    return self.closed
end

function ImageQueue:size()
    return #self.queue
end

function ImageQueue:is_empty()
    return #self.queue == 0
end

function ImageQueue:is_full()
    return #self.queue >= self.max_size
end

function ImageQueue:get_stats()
    return {
        size = #self.queue,
        max_size = self.max_size,
        pushed = self.total_pushed,
        popped = self.total_popped,
        closed = self.closed
    }
end

function ImageQueue:reset()
    self.queue = {}
    self.closed = false
    self.total_pushed = 0
    self.total_popped = 0
end

return ImageQueue
