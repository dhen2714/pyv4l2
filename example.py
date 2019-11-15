import cv2
import numpy as np
from pyv4l2.camera import Camera

videocap = Camera('/dev/video0')

for i in range(500):
    frame = videocap.get_frame()
    cv2.imshow('frame', frame)
    cv2.waitKey(1)

cv2.destroyAllWindows()
print('Reading reg')
test = videocap.read_ISPreg(0x80181033)
print(test)
print('Attemping write:')
videocap.write_ISPreg(0x80181033, 0)
videocap.write_ISPreg(0x80181833, 0);
print('Written')
print('Reading')
test = videocap.read_ISPreg(0x80181033)
print(test)

for i in range(500):
    frame = videocap.get_frame()
    cv2.imshow('frame', frame)
    cv2.waitKey(1)

videocap.close()
