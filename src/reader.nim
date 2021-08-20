
import strutils
import tables
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



proc addEvent(reader: Reader, t: Time, key, ev, evdata: string) =

  let g = reader.keyToGroup(reader.root, key)
  g.ts.incl t

  var value = NoValue
  try:
    let vs = evdata.splitWhitespace()
    if vs.len > 0:
      value = vs[0].parseFloat()
  except:
    discard

  case ev[0]
    of '+':
      g.events.add misc.Event(kind: ekSpan, data: evdata, time: t)
    of '-':
      if g.events.len > 0:
        g.events[^1].duration = t - g.events[^1].time
    of '!':
      g.events.add misc.Event(kind: ekOneshot, data: evdata, time: t)
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

    reader.addEvent(t, reader.prefix & key, ev, evdata)


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

