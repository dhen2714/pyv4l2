import cv2
import numpy as np
from pyv4l2.camera import Camera
from capgui.gui import CapApp
# import thread

ca = CapApp('capgui')
# ca.root.mainloop()

# videocap = Camera('/dev/video0')
# gain = videocap.get_gain()
# print(gain)
# videocap.set_gain(0)
# gain = videocap.get_gain()
# print(gain)


for i in range(500):
    frame, _ = ca.vc.get_frame()

    cv2.imshow('frame', frame)
    cv2.waitKey(1)

# cv2.destroyAllWindows()
# print('Reading reg')
# test = videocap.read_ISPreg(0x80181033)
# print(test)
# print('Attemping write:')
# videocap.write_ISPreg(0x80181033, 0)
# videocap.write_ISPreg(0x80181833, 0);
# print('Written')
# print('Reading')
# test = videocap.read_ISPreg(0x80181033)
# print(test)

# for i in range(500):
#     frame, _ = videocap.get_frame()
#     if i > 250:
#         videocap.set_exposure(32)
#     cv2.imshow('frame', frame)
#     cv2.waitKey(1)

# videocap.close()
