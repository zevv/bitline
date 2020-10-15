
import strutils
import times except Time
from posix import nil

import misc


type

  Reader* = ref object
    fd: cint
    rxBuf: string
    rxPtr: int
    cb: ReaderCallback
    prefix: string

  ReaderCallback = proc(t: Time, key, ev, evdata: string)


const
  readBufSize = 256 * 1024


proc parseEvent(reader: Reader, l: string) =

  let r = l.splitWhiteSpace(3)

  if r.len == 2 and r[0] == "prefix":
    reader.prefix = r[1] & "."

  if r.len >= 3:
    let (ts, ev, key) = (r[0], r[1], r[2])
    let evdata = if r.len == 4: r[3] else: ""
    var t = NoTime

    try:
      t = ts.parseFloat()
    except:
      try:
        t = ts.parse(iso8601format).toTime.toUnixFloat
      except:
        return

    reader.cb(t, reader.prefix & key, ev, evdata)


proc read*(reader: Reader): bool =
  var count = 0

  let n = posix.read(reader.fd, reader.rxBuf[reader.rxPtr].addr, readBufSize - reader.rxPtr)
  if n <= 0:
    return false

  reader.rxPtr += n
  var o1 = 0
  var o2 = 0

  while true:
    o2 = reader.rxBuf.find("\n", o1, reader.rxPtr-1)
    if o2 > -1:
      let l = reader.rxBuf[o1..<o2]
      reader.parseEvent(l)
      inc count
      o1 = o2 + 1
    else:
      let nLeft = reader.rxPtr - o1
      if nLeft > 0:
        moveMem(reader.rxBuf[0].addr, reader.rxBuf[o1].addr, nLeft)
      reader.rxPtr = nLeft
      break

  return count > 0


proc newReader*(fname: string, cb: ReaderCallback): Reader =
  let fd = posix.open(fname.c_string, posix.O_RDONLY or posix.O_NONBLOCK)
  if fd == -1:
    return nil

  Reader(
    rxBuf: newString(readBufSize),
    fd: fd,
    cb: cb
  )


# vi: ft=nim sw=2 ts=2 

