#!/bin/bash
aclocal -I m4

autoconf

automake --add-missing

./configure

make
