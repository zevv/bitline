
import strutils
import tables
import parseutils
import times except Time
from posix import nil

import misc


type

  Reader* = ref object
    fd: cint
    rxBuf: string
    rxPtr: int
    root: Group
    prefix: string
    gidCache: Table[string, Group]

  ReaderCallback = proc(t: Time, key, ev, evdata: string)


const
  readBufSize = 256 * 1024
    

proc keyToGroup(reader: Reader, root: Group, key: string): Group =
  var g: Group
  if key in reader.gidCache:
    g = reader.gidCache[key]
  else:
    g = root
    for id in key.split("."):
      if id notin g.groups:
        g.groups[id] = g.newGroup(id)
        g = g.groups[id]
      else:
        g = g.groups[id]
      reader.gidCache[key] = g
  return g


proc addEvent(reader: Reader, t: Time, key: string, ev: char, evdata: string) =

  let g = reader.keyToGroup(reader.root, key)
  g.ts.incl t

  var value = NoValue
  try:
    let vs = evdata.splitWhitespace()
    if vs.len > 0:
      value = vs[0].parseFloat()
  except:
    discard

  case ev:
    of '+':
      g.events.add misc.Event(kind: ekSpan, data: evdata, time: t, value: value)
    of '-':
      if g.events.len > 0:
        g.events[^1].duration = t - g.events[^1].time
    of '!':
      g.events.add misc.Event(kind: ekOneshot, data: evdata, time: t, value: value)
    of 'c':
      if g.prevTotal == NoValue:
        g.prevTotal = value
      else:
        let total = g.prevTotal + value
        let dt = t - g.prevTime
        if dt > 0.0:
          value /= dt
          g.events.add misc.Event(kind: ekCounter, data: evdata, time: t, value: value)
          g.vs.incl value
        g.prevTotal = total
      g.prevTime = t
    of 'g', 'v':
      g.events.add misc.Event(kind: ekGauge, data: evdata, time: t, value: value)
      g.vs.incl value
    else:
      discard


proc parseEvent(reader: Reader, l: string, off: int): int =

  var t: float
  var key: string
  var ev: char
  var evdata: string
  var n: int

  # TODO t = tmp.parse(iso8601format).toTime.toUnixFloat

  template req(code: untyped) =
    let r = code
    if r == 0: return 0
    n += r
  
  template opt(code: untyped) =
    n += code

  req l.parseFloat(t, off+n)
  req l.skipWhile({' '}, off+n)
  req l.parseChar(ev, off+n)
  req l.skipWhile({' '}, off+n)
  req l.parseUntil(key, {' ','\r','\n'}, off+n)
  opt l.skipWhile({' '}, off+n)
  opt l.parseUntil(evdata, {'\r','\n'}, off+n)
  req l.skipWhile({'\r','\n'}, off+n)

  reader.addEvent(t, reader.prefix & key, ev, evdata)
  return n


proc read*(reader: Reader): bool =
  var count = 0

  var n = posix.read(reader.fd, reader.rxBuf[reader.rxPtr].addr, readBufSize - reader.rxPtr - 1)
  if n <= 0:
    return false
  reader.rxBuf[reader.rxPtr+n] = '\0'
  n += reader.rxPtr

  var off = 0

  while true:
    let r = reader.parseEvent(reader.rxBuf, off)
    if r > 0:
      off += r
    else:
      break

  let nLeft = n - off
  if nLeft > 0:
     moveMem(reader.rxBuf[0].addr, reader.rxBuf[off].addr, nLeft)
  reader.rxPtr = nLeft

  return true



proc newReader*(fname: string, root: Group): Reader =
  let fd = posix.open(fname.c_string, posix.O_RDONLY or posix.O_NONBLOCK)
  if fd == -1:
    echo "Error opening $1: $2" % [fname, $posix.strerror(posix.errno)]
    quit 1

  Reader(
    rxBuf: newString(readBufSize),
    fd: fd,
    root: root,
  )


# vi: ft=nim sw=2 ts=2 

