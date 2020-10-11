
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

  TimeFloat* = float64

  Span*[T] = object
    v1*, v2*: T

  TimeSpan* = Span[TimeFloat]

  ValueSpan* = Span[Value]

  Group* = ref object
    id*: string
    ts*: TimeSpan
    vs*: ValueSpan
    groups*: OrderedTable[string, Group]
    events*: seq[Event]

  Event* = object
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
    var sign = " "
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

echo siFmt(1)

proc initSpan*[T](v1, v2: T): Span[T] =
  Span[T](v1: v1, v2: v2)

proc incl*[T](s: var Span[T], v: T) =
  s.v1 = min(s.v1, v)
  s.v2 = max(s.v2, v)

proc incl*[T](s: var Span[T], v: Span[T]) =
  s.v1 = min(s.v1, v.v1)
  s.v2 = max(s.v2, v.v2)

proc duration*(ts: TimeSpan): float =
  ts.v2 - ts.v1


proc contains*[T](s: Span[T], v: T): bool =
  v >= s.v1 and v <= s.v2


proc fmtDuration*(d: TimeFloat): string =
  let d = abs(d)
  result.add if d < 60:
    siFmt(d, "s")
  elif d < 3600:
    &"{int(d/60.0)}m {d mod 60.0:.01f}s"
  else:
    &"{int(d/3600.0)}h {int(d/60.0) mod 60}m {d mod 60.0:.01f}s"


proc fmtFrequency*(f: float): string =
  siFmt(f, "Hz")

