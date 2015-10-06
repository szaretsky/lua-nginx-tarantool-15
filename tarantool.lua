module("tarantool", package.seeall)

local ffi 	 = require("ffi")
local C      = require("const")
local string = string
local table  = table
local ngx    = ngx
local type   = type
local ipairs = ipairs
local error  = error


function new(self, params)
    local obj = {
        host           = C.HOST,
        port           = C.PORT,
        socket_timeout = C.SOCKET_TIMEOUT,
        connect_now    = C.CONNECT_NOW,
    }

    if params and type(params) == 'table' then
        for key, value in pairs(obj) do
            if params[key] ~= nil then
                obj[key] = params[key]
            end
        end
    end

    local sock, err = ngx.socket.tcp()
    if not sock then
        return nil, err
    end

    if obj.socket_timeout then
        sock:settimeout(obj.socket_timeout)
    end

    obj.sock     = sock
    obj._spaces  = {}
    obj._indexes = {}
    obj = setmetatable(obj, { __index = self })

    if obj.connect_now then
        local ok, err = obj:connect()
        if not ok then
            return nil, err
        end
    end

    return obj
end

function connect(self, host, port)
    if not self.sock then
        return nil, "no socket created"
    end
    local ok, err = self.sock:connect(host or self.host, tonumber(port or self.port))
    if not ok then
        return ok, err
	else
		return ok, nil
    end

--	not used in 1.5
--    return self:_handshake()
end

function disconnect(self)
    if not self.sock then
        return nil, "no socket created"
    end
    return self.sock:close()
end

local function _log( str )
	ngx.say("Log: ".. str .. "<br>")
end

function set_keepalive(self)
    if not self.sock then
        return nil, "no socket created"
    end
    local ok, err = self.sock:setkeepalive()
    if not ok then
        self:disconnect()
        return nil, err
    end
    return ok
end

local function _packuint32( integer )
	return ffi.string(ffi.new("uint32_t[1]", integer), 4)
end

local function _unpackuint32( str )
	return string.byte( str, 1, 1) + 0x100 * ( string.byte( str, 2, 2) + 0x100 * ( string.byte( str, 3,3) + 0x100 * string.byte( str, 4, 4)))
end

local function _packvaruint(integer)
	if integer == 0 then return '\000' end
	local ber = { string.char(integer % 128) }
	while integer > 127 do
		integer = math.floor(integer/128)
		local seven_bits = integer % 128
		table.insert(ber, 1, string.char(128+seven_bits))
	end
	return table.concat(ber)
end

local function _unpackvaruint(s, start)
	local i = start
	local len = 0
	local integer = 0
	while true do
		local byte = string.byte(s, i)
		integer = integer + (byte%128)
		if byte < 127.5 then
			return integer, len+1
		end
		if i >= #s then
			warn('str2ber_int: no end-of-integer found')
			return 0, start
		end
		i = i + 1
		len = len + 1
		integer = integer * 128
	end
end

local function _strdump( str )
	local dmp = ''
	for i = 1, #str do
		dmp = dmp .. "-".. string.byte(str,i,i)
	end
	return dmp
end

local function _parse_select_response( selectbody )
	local tuples_num = _unpackuint32( string.sub( selectbody, 1, 4))
	local ind = 5
	local result = {}
	for i=1, tuples_num do
		result[ i ] = {}
		local tuplelen = _unpackuint32( string.sub( selectbody, ind, ind+3))
		local tuplecrd = _unpackuint32( string.sub( selectbody, ind+4, ind+7))
		local tuple = string.sub( selectbody, ind+8, ind + tuplelen + 7)
		local tupleind = 1
		for j=1,tuplecrd do 
			result[i][ j ] = {}
			local elemlength, varlen = _unpackvaruint(  tuple, tupleind, tupleind + 3 )
			local elem = string.sub( tuple, tupleind + varlen, tupleind +varlen -1 +elemlength)
			result[i][j] = elem
			tupleind = tupleind + elemlength +varlen
		end
		ind = ind + tuplelen + 4
	end
	return result
end

function call(self, proc, args)
    local body = _packuint32(0) .. _packvaruint( string.len( proc )) .. proc .. _packuint32(1) .. _packvaruint( string.len(args)) .. args
	local response, err = self:_request( { [ C.TYPE ] = C.CALL }, body )
  	if err then
        return nil, err
   	elseif response and response.code ~= C.OK then
        return nil, (response and response.error or "Internal error")
    else
		return _parse_select_response( response.body )
    end
end



function _request(self, header, body)
    local sock = self.sock
    if type(header) ~= 'table' then
        return nil, 'invlid request header'
    end		

    self.sync_num = ((self.sync_num or 0) + 1) % C.REQUEST_PER_CONNECTION
    if not header[C.SYNC] then
        header[C.SYNC] = self.sync_num
    else
        self.sync_num = header[C.SYNC]
    end
    local request  = _prepare_request(header, body)
    local bytes, err = sock:send(request)
	if not bytes then
        sock:close()
        return nil, "Failed to send request: " .. err
    end

    local head, err = sock:receive(C.HEAD_BODY_LEN_SIZE)
    if not head then
        sock:close()
        return nil, "Failed to get response header: " .. err
    end
	
	--unpack header
	local cmd = _unpackuint32( string.sub( head, 1, 4) )
	local bodylength = _unpackuint32( string.sub( head, 5, 8) )
	local sync_resp = _unpackuint32( string.sub( head, 9, 12) )
	
	if sync_resp ~= self.sync_num then
        return nil, "Invalid header SYNC: request: " .. self.sync_num .. " response: " .. sync_resp
    end

	--read body
	local body, err = sock:receive( bodylength )
	if not body then
		sock:close()
		return nil, "Failed to get response body: " .. err
	end

	local return_code = _unpackuint32( string.sub( body, 1, 4 ))
	local response_body = ''
	if bodylength > 4 then
		response_body = string.sub( body, 5, -1)
	end

	return { code = return_code, cmd = cmd, body = response_body }
end

function _prepare_request(h, body)
	local bodylen = string.len(body)
	local header =  _packuint32( h[ C.TYPE ]).. _packuint32(bodylen) .. _packuint32( h[ C.SYNC ])
    return header .. body
end

