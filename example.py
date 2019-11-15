import cv2
import numpy as np
from pyv4l2.camera import Camera

videocap = Camera('/dev/video0')

for i in range(500):
    frame = videocap.get_frame()
    cv2.imshow('frame', frame)
    cv2.waitKey(1)

cv2.destroyAllWindows()

videocap.close()
