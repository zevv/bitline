import npeg
import strutils
import times
import tables
import json

var sidCid: Table[string, string]

for l in lines(stdin):

  try:
    let j1 = l.parseJson()
    var m = j1["message"].getStr()
    
    var ts = j1["@timestamp"].getStr().parse("yyyy-MM-dd'T'HH:mm:ss'.'ffffff'Z'").toTime.toUnixFloat()


    if m[0..8] == "[EVENT] {":
      m = m[8..^1]

    m = m.replace("\\\"", "\"")
    let j = m.parseJson()
  
    if "timestamp" in j:
      ts = j["timestamp"].getStr().parse("yyyy-MM-dd HH:mm:ss'.'fff").toTime.toUnixFloat()

    let et = j["eventtype"].getStr()
    let oid = j["operatorid"].getStr()
    let sid = j["sessionid"].getStr()

    var cid = "?"
    if "clientid" in j: cid = j["clientid"].getStr()
    if "clientID" in j: cid = j["clientID"].getStr()

    if cid != "?" and cid notin sidCid:
      sidCid[sid] = cid

    if cid == "?" and sid in sidCid:
      cid = sidCid[sid]

    let tsf = ts.fromUnixFloat().format("yyyy-MM-dd'T'HH:mm:ss'.'ffffff'Z'")

    let p = tsf & " " & oid & "." & cid & "." & sid & "."

    if et == "session-launch-complete":
      echo p & "session +"
    elif et == "session-stop":
      echo p & "session -"
    elif et == "av-segment-downloaded":
      let d = j["serverdownloadduration"].getFloat()
      let ts2 = ts - d
      let tsf2 = ts2.fromUnixFloat().format("yyyy-MM-dd'T'HH:mm:ss'.'ffffff'Z'")
      echo tsf2, " ", oid, ".", cid, ".", sid, ".av-segment-downloaded +"
      echo tsf,  " ", oid, ".", cid, ".", sid, ".av-segment-downloaded -"
    else:
      echo p & et & " " & "!"

    #echo j.repr

  except:
    echo getCurrentExceptionMsg(), " ", l
    discard

