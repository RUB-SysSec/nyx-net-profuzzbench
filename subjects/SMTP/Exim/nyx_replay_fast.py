import sys
import socket
import select
import time

def print_usage():
  print("USAGE <file> <tcp/udp/stdout> <port>")

def packet(data=""):
  global mode
  if mode == "stdout":
    sys.stdout.write(data)
  else:
    ready = select.select([s], [], [], 0)
    if ready[0]:
      try:
        s.recv(4096)
      except:
        print("    cannot recv")
    if len(data) != 1:
    	time.sleep(0.1)
    s.send(data)
  #print("SEND %d bytes"%(len(data)))
  #print(data)

if len(sys.argv) >= 3:

  payload_file = sys.argv[1]
  mode = sys.argv[2]

  if mode == "stdout":
    execfile(sys.argv[1])
  elif (mode == "tcp" or mode == "udp") and len(sys.argv) == 4:
    host = "localhost"
    port = int(sys.argv[3])
    if mode == "tcp":
      s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    elif mode == "udp":
      s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setblocking(0)
    s.settimeout(1)

    connected = False
    for _ in range(100):
      try:
        s.connect((host, port))
        connected = True
        break
      except:
        time.sleep(0.3)
    if not connected:
      print("Could not connect")
      sys.exit(1)
    execfile(sys.argv[1])
  else:
    print_usage()

else:
  print_usage()

