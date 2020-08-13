from pyv4l2.v4l2 cimport *
from libc.errno cimport errno, EINTR, EINVAL
from libc.string cimport memset, memcpy, strerror
from libc.stdlib cimport malloc, calloc, free
from posix.select cimport fd_set, timeval, FD_ZERO, FD_SET, select
from posix.fcntl cimport O_RDWR
from posix.mman cimport PROT_READ, PROT_WRITE, MAP_SHARED
from posix.unistd cimport sleep

from pyv4l2.controls import CameraControl
from pyv4l2.exceptions import CameraError

import numpy as np
cimport numpy as np

cdef enum: UVC_SET_CUR = 0x01
cdef enum: UVC_GET_CUR = 0x81

cdef __u8 query_value[384]
cdef __u8 i2c_flag = 1

cdef uvc_xu_control_query xu_query = [4, 2, UVC_SET_CUR, 384, query_value]

cdef void SAFE_IOCTL(int x):
    if x < 0:
        raise CameraError('ioctl error: {}    {}'.format(
            errno, strerror(errno).decode())
        )

cdef class Camera:
    cdef int fd
    cdef fd_set fds

    cdef v4l2_format fmt
    cdef v4l2_format frame_fmt

    cdef public unsigned int width
    cdef public unsigned int height

    cdef unsigned int frame_size
    cdef unsigned char *frame_data
    cdef unsigned int fps

    cdef v4l2_requestbuffers buf_req
    cdef v4l2_buffer buf
    cdef buffer_info *buffers

    # For fps
    cdef v4l2_streamparm parm

    cdef timeval tv
    cdef unsigned long timestamp

    def __cinit__(self, device_path, const int fps=100,
                  unsigned int width=1280, unsigned int height=480):
        device_path = device_path.encode()

        self.fd = v4l2_open(device_path, O_RDWR)
        if -1 == self.fd:
            raise CameraError('Error opening device {}'.format(device_path))

        memset(&self.fmt, 0, sizeof(self.fmt))
        self.fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

        if -1 == xioctl(self.fd, VIDIOC_G_FMT, &self.fmt):
            raise CameraError('Getting format failed')

        self.fmt.fmt.pix.width = width
        self.fmt.fmt.pix.height = height
        self.fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_GREY
        self.fmt.fmt.pix.field = V4L2_FIELD_ANY

        if -1 == xioctl(self.fd, VIDIOC_S_FMT, &self.fmt):
            raise CameraError('Setting format failed')

        self.fps = fps
        self.parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.parm.parm.capture.timeperframe.numerator = 1
        self.parm.parm.capture.timeperframe.denominator = self.fps

        if -1 == xioctl(self.fd, VIDIOC_S_PARM, &self.parm):
            raise CameraError('Setting fps failed')

        self.width = width
        self.height = height

        self.frame_size = width * height
        self.frame_data = <unsigned char *>malloc(self.frame_size)

        memset(&self.buf_req, 0, sizeof(self.buf_req))
        self.buf_req.count = 1
        self.buf_req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.buf_req.memory = V4L2_MEMORY_MMAP

        if -1 == xioctl(self.fd, VIDIOC_REQBUFS, &self.buf_req):
            raise CameraError('Requesting buffer failed')

        self.buffers = <buffer_info *>calloc(self.buf_req.count,
                                             sizeof(self.buffers[0]))
        if self.buffers == NULL:
            raise CameraError('Allocating memory for buffers array failed')
        self.initialize_buffers()

        if -1 == xioctl(self.fd, VIDIOC_STREAMON, &self.buf.type):
            raise CameraError('Starting capture failed')

        print('Initializing...')
        # Registers need to be read before they can be changed.
        self.read_ISPreg(0x80181033)
        self.read_ISPreg(0x80181833)
        self.write_ISPreg(0x80181033, 0)
        self.write_ISPreg(0x80181833, 0)
        self.get_gain()
        self.set_gain(0x00)

    cdef inline int initialize_buffers(self) except -1:
        for buf_index in range(self.buf_req.count):
            memset(&self.buf, 0, sizeof(self.buf))
            self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
            self.buf.memory = V4L2_MEMORY_MMAP
            self.buf.index = buf_index

            if -1 == xioctl(self.fd, VIDIOC_QUERYBUF, &self.buf):
                raise CameraError('Querying buffer failed')

            bufptr = v4l2_mmap(NULL, self.buf.length,
                               PROT_READ | PROT_WRITE,
                               MAP_SHARED, self.fd, self.buf.m.offset)

            if bufptr == <void *>-1:
                raise CameraError('MMAP failed: {}'.format(
                    strerror(errno).decode())
                )

            self.buffers[buf_index] = buffer_info(bufptr, self.buf.length)

            memset(&self.buf, 0, sizeof(self.buf))
            self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
            self.buf.memory = V4L2_MEMORY_MMAP
            self.buf.index = buf_index

            if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
                raise CameraError('Exchanging buffer with device failed')

        return 0

    cdef list enumerate_menu(self, v4l2_queryctrl *queryctrl,
                             v4l2_querymenu *querymenu):
        menu = []

        if queryctrl.type == V4L2_CTRL_TYPE_MENU:
            memset(querymenu, 0, sizeof(querymenu[0]))
            querymenu.id = queryctrl.id

            for querymenu.index in range(queryctrl.minimum,
                                         queryctrl.maximum + 1):
                if 0 == xioctl(self.fd, VIDIOC_QUERYMENU, querymenu):
                    menu.append(querymenu.name.decode('utf-8'))
                else:
                    raise CameraError('Querying controls failed')

        return menu

    cpdef list get_controls(self):
        controls_list = []

        cdef v4l2_queryctrl queryctrl
        cdef v4l2_querymenu querymenu

        memset(&queryctrl, 0, sizeof(queryctrl))

        for queryctrl.id in range(V4L2_CID_BASE, V4L2_CID_LASTP1):
            if 0 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
                if queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
                    continue

                controls_list.append(
                    CameraControl(queryctrl.id, queryctrl.type,
                                  queryctrl.name.decode('utf-8'),
                                  queryctrl.default_value, queryctrl.minimum,
                                  queryctrl.maximum, queryctrl.step,
                                  self.enumerate_menu(&queryctrl, &querymenu),
                                  queryctrl.flags)
                )
            elif errno == EINVAL:
                continue
            else:
                raise CameraError('Querying controls failed')

        queryctrl.id = V4L2_CID_PRIVATE_BASE
        while True:
            if 0 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
                if queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
                    continue

                controls_list.append(
                    CameraControl(queryctrl.id, queryctrl.type,
                                  queryctrl.name.decode('utf-8'),
                                  queryctrl.default_value, queryctrl.minimum,
                                  queryctrl.maximum, queryctrl.step,
                                  self.enumerate_menu(&queryctrl, &querymenu),
                                  queryctrl.flags)
                )
            elif errno == EINVAL:
                break
            else:
                raise CameraError('Querying controls failed')

        return controls_list

    cpdef void set_control_value(self, control_id, value):
        cdef v4l2_queryctrl queryctrl
        cdef v4l2_control control

        memset(&queryctrl, 0, sizeof(queryctrl))
        queryctrl.id = control_id.value

        if -1 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
            if errno != EINVAL:
                raise CameraError('Querying control')
            else:
                raise AttributeError('Control is not supported')
        elif queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
            raise AttributeError('Control is not supported')
        else:
            memset(&control, 0, sizeof(control))
            control.id = control_id.value
            control.value = value

            if -1 == xioctl(self.fd, VIDIOC_S_CTRL, &control):
                raise CameraError('Setting control')

    cpdef int get_control_value(self, control_id):
        cdef v4l2_queryctrl queryctrl
        cdef v4l2_control control

        memset(&queryctrl, 0, sizeof(queryctrl))
        queryctrl.id = control_id.value

        if -1 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
            if errno != EINVAL:
                raise CameraError('Querying control')
            else:
                raise AttributeError('Control is not supported')
        elif queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
            raise AttributeError('Control is not supported')
        else:
            memset(&control, 0, sizeof(control))
            control.id = control_id.value

            if 0 == xioctl(self.fd, VIDIOC_G_CTRL, &control):
                return control.value
            else:
                raise CameraError('Getting control')

    cdef np.ndarray[np.uint8_t, ndim=2] _get_frame(self):
        FD_ZERO(&self.fds)
        FD_SET(self.fd, &self.fds)
        cdef np.ndarray frame
        cdef int r

        self.tv.tv_sec = 2

        r = select(self.fd + 1, &self.fds, NULL, NULL, &self.tv)
        while -1 == r and errno == EINTR:
            FD_ZERO(&self.fds)
            FD_SET(self.fd, &self.fds)

            self.tv.tv_sec = 2

            r = select(self.fd + 1, &self.fds, NULL, NULL, &self.tv)

        if -1 == r:
            raise CameraError('Waiting for frame failed')

        memset(&self.buf, 0, sizeof(self.buf))
        self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.buf.memory = V4L2_MEMORY_MMAP

        if -1 == xioctl(self.fd, VIDIOC_DQBUF, &self.buf):
            raise CameraError('Retrieving frame failed')

        self.frame_data = <unsigned char *>self.buffers[self.buf.index].start
        self.timestamp = self.buf.timestamp.tv_sec * 1000000 + self.buf.timestamp.tv_usec
        
        if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
            raise CameraError('Exchanging buffer with device failed')

        frame = np.frombuffer(self.frame_data[:self.frame_size], dtype=np.uint8)
        return frame.reshape((self.height, self.width))

    def get_frame(self):
        frame = np.zeros((self.height, self.width), dtype=np.uint8)
        frame = self._get_frame()
        timestamp = self.timestamp
        return frame, timestamp
    
    cpdef __u8 read_ISPreg(self, __u32 isp_add):
        xu_query.query = UVC_SET_CUR # UVC_SET_CUR

        query_value[0] = 0x51
        query_value[1] = 0xa2
        query_value[2] = 0x6c
        query_value[3] = 0x04
        query_value[4] = 0x01
        query_value[5] = isp_add>>24
        query_value[6] = isp_add>>16
        query_value[7] = isp_add>>8
        query_value[8] = isp_add&0xff
        query_value[9] = 0x90
        query_value[10] = 0x01
        query_value[11] = 0x00
        query_value[12] = 0x01

        ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query)
        sleep(1)

        xu_query.query = UVC_GET_CUR # UVC_GET_CUR
        SAFE_IOCTL(ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query))

        return query_value[17]

    cpdef void write_ISPreg(self, __u32 isp_add, __u8 isp_val):
        xu_query.query = UVC_SET_CUR # UVC_SET_CUR

        query_value[0] = 0x50
        query_value[1] = 0xa2
        query_value[2] = 0x6c
        query_value[3] = 0x04
        query_value[4] = 0x01
        #register address
        query_value[5] = isp_add>>24
        query_value[6] = isp_add>>16
        query_value[7] = isp_add>>8
        query_value[8] = isp_add&0xff

        query_value[9] = 0x90
        query_value[10] = 0x01
        query_value[11] = 0x00
        query_value[12] = 0x01

        query_value[16] = isp_val

        SAFE_IOCTL(ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query))

    cdef __u8 read_sensor_reg(self, __u16 sensor_add, __u8 i2c):
        xu_query.query = UVC_SET_CUR

        query_value[0] = 0x51

        if(i2c):
            query_value[1] = 0xa3
        else:
            query_value[1] = 0xa5

        query_value[2] = 0xc0
        query_value[3] = 0x02
        query_value[4] = 0x01
        query_value[5] = 0x00
        query_value[6] = 0x00
        query_value[7] = sensor_add>>8
        query_value[8] = sensor_add&0xff
        query_value[9] = 0x90
        query_value[10] = 0x01
        query_value[11] = 0x00
        query_value[12] = 0x01

        SAFE_IOCTL(ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query))
        sleep(1)

        xu_query.query = UVC_GET_CUR
        SAFE_IOCTL(ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query))
        return query_value[17]

    cdef void write_sensor_reg(self, __u16 sensor_add, __u8 sensor_val, __u8 i2c):
        xu_query.query = UVC_SET_CUR

        query_value[0] = 0x50

        if(i2c):
            query_value[1] = 0xa3
        else:
            query_value[1] = 0xa5

        query_value[2] = 0xc0
        query_value[3] = 0x02
        query_value[4] = 0x01

        # register address
        query_value[5] = 0x00
        query_value[6] = 0x00
        query_value[7] = sensor_add>>8
        query_value[8] = sensor_add&0xff

        query_value[9] = 0x90
        query_value[10] = 0x01
        query_value[11] = 0x00
        query_value[12] = 0x01

        query_value[16] = sensor_val

        SAFE_IOCTL(ioctl(self.fd, UVCIOC_CTRL_QUERY, &xu_query))

    cpdef void set_aec(self, __u8 val):
        self.read_ISPreg(0x80181033)
        self.read_ISPreg(0x80181833)
        self.write_ISPreg(0x80181033, val)
        self.write_ISPreg(0x80181833, val)

    cpdef __u8 get_aec(self, flag=0):
        if flag:
            return self.read_ISPreg(0x80181033)
        else:
            return self.read_ISPreg(0x80181833)

    cpdef __u8 get_exposure(self):
        return self.read_sensor_reg(0x3501, 0)

    cpdef void set_exposure(self, __u8 exposure):
        # Max value is 31
        self.write_sensor_reg(0x3501, exposure, 0x00)
        self.write_sensor_reg(0x3501, exposure, 0x01)

    cpdef void set_gain(self, __u8 gain):
        # Default is 248 or 0xf8
        self.write_sensor_reg(0x350B, gain, 0x00)
        self.write_sensor_reg(0x350B, gain, 0x01)

    cpdef __u8 get_gain(self):
        self.read_sensor_reg(0x350B, 0x01)
        self.read_sensor_reg(0x350B, 0x00)
        return self.read_sensor_reg(0x350B, 0x00)

    def close(self):
        xioctl(self.fd, VIDIOC_STREAMOFF, &self.buf.type)

        for i in range(self.buf_req.count):
            v4l2_munmap(self.buffers[i].start, self.buffers[i].length)

        v4l2_close(self.fd)


