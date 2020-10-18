
import strformat
import strutils
import tables
import hashes
import math
import gui
import sets
import textcache

import sdl2/sdl except Event

type

  Value* = float64

  Time* = float64

  Span*[T] = object
    lo*, hi*: T

  TimeSpan* = Span[Time]

  ValueSpan* = Span[Value]

  Bin* = range[1..9]

  Group* = ref object
    parent*: Group
    id*: string
    ts*: TimeSpan
    vs*: ValueSpan
    groups*: OrderedTable[string, Group]
    events*: seq[Event]
    bin*: Bin
    prevTotal*: Value
    prevTime*: Time

  EventKind* = enum
    ekOneshot,
    ekSpan,
    ekCounter,
    ekGauge,

  Event* = object
    kind*: EventKind
    ts*: TimeSpan
    data*: string
    value*: Value

  AppStats* = object
    eventCount*: int
    groupCount*: int

const
  iso8601format* = "yyyy-MM-dd'T'HH:mm:ss'.'ffffff'Z'"
  NoTime* = float64.low
  NoValue* = float64.low


proc hash*(g: Group): Hash =
  result = hash cast[pointer](g)

proc siFmt*(v: SomeNumber, unit="", align=false): string =
  
  let f = abs(v.float)

  proc format(s: float, suffix: string): string =
    var fs = &"{f*s:.4g}"
    fs.trimZeros()
    if align:
      fs = fs.align(5)
    var sign = ""
    if v < 0: sign = "-"
    &"{sign}{fs}{suffix}{unit}"

  if f == 0.0:
    format(0, "")
  elif f < 999e-9:
    format(1e9, "n")
  elif f < 999e-6:
    format(1e6, "µ")
  elif f < 999e-3:
    format(1e3, "m")
  elif f < 999:
    format(1.0, if align: " " else: "")
  elif f < 999e3:
    format(1e-3, "K")
  elif f < 999e6:
    format(1e-6, "M")
  else:
    format(1e-9, "G")

proc initSpan*[T](lo:T=T.high, hi:T=T.low): Span[T] =
  Span[T](lo: lo, hi: hi)

proc incl*[T](s: var Span[T], v: T) =
  s.lo = min(s.lo, v)
  s.hi = max(s.hi, v)

proc incl*[T](s: var Span[T], v: Span[T]) =
  s.lo = min(s.lo, v.lo)
  if v.hi != T.low:
    s.hi = max(s.hi, v.hi)
  else:
    s.hi = max(s.hi, v.lo)

proc duration*(ts: TimeSpan): float =
  ts.hi - ts.lo


proc contains*[T](s: Span[T], v: T): bool =
  v >= s.lo and v <= s.hi

proc overlaps*[T](s1: Span[T], s2: Span[T]): bool =
  s1.lo <= s2.hi and s1.hi >= s2.lo 

proc fmtDuration*(d: Time): string =
  let d = abs(d)
  result.add if d < 60:
    siFmt(d, "s")
  elif d < 3600:
    &"{int(d/60.0)}m {d mod 60.0:.01f}s"
  else:
    &"{int(d/3600.0)}h {int(d/60.0) mod 60}m {d mod 60.0:.01f}s"

proc fmtFrequency*(f: float): string =
  siFmt(f, "Hz")

proc newGroup*(parent: Group=nil, id="", bin=1): Group =
  Group(
    parent: parent,
    id: id,
    bin: bin,
    ts: initSpan[Time](),
    vs: initSpan[Value](),
    prevTime: NoTime,
    prevTotal: NoValue,
  )
