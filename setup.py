"""
1) Install numpy and cython:
    pip install numpy
    pip install cython
2) Build extension modules in pyv4l2 directory:
    python setup.py build --inplace 
Or install them into package directory:
    python setup.py install
"""
from setuptools import setup, Extension, find_packages
from Cython.Build import cythonize
import numpy


extensions = [
    Extension('pyv4l2.camera', ['pyv4l2/camera.pyx'],
        include_dirs=[numpy.get_include(), 'src'],
        libraries=['v4l2']),
    Extension('pyv4l2.controls', ['pyv4l2/controls.pyx'],
        include_dirs=[numpy.get_include()],
        libraries=['v4l2']),
    Extension('pyv4l2.exceptions', ['pyv4l2/exceptions.py'])
]


setup(
    name='pyv4l2',
    #version=__version__,
    packages=['pyv4l2'],
    description='libv4l2 based frame grabber for OV580-OV7251',
    license='GNU Lesser General Public License v3 (LGPLv3)',
    ext_modules=cythonize(extensions, compiler_directives={'language_level' : '3'}),
)