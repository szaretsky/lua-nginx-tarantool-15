module("const", package.seeall)

-- common
HEAD_BODY_LEN_SIZE     = 12
REQUEST_PER_CONNECTION = 100000
MAX_LIMIT              = 0xFFFFFFFF

-- default options
HOST           = '127.0.0.1'
PORT           = 3301
SOCKET_TIMEOUT = 5000
CONNECT_NOW    = true

-- packet codes
OK         = 0
SELECT     = 17
INSERT     = 13
UPDATE     = 19
DELETE     = 21
CALL       = 22
PING	   = 65280
ERROR_TYPE = 65536

-- packet keys
TYPE          = 0x00
LENGTH		  = 0x01
SYNC          = 0x02
