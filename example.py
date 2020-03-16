"""
Example code for pyv4l2 camera.
"""
import numpy as np
from pyv4l2.camera import Camera


videocap = Camera('/dev/video0')


for i in range(500):
    # get_frame() method returns frame as a numpy array and timestamp
    frame, _ = videocap.get_frame()
    print(np.mean(frame))

videocap.close()