import npeg

#[

sudo perf record -a -e 'syscalls:*' --exclude-perf -e 'timer:*' --exclude-perf
sudo perf script --fields 'comm,tid,pid,time,event,trace' 

]#


let p = peg line:
  s <- +' '
  line <- s * >name * s * >pid * '/' * >tid * s * >time * ':' * s * "syscalls:sys_" * >enterexit * "_" * >syscall:
    var prefix = ""
    if $5 == "enter":
      prefix = "+"
    if $5 == "exit":
      prefix = "-"
    let comm = $1
    let tid = $2
    let pid = $3
    let time = $4
    let syscall = $6

    echo time, " ", pid, ".", comm, "(", tid, ").", syscall, " ", prefix

    #echo $4 & " " & $2 & "." & $1 & "." & $3 & " " & $prefix & $6
  name <- +Graph
  pid <- +Digit
  tid <- +Digit
  time <- +Digit * "." * +Digit
  enterexit <- "enter" | "exit"
  syscall <- +Alnum

for l in lines(stdin):
  discard p.match(l)

