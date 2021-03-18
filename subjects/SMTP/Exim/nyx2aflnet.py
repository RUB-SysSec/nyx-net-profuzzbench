
import struct
import os
import sys

output_buffer = b""

def packet_raw(inputs=None, borrows=None, data=""):
  global output_buffer
  #print(data)
  #print(len(data))
  output_buffer += struct.pack("i", len(data))
  output_buffer += data

def packet(data=""):
  global output_buffer
  #print(data)
  #print(len(data))
  output_buffer += struct.pack("i", len(data))
  output_buffer += data

file_name = sys.argv[1]
out_file_name = sys.argv[2]

print(file_name)
execfile(file_name)

#print(os.path.basename(file_name))
f = open(out_file_name, "w")
f.write(output_buffer)
f.close()

