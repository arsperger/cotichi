FROM alpine:3.19

# Install Lua, LuaRocks and system dependencies
RUN apk add --no-cache \
    lua5.4 \
    lua5.4-dev \
    luarocks5.4 \
    build-base \
    openssl-dev \
    libzip-dev \
    curl

RUN ln -sf /usr/bin/lua5.4 /usr/bin/lua && \
    ln -sf /usr/bin/luarocks-5.4 /usr/bin/luarocks

WORKDIR /app

RUN luarocks install copas && \
    luarocks install luasocket && \
    luarocks install md5 && \
    luarocks install lua-zip && \
    luarocks install luaposix

COPY src/ ./src/
COPY tests/ ./tests/

ENTRYPOINT ["lua", "src/main.lua"]
