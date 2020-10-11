import math
import random
import algorithm

proc pow2(t1, t2: float, depth: int) =

  let dt = (t2 - t1) / pow(2.0, depth.float)

  var t = t1
  while t < t2:
    echo t,    " pow2.", depth, " +"
    echo t+dt, " pow2.", depth, " -"
    t += dt*2

  if depth < 21:
    pow2(t1, t2, depth+1)


proc noise(t1, t2: float, depth: int) =

  let n = pow(2.0, depth.float).int

  var ts: seq[float]

  for i in 0..n:
    ts.add t1 + rand(t2-t1)

  sort ts

  for t in ts:
    echo t, " rand.", depth, " !"

  if depth < 16:
    noise(t1, t2, depth+1)


proc graphs(t1, t2: float, depth: int) =
  
  let dt = (t2 - t1) / pow(2.0, depth.float)
  var t = t1
  var v = 0.0
  while t < t2:
    echo t, " graph.", depth, " ! ", sin(v)
    v += 0.1
    t += dt

  if depth < 16:
    graphs(t1, t2, depth+1)



noise(100, 200, 1)
graphs(100, 200, 1)
pow2(100, 200, 1)
