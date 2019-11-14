from pyv4l2.v4l2 cimport *
from libc.errno cimport errno, EINTR, EINVAL
from libc.string cimport memset, memcpy, strerror
from libc.stdlib cimport malloc, calloc, free
from posix.select cimport fd_set, timeval, FD_ZERO, FD_SET, select
from posix.fcntl cimport O_RDWR
from posix.mman cimport PROT_READ, PROT_WRITE, MAP_SHARED

from pyv4l2.controls import CameraControl
from pyv4l2.exceptions import CameraError

import numpy as np
cimport numpy as np

cdef class Camera:
    cdef int fd
    cdef fd_set fds

    cdef v4l2_format fmt
    cdef v4l2_format dest_fmt
    cdef v4l2_format frame_fmt

    cdef public unsigned int width
    cdef public unsigned int height

    cdef unsigned int conv_dest_size
    cdef unsigned char *conv_dest
    cdef unsigned int frame_dest_size
    cdef unsigned char *frame_dest

    cdef unsigned int frame_size
    cdef unsigned char *frame

    cdef v4l2_requestbuffers buf_req
    cdef v4l2_buffer buf
    cdef buffer_info *buffers

    cdef timeval tv
    cdef v4lconvert_data *convert_data
    cdef v4lconvert_data *frame_data

    def __cinit__(self, device_path,
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

        self.width = width
        self.height = height

        self.frame_size = width * height
        self.frame = <unsigned char *>malloc(self.frame_size)

        self.frame_fmt.type = self.fmt.type
        self.frame_fmt.fmt.pix.width = self.fmt.fmt.pix.width
        self.frame_fmt.fmt.pix.height = self.fmt.fmt.pix.height
        self.frame_fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_GREY
        self.frame_fmt.fmt.pix.field = V4L2_FIELD_ANY

        self.frame_dest_size = self.width * self.height
        self.frame_dest = <unsigned char *>malloc(self.conv_dest_size)
        if self.frame_dest == NULL:
            raise CameraError('Allocating memory for converted data failed')
        self.frame_data = v4lconvert_create(self.fd)

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

    cpdef bytes get_frame(self):
        FD_ZERO(&self.fds)
        FD_SET(self.fd, &self.fds)
        #cdef np.ndarray h = np.zeros([self.width, self.height], dtype=np.uint8)

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

        #print(self.buf.bytesused)

        
        if -1 == v4lconvert_convert(
                self.convert_data,
                &self.fmt, &self.dest_fmt,
                <unsigned char *>self.buffers[self.buf.index].start,
                self.buf.bytesused,
                self.conv_dest,
                self.conv_dest_size
        ):
            raise CameraError('Conversion failed')
        
        self.conv_dest = <unsigned char *>self.buffers[self.buf.index].start
        
        if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
            raise CameraError('Exchanging buffer with device failed')

        #print(self.conv_dest_size)
        #h = np.frombuffer(self.conv_dest[:self.conv_dest_size], dtype=np.uint8).reshape((480, 1280))
        return self.conv_dest[:self.conv_dest_size]
        #return self.conv_dest[:self.conv_dest_size]
        #return <unsigned char *>self.buffers[self.buf.index].start

    cpdef np.ndarray[np.uint8_t, ndim=2] read(self):
        FD_ZERO(&self.fds)
        FD_SET(self.fd, &self.fds)
        cdef np.ndarray h = np.zeros([self.width, self.height], dtype=np.uint8)

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

        """
        if -1 == v4lconvert_convert(
                self.frame_data,
                &self.fmt, &self.frame_fmt,
                <unsigned char *>self.buffers[self.buf.index].start,
                self.buf.bytesused,
                self.frame_dest,
                self.frame_dest_size
        ):
            raise CameraError('Conversion failed')
        """
        #lul = <unsigned char *>malloc(self.conv_dest_size)
        #self.frame_dest = <unsigned char *>self.buffers[self.buf.index].start
        self.frame = <unsigned char *>self.buffers[self.buf.index].start
        
        if -1 == xioctl(self.fd, VIDIOC_QBUF, &self.buf):
            raise CameraError('Exchanging buffer with device failed')

        #h = np.frombuffer(self.frame_dest[:self.frame_dest_size], dtype=np.uint8).reshape((480, 1280))
        h = np.frombuffer(self.frame[:self.frame_size], dtype=np.uint8).reshape((480, 1280))
        return h
    

    def close(self):
        xioctl(self.fd, VIDIOC_STREAMOFF, &self.buf.type)

        for i in range(self.buf_req.count):
            v4l2_munmap(self.buffers[i].start, self.buffers[i].length)

        v4l2_close(self.fd)
