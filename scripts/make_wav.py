"""Write a short stereo 16-bit WAV (a 220 Hz tone with a gentle pulse) for picker checks."""
import math, struct, sys, wave

path = sys.argv[1]
rate, seconds = 44100, 6
with wave.open(path, 'wb') as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(rate)
    frames = bytearray()
    for i in range(rate * seconds):
        t = i / rate
        pulse = 0.6 + 0.4 * math.exp(-(t % 0.5) * 8)
        value = int(9000 * pulse * math.sin(2 * math.pi * 220 * t))
        frames += struct.pack('<hh', value, value)
    out.writeframes(bytes(frames))
print('wrote', path)
