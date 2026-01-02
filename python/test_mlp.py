import serial
import time

ser = serial.Serial('/dev/ttyUSB1', 115200, timeout=1)
time.sleep(0.1)

# Send 4 input bytes (values 0-255)
inputs = [100, 50, 200, 30]
for val in inputs:
    ser.write(bytes([val]))
    time.sleep(0.01)

# Send 'I' command for inference
ser.write(b'I')
time.sleep(0.1)

# Read 2 output bytes
output = ser.read(2)
if len(output) == 2:
    print(f"Output: [{output[0]}, {output[1]}]")
else:
    print("No response")

ser.close()