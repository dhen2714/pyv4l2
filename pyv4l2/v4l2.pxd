from libc.errno cimport errno, EINTR
from posix.select cimport timeval

cdef extern from 'linux/videodev2.h':
    ctypedef unsigned char           __u8
    ctypedef signed char             __s8
    ctypedef unsigned short          __u16
    ctypedef signed short            __s16
    ctypedef unsigned int            __u32
    ctypedef signed int              __s32
    ctypedef unsigned long long int  __u64
    ctypedef signed long long int    __s64
    
    enum: VIDIOC_G_FMT
    enum: VIDIOC_S_FMT
    enum: VIDIOC_REQBUFS
    enum: VIDIOC_QUERYBUF
    enum: VIDIOC_STREAMON
    enum: VIDIOC_STREAMOFF
    enum: VIDIOC_QBUF
    enum: VIDIOC_DQBUF
    enum: VIDIOC_QUERYMENU
    enum: VIDIOC_QUERYCTRL
    enum: VIDIOC_G_CTRL
    enum: VIDIOC_S_CTRL
    enum: V4L2_CID_BASE
    enum: V4L2_CID_LASTP1
    enum: V4L2_CID_PRIVATE_BASE
    enum: V4L2_CTRL_FLAG_DISABLED

    enum: VIDIOC_S_PARM
    enum: VIDIOC_G_PARM

    enum: V4L2_CTRL_FLAG_DISABLED
    enum: V4L2_CTRL_FLAG_GRABBED
    enum: V4L2_CTRL_FLAG_READ_ONLY
    enum: V4L2_CTRL_FLAG_UPDATE
    enum: V4L2_CTRL_FLAG_INACTIVE
    enum: V4L2_CTRL_FLAG_WRITE_ONLY
    
    enum: V4L2_CID_BRIGHTNESS
    enum: V4L2_CID_CONTRAST
    enum: V4L2_CID_SATURATION
    enum: V4L2_CID_HUE
    enum: V4L2_CID_AUDIO_VOLUME
    enum: V4L2_CID_AUDIO_BALANCE
    enum: V4L2_CID_AUDIO_BASS
    enum: V4L2_CID_AUDIO_TREBLE
    enum: V4L2_CID_AUDIO_MUTE
    enum: V4L2_CID_AUDIO_LOUDNESS
    enum: V4L2_CID_BLACK_LEVEL
    enum: V4L2_CID_AUTO_WHITE_BALANCE
    enum: V4L2_CID_DO_WHITE_BALANCE
    enum: V4L2_CID_RED_BALANCE
    enum: V4L2_CID_BLUE_BALANCE
    enum: V4L2_CID_GAMMA
    enum: V4L2_CID_WHITENESS
    enum: V4L2_CID_EXPOSURE
    enum: V4L2_CID_EXPOSURE_ABSOLUTE
    enum: V4L2_CID_AUTOGAIN
    enum: V4L2_CID_GAIN
    enum: V4L2_CID_HFLIP
    enum: V4L2_CID_VFLIP
    enum: V4L2_CID_POWER_LINE_FREQUENCY
    enum: V4L2_CID_HUE_AUTO
    enum: V4L2_CID_WHITE_BALANCE_TEMPERATURE
    enum: V4L2_CID_SHARPNESS
    enum: V4L2_CID_BACKLIGHT_COMPENSATION
    enum: V4L2_CID_CHROMA_AGC
    enum: V4L2_CID_COLOR_KILLER 
    enum: V4L2_CID_COLORFX

    enum: V4L2_BUF_TYPE_VIDEO_CAPTURE

    cdef struct v4l2_pix_format:
        __u32   width
        __u32   height
        __u32   pixelformat
        __u32   field
        __u32   bytesperline
        __u32   sizeimage
        __u32   colorspace
        __u32   priv
        __u32   flags
        __u32   ycbcr_enc
        __u32   quantization
        __u32   xfer_func

    cdef union __v4l2_format_fmt:
        v4l2_pix_format        pix
        __u8                   raw_data[200]

    cdef struct v4l2_format:
        __u32 type
        __v4l2_format_fmt fmt
            

    cdef struct v4l2_requestbuffers:
        __u32 count
        __u32 type
        __u32 memory

    cdef union __v4l2_buffer_m:
        __u32          offset
        unsigned long  userptr
        __s32          fd

    cdef struct v4l2_buffer:
        __u32 index
        __u32 type
        __u32 memory
        __u32 length
        __u32 bytesused
        timeval timestamp

        __v4l2_buffer_m m

    cdef enum v4l2_ctrl_type:
        V4L2_CTRL_TYPE_INTEGER
        V4L2_CTRL_TYPE_BOOLEAN
        V4L2_CTRL_TYPE_MENU
        V4L2_CTRL_TYPE_BUTTON
        V4L2_CTRL_TYPE_INTEGER64
        V4L2_CTRL_TYPE_STRING
        V4L2_CTRL_TYPE_CTRL_CLASS

    cdef struct v4l2_queryctrl:
        __u32             id
        v4l2_ctrl_type    type
        __u8	          name[32]
        __s32	          minimum
        __s32	          maximum
        __s32	          step
        __s32	          default_value
        __u32	          flags
        __u32	          reserved[2]

    cdef struct v4l2_querymenu:
        __u32 id
        __u32 index
        __u8  name[32]
        __u32 reserved

    cdef struct v4l2_control:
        __u32 id
        __s32 value

    cdef struct v4l2_fract:
        __u32 numerator
        __u32 denominator

    cdef struct v4l2_captureparm:
        __u32 capability
        __u32 capturemode
        v4l2_fract timeperframe
        __u32 extendedmode
        __u32 readbuffers
        __u32 reserved[4]

    cdef struct v4l2_outputparm:
        __u32 capability
        __u32 outputmode
        v4l2_fract timeperframe
        __u32 extendedmode
        __u32 writebuffers
        __u32 reserved[4]

    cdef union parm:
        v4l2_captureparm capture
        v4l2_outputparm output
        __u8 raw_data[200]

    cdef struct v4l2_streamparm:
        __u32 type
        parm parm

    cdef struct v4l2_frmivalenum:
        __u32 index
        __u32 pixel_format
        __u32 width
        __u32 height
        __u32 type
        


cdef extern from 'libv4l2.h':
    enum: V4L2_PIX_FMT_YUYV
    enum: V4L2_PIX_FMT_GREY
    # enum: V4L2_BUF_TYPE_VIDEO_CAPTURE
    enum: V4L2_MEMORY_MMAP
    enum: V4L2_FIELD_ANY

    int v4l2_open(const char *device_name, int flags)
    int v4l2_close(int fd)

    int v4l2_ioctl(int fd, int request, void *argp)

    void *v4l2_mmap(void *start, size_t length, int prot, int flags, int fd,
                    __s64 offset)
    int v4l2_munmap(void *_start, size_t length)

cdef inline int xioctl(int fd, unsigned long int request, void *arg):
    cdef int r = v4l2_ioctl(fd, request, arg)
    while -1 == r and EINTR == errno:
        r = v4l2_ioctl(fd, request, arg)

    return r

cdef struct buffer_info:
    void *start
    size_t length

cdef extern from 'sys/ioctl.h':
    int ioctl(int fd, unsigned long request, void *argp)

cdef extern from 'linux/uvcvideo.h':
    #enum: UVC_SET_CUR
    enum: UVCIOC_CTRL_QUERY

    cdef struct uvc_xu_control_query:
        __u8 unit
        __u8 selector
        __u8 query
        __u16 size
        __u8 *data