cdef class OV580_OV7251(Camera):
    pass


cdef class MIPI_OV7251:
    cdef int fd
    cdef fd_set fds

    cdef v4l2_format fmt
    cdef v4l2_format frame_fmt

    cdef public unsigned int width
    cdef public unsigned int height

    cdef unsigned int frame_size
    cdef unsigned char *frame_data

    cdef v4l2_requestbuffers buf_req
    cdef v4l2_buffer buf
    cdef buffer_info *buffers

    cdef timeval tv
    cdef unsigned long timestamp

    def __cinit__(self, device_path):
        device_path = device_path.encode()

        self.fd = v4l2_open(device_path, O_RDWR)
        if -1 == self.fd:
            raise CameraError('Error opening device {}'.format(device_path))

        memset(&self.fmt, 0, sizeof(self.fmt))
        self.fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

        if -1 == xioctl(self.fd, VIDIOC_G_FMT, &self.fmt):
            raise CameraError('Getting format failed')

        self.fmt.fmt.pix.width = 640
        self.fmt.fmt.pix.height = 480
        self.fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV
        self.fmt.fmt.pix.field = V4L2_FIELD_ANY

        if -1 == xioctl(self.fd, VIDIOC_S_FMT, &self.fmt):
            raise CameraError('Setting format failed')

        self.width = 640
        self.height = 480

        self.frame_size = self.width * self.height
        self.frame_data = <unsigned char *>malloc(self.frame_size)

        memset(&self.buf_req, 0, sizeof(self.buf_req))
        self.buf_req.count = 4
        self.buf_req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.buf_req.memory = V4L2_MEMORY_MMAP

        if -1 == xioctl(self.fd, VIDIOC_REQBUFS, &self.buf_req):
            raise CameraError('Requesting buffer failed')

        self.buffers = <buffer_info *>calloc(self.buf_req.count,
                                             sizeof(self.buffers[0]))
        if self.buffers == NULL:
            raise CameraError('Allocating memory for buffers array failed')
        self.initialize_buffers()

        if -1 == xioctl(self.fd, VIDIOC_STREAMON, &self.buf.type):
            raise CameraError('Starting capture failed')

        # self.set_fps(100)
        # self.set_exposure(600)

    cdef inline int initialize_buffers(self) except -1:
        for buf_index in range(self.buf_req.count):
            memset(&self.buf, 0, sizeof(self.buf))
            self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
            self.buf.memory = V4L2_MEMORY_MMAP
            self.buf.index = buf_index

            if -1 == xioctl(self.fd, VIDIOC_QUERYBUF, &self.buf):
                raise CameraError('Querying buffer failed')

            bufptr = v4l2_mmap(NULL, self.buf.length,
                               PROT_READ | PROT_WRITE,
                               MAP_SHARED, self.fd, self.buf.m.offset)

            if bufptr == <void *>-1:
                raise CameraError('MMAP failed: {}'.format(
                    strerror(errno).decode())
                )

            self.buffers[buf_index] = buffer_info(bufptr, self.buf.length)

            memset(&self.buf, 0, sizeof(self.buf))
            self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
            self.buf.memory = V4L2_MEMORY_MMAP
            self.buf.index = buf_index

            if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
                raise CameraError('Exchanging buffer with device failed')

        return 0

    cdef list enumerate_menu(self, v4l2_queryctrl *queryctrl,
                             v4l2_querymenu *querymenu):
        menu = []

        if queryctrl.type == V4L2_CTRL_TYPE_MENU:
            memset(querymenu, 0, sizeof(querymenu[0]))
            querymenu.id = queryctrl.id

            for querymenu.index in range(queryctrl.minimum,
                                         queryctrl.maximum + 1):
                if 0 == xioctl(self.fd, VIDIOC_QUERYMENU, querymenu):
                    menu.append(querymenu.name.decode('utf-8'))
                else:
                    raise CameraError('Querying controls failed')

        return menu

    cpdef list get_controls(self):
        controls_list = []

        cdef v4l2_queryctrl queryctrl
        cdef v4l2_querymenu querymenu

        memset(&queryctrl, 0, sizeof(queryctrl))

        for queryctrl.id in range(V4L2_CID_BASE, V4L2_CID_LASTP1):
            if 0 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
                if queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
                    continue

                controls_list.append(
                    CameraControl(queryctrl.id, queryctrl.type,
                                  queryctrl.name.decode('utf-8'),
                                  queryctrl.default_value, queryctrl.minimum,
                                  queryctrl.maximum, queryctrl.step,
                                  self.enumerate_menu(&queryctrl, &querymenu),
                                  queryctrl.flags)
                )
            elif errno == EINVAL:
                continue
            else:
                raise CameraError('Querying controls failed')

        queryctrl.id = V4L2_CID_PRIVATE_BASE
        while True:
            if 0 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
                if queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
                    continue

                controls_list.append(
                    CameraControl(queryctrl.id, queryctrl.type,
                                  queryctrl.name.decode('utf-8'),
                                  queryctrl.default_value, queryctrl.minimum,
                                  queryctrl.maximum, queryctrl.step,
                                  self.enumerate_menu(&queryctrl, &querymenu),
                                  queryctrl.flags)
                )
            elif errno == EINVAL:
                break
            else:
                raise CameraError('Querying controls failed')

        return controls_list

    cpdef void set_control_value(self, control_id, value):
        cdef v4l2_queryctrl queryctrl
        cdef v4l2_control control

        memset(&queryctrl, 0, sizeof(queryctrl))
        queryctrl.id = control_id.value

        if -1 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
            if errno != EINVAL:
                raise CameraError('Querying control')
            else:
                raise AttributeError('Control is not supported')
        elif queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
            raise AttributeError('Control is not supported')
        else:
            memset(&control, 0, sizeof(control))
            control.id = control_id.value
            control.value = value

            if -1 == xioctl(self.fd, VIDIOC_S_CTRL, &control):
                raise CameraError('Setting control')

    cpdef int get_control_value(self, control_id):
        cdef v4l2_queryctrl queryctrl
        cdef v4l2_control control

        memset(&queryctrl, 0, sizeof(queryctrl))
        queryctrl.id = control_id.value

        if -1 == xioctl(self.fd, VIDIOC_QUERYCTRL, &queryctrl):
            if errno != EINVAL:
                raise CameraError('Querying control')
            else:
                raise AttributeError('Control is not supported')
        elif queryctrl.flags & V4L2_CTRL_FLAG_DISABLED:
            raise AttributeError('Control is not supported')
        else:
            memset(&control, 0, sizeof(control))
            control.id = control_id.value

            if 0 == xioctl(self.fd, VIDIOC_G_CTRL, &control):
                return control.value
            else:
                raise CameraError('Getting control')

    cdef np.ndarray[np.uint8_t, ndim=2] _get_frame(self):
        FD_ZERO(&self.fds)
        FD_SET(self.fd, &self.fds)
        cdef np.ndarray frame
        cdef int r

        self.tv.tv_sec = 2

        r = select(self.fd + 1, &self.fds, NULL, NULL, &self.tv)
        while -1 == r and errno == EINTR:
            FD_ZERO(&self.fds)
            FD_SET(self.fd, &self.fds)

            self.tv.tv_sec = 2

            r = select(self.fd + 1, &self.fds, NULL, NULL, &self.tv)

        if -1 == r:
            raise CameraError('Waiting for frame failed')

        memset(&self.buf, 0, sizeof(self.buf))
        self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.buf.memory = V4L2_MEMORY_MMAP

        if -1 == xioctl(self.fd, VIDIOC_DQBUF, &self.buf):
            raise CameraError('Retrieving frame failed')

        # Change from 10 bits per pixel to 8 bits per pixel
        cdef unsigned char *buffer_raw
        cdef unsigned char *buffer_processed
        buffer_raw = <unsigned char *>self.buffers[self.buf.index].start
        buffer_processed = <unsigned char*>malloc(self.frame_size)
        # To get coherent frame, incoming bytes need to be swapped
        cdef __u16 raw_pix_val
        cdef __u8 processed_pix_val, byte1, byte2

        for i in range(self.frame_size):
            byte1 = buffer_raw[2*i]
            byte2 = buffer_raw[2*i + 1]
            raw_pix_val = (byte2 << 8) | byte1

            processed_pix_val = <unsigned char>((255.0/1023.0) * <float>(raw_pix_val))

            buffer_processed[i] = processed_pix_val

        self.frame_data = buffer_processed
        self.timestamp = self.buf.timestamp.tv_sec * 1000000 + self.buf.timestamp.tv_usec
        
        if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
            raise CameraError('Exchanging buffer with device failed')

        frame = np.frombuffer(self.frame_data[:self.frame_size], dtype=np.uint8)
        return frame.reshape((self.height, self.width))

    def get_frame(self):
        frame = np.zeros((self.height, self.width), dtype=np.uint8)
        frame = self._get_frame()
        timestamp = self.timestamp
        return frame, timestamp

    cpdef void set_exposure(self, exposure):
        cdef v4l2_control control
        control.id = V4L2_CID_EXPOSURE_ABSOLUTE

        if -1 == xioctl(self.fd, VIDIOC_G_CTRL, &control):
            raise CameraError('Getting exposure')

        print(control.value)

        control.value = exposure

        if -1 == xioctl(self.fd, VIDIOC_S_CTRL, &control):
            raise CameraError('Setting exposure')

    cpdef void set_fps(self, fps):
        cdef v4l2_streamparm parm
        parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        parm.parm.capture.timeperframe.numerator = 1
        parm.parm.capture.timeperframe.denominator = fps

        parm.parm.capture.capability = 0x1000
        parm.parm.capture.capturemode = 0x0001

        if -1 == xioctl(self.fd, VIDIOC_S_PARM, &parm):
            raise CameraError('Setting fps')

    def close(self):
        xioctl(self.fd, VIDIOC_STREAMOFF, &self.buf.type)

        for i in range(self.buf_req.count):
            v4l2_munmap(self.buffers[i].start, self.buffers[i].length)

        v4l2_close(self.fd)


    
