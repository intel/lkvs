#!/bin/bash

############################# Global variables ################################
DMA_MODULE="dmatest"
lasttime=$(dmesg | tail -1 | cut -d']' -f1 | sed 's/.*\[\|\s//g')

########################### DYNAMICALLY-DEFINED Params ########################
: "${TEST_LOOP:='1'}"
: "${THREAD:='1'}"
: "${ITERATION:='10000'}"
: "${BUFF_SIZE:='4096'}"
: "${DMA_CH:=''}"

############################# Functions #######################################
usage()
{
  cat <<-EOF >&2
    usage: ./${0##*/}  [-l TEST_LOOP] [-t TESTCASE_ID] [-p THREADS] [-i ITERATIONS] [-b BUFF_SIZE] [-c DMA_CH]
    -l TEST_LOOP  test loop
    -p THREADS how many threads use dma
    -i ITERATIONS transfer for how many times
    -b BUFF_SIZE DMA buffer size
    -c DMA_CH which channel to be test
    -h Help   print this usage
EOF
  exit 0
}

init_device()
{
  echo dsa0 > /sys/bus/dsa/drivers/idxd/unbind || true
  modprobe -r idxd || true
  modprobe idxd
  echo 0 > /sys/bus/dsa/devices/dsa0/wq0.0/group_id
  echo dedicated > /sys/bus/dsa/devices/dsa0/wq0.0/mode
  echo 10 > /sys/bus/dsa/devices/dsa0/wq0.0/priority
  echo 16 > /sys/bus/dsa/devices/dsa0/wq0.0/size
  echo "kernel" > /sys/bus/dsa/devices/dsa0/wq0.0/type
  echo "dma2chan0" > /sys/bus/dsa/devices/dsa0/wq0.0/name
  echo "dmaengine" > /sys/bus/dsa/devices/dsa0/wq0.0/driver_name
  echo 0 > /sys/bus/dsa/devices/dsa0/engine0.0/group_id
  echo dsa0 > /sys/bus/dsa/drivers/idxd/bind
  echo wq0.0 > /sys/bus/dsa/drivers/dmaengine/bind
}

############################### CLI Params ###################################
while getopts :l:p:i:b:c:h arg; do
  case $arg in
    l)  TEST_LOOP="$OPTARG";;
    p)  THREAD="$OPTARG";;
    i)  ITERATION="$OPTARG";;
    b)  BUFF_SIZE="$OPTARG";;
    c)  DMA_CH="$OPTARG";;
    h)  usage;;
    :)  echo "$0: Must supply an argument to -$OPTARG."
        exit 1
    ;;
    \?) echo "Invalid Option -$OPTARG ignored."
        usage
        exit 1
    ;;
  esac
done

init_device

i=0
while [ $i -lt $TEST_LOOP ]; do
  modprobe -r dmatest || true
  modprobe dmatest run=$THREAD iterations=$ITERATION wait=1 test_buf_size=$BUFF_SIZE channel=$DMA_CH timeout=2000 || {
    echo "Failed to modprobe $DMA_MODULE"
    exit 1
  }
  
  result=$(dmesg | sed "1,/$lasttime/d" | grep dmatest | grep -w "0 failures")
  
  i=$((i+1))
done

modprobe -r dmatest
echo dsa0 > /sys/bus/dsa/drivers/idxd/unbind

[ -z "$result" ] && {
  echo "DMA mem2mem copy failed, dmesg is:$(dmesg | sed "1,/$lasttime/d")"
  exit 1
}

exit 0

