#!/usr/bin/env python3
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
import numpy

extensions = [
    Extension('pyv4l2.camera', ['pyv4l2/camera.pyx'],
        include_dirs=[numpy.get_include(), 'src'],
        libraries=['v4l2']),
    # Everything but primes.pyx is included here.
    Extension('pyv4l2.controls', ['pyv4l2/controls.pyx'],
        include_dirs=[numpy.get_include()],
        libraries=['v4l2'])
]

setup(
    name='pyv4l2',
    #version=__version__,
    packages=['pyv4l2'],
    description='libv4l2 based frame grabber for OV580-OV7251',
    license='GNU Lesser General Public License v3 (LGPLv3)',
    ext_modules=cythonize(extensions, compiler_directives={'language_level' : '3'}),
)
# setup(
#     ext_modules = cythonize("PyV4L2/*")
# )


# setup(
#     name='PyV4L2Camera',
#     version=__version__,
#     description='Simple, libv4l2 based frame grabber',
#     author='Dominik Pieczyński',
#     author_email='dominik.pieczynski@gmail.com',
#     url='https://gitlab.com/radish/PyV4L2Camera',
#     license='GNU Lesser General Public License v3 (LGPLv3)',
#     ext_modules=extensions,
#     extras_require={
#         'examples': ['pillow', 'numpy'],
#     },
#     packages=find_packages()
# )

# import sys
# import numpy
# # from setuptools import setup, find_packages
# from distutils.core import setup, Extension
# from setuptools import find_packages
# # from setuptools.extension import Extension

# from PyV4L2Camera import __version__

# try:
#     sys.argv.remove('--use-cython')
#     USE_CYTHON = True
# except ValueError:
#     USE_CYTHON = False

# ext = '.pyx' if USE_CYTHON else '.c'
# extensions = [
#     Extension(
#         'PyV4L2.camera',
#         ['PyV4L2Camera/camera' + ext],
#         libraries=['v4l2', ],
#         include_dirs=[numpy.get_include()]
#     ),
#     Extension(
#         'PyV4L2.controls',
#         ['PyV4L2Camera/controls' + ext],
#         libraries=['v4l2', ],
#         include_dirs=[numpy.get_include()]
#     )
# ]

# if USE_CYTHON:
#     from Cython.Build import cythonize
#     extensions = cythonize(extensions)

# setup(
#     name='PyV4L2Camera',
#     version=__version__,
#     description='Simple, libv4l2 based frame grabber',
#     author='Dominik Pieczyński',
#     author_email='dominik.pieczynski@gmail.com',
#     url='https://gitlab.com/radish/PyV4L2Camera',
#     license='GNU Lesser General Public License v3 (LGPLv3)',
#     ext_modules=extensions,
#     extras_require={
#         'examples': ['pillow', 'numpy'],
#     },
#     packages=find_packages()
# )
