#!/bin/sh
ret=0
cd /home/cuda-samples/Samples/0_Introduction || ret=1
if [ $ret -ne 0 ]; then
    echo "Cuda samples not found, please make sure /home/cuda-samples/Samples/0_Introduction is installed and built "
    exit 1
fi
folder="matrixMul matrixMulDrv matrixMulDynlinkJIT vectorAdd vectorAddDrv vectorAddMMAP vectorAdd_nvrtc"
echo "Start cuda test ----------------"
for i in $folder; do
    echo "Start test $i ----------------"
    cd $i || ret=1
    ./$i || ret=1
    cd ../
    if [ $ret -ne 0 ]; then
        echo "Cuda test $i fail"
        exit $ret
    else
        echo "Cuda test $i pass"
    fi
done
