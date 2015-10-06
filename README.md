lua-nginx-tarantool
===================

Driver for tarantool 1.5 on nginx cosockets, based on https://github.com/ziontab/lua-nginx-tarantool.git

Introduction
------------

A driver for a NoSQL database in a Lua script [Tarantool](http://tarantool.org/) build on fast nginx cosockets.

Requires [lua-MessagePack](https://github.com/fperrad/lua-MessagePack).

Synopsis
------------

```lua

tarantool = require("tarantool")

-- initialize connection
local tar, err = tarantool:new()

local tar, err = tarantool:new({ connect_now = false })
local ok, err = tar:connect()

local tar, err = tarantool:new({
    host           = '127.0.0.1',
    port           = 3301,
    user           = 'gg_tester',
    password       = 'pass',
    socket_timeout = 2000,
    connect_now    = true,
})

-- requests (only call is supported)
local data, err = tar:call('package.func', [1])

-- disconnect or set_keepalive at the end
local ok, err = tar:disconnect()
local ok, err = tar:set_keepalive()

```
