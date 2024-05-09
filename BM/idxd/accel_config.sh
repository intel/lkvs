#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

function cmd_disable_device() {
  dev_dir=$1

  if [ -d "/sys/bus/dsa/devices/$dev_dir" ]; then
    if echo "$dev_dir" > /sys/bus/dsa/drivers/idxd/unbind;
    then
      echo "device $dev_dir disabled"
    else
      echo "device $dev_dir not disabled"
      exit 1
    fi
  else
    echo "device $dev_dir not found"
    exit 1
  fi
}

function cmd_enable_device() {
  dev_dir=$1

  if [ -d "/sys/bus/dsa/devices/$dev_dir" ]; then
    if echo "$dev_dir" > /sys/bus/dsa/drivers/idxd/bind;
    then
      echo "device $dev_dir enabled"
    else
      echo "device $dev_dir not enabled"
      exit 1
    fi
  else
    echo "device $dev_dir not found"
    exit 1
  fi
}

function cmd_disable_wq() {
  dev_dir=$(echo "$1" | cut -d "/" -f 1)
  wq_dir=$(echo "$1" | cut -d "/" -f 2)

  if [[ -d "/sys/bus/dsa/devices/$dev_dir" ]] && [[ -d "/sys/bus/dsa/devices/$wq_dir" ]]; then
    driver_name=$(cat /sys/bus/dsa/devices/"$wq_dir"/driver_name)
    if [ -d "/sys/bus/dsa/drivers/$driver_name" ]; then
      if echo "$wq_dir" > "/sys/bus/dsa/drivers/$driver_name/unbind";
      then
        echo "wq $wq_dir disabled"
      else
        echo "wq $wq_dir not disabled"
        exit 1
      fi
    else
      echo "Invalid wq driver name $driver_name"
      exit 1
    fi
  else
    echo "wq $dev_dir/$wq_dir not found"
    exit 1
  fi
}

function cmd_enable_wq() {
  dev_dir=$(echo "$1" | cut -d "/" -f 1)
  wq_dir=$(echo "$1" | cut -d "/" -f 2)

  if [[ -d "/sys/bus/dsa/devices/$dev_dir" ]] && [[ -d "/sys/bus/dsa/devices/$wq_dir" ]]; then
    driver_name=$(cat /sys/bus/dsa/devices/"$wq_dir"/driver_name)
    if [ -d "/sys/bus/dsa/drivers/$driver_name" ]; then
      if echo "$wq_dir" > "/sys/bus/dsa/drivers/$driver_name/bind";
      then
        echo "wq $wq_dir enabled"
      else
        echo "wq $wq_dir not enabled"
        exit 1
      fi
    else
      echo "Invalid wq driver name $driver_name"
      exit 1
    fi
  else
    echo "wq $dev_dir/$wq_dir not found"
    exit 1
  fi
}

function cmd_config_device() {
  dev_read_buffer_limit=""
  dev_event_log_size=""

  ARGS=$(getopt -o l:e: \
--long read-buffer-limit:,event-log-size: -n "$0" -- "$@")
  rtn=$?
  if [ $rtn != 0 ]; then
    echo "Terminating..."
    exit 1
  fi

  eval set -- "${ARGS}"

  while true
  do
    case "$1" in
    -l|--read-buffer-limit)
      dev_read_buffer_limit=$2;
      shift 2
    ;;
    -e|--event-log-size)
      dev_event_log_size=$2;
      shift 2
    ;;
    --)
      shift
      break
    ;;
    *)
      echo "unknown option $1"
      exit 1
    ;;
    esac
  done

  dev_dir=$1

  if [ -d "/sys/bus/dsa/devices/$dev_dir" ]; then
    if [ "$dev_read_buffer_limit" != "" ]; then
      echo "$dev_read_buffer_limit" > "/sys/bus/dsa/devices/$dev_dir/read_buffer_limit"
    fi
    if [ "$dev_event_log_size" != "" ]; then
      echo "$dev_event_log_size" > "/sys/bus/dsa/devices/$dev_dir/event_log_size"
    fi
  else
    echo "device $dev_dir not found"
    exit 1
  fi
}

function cmd_config_group() {
  grp_read_buffers_reserved=""
  grp_read_buffers_allowed=""
  grp_use_read_buffer_limit=""
  grp_traffic_class_a=""
  grp_traffic_class_b=""
  grp_desc_progress_limit=""
  grp_batch_progress_limit=""

  ARGS=$(getopt -o r:t:l:a:b:d:p: \
--long read-buffers-reserved:,read-buffers-allowed:,\
use-read-buffer-limit:,traffic-class-a:,traffic-class-b:,\
desc-progress-limit:,batch-progress-limit: -n "$0" -- "$@")
  rtn=$?
  if [ $rtn != 0 ]; then
    echo "Terminating..."
    exit 1
  fi

  eval set -- "${ARGS}"

  while true
  do
    case "$1" in
    -r|--read-buffers-reserved)
      grp_read_buffers_reserved=$2
      shift 2
    ;;
    -t|--read-buffers-allowed)
      grp_read_buffers_allowed=$2
      shift 2
    ;;
    -l|--use-read-buffer-limit)
      grp_use_read_buffer_limit=$2
      shift 2
    ;;
    -a|--traffic-class-a)
      grp_traffic_class_a=$2
      shift 2
    ;;
    -b|--traffic-class-b)
      grp_traffic_class_b=$2
      shift 2
    ;;
    -d|--desc-progress-limit)
      grp_desc_progress_limit=$2
      shift 2
    ;;
    -p|--batch-progress-limit)
      grp_batch_progress_limit=$2
      shift 2
    ;;
    --)
      shift
      break
    ;;
    *)
      echo "unknown option $1"
      exit 1
      ;;
    esac
  done

  grp_dir=$1

  if [ -d "/sys/bus/dsa/devices/$grp_dir" ]; then
    if [ "$grp_read_buffers_reserved" != "" ]; then
      echo "$grp_read_buffers_reserved" > "/sys/bus/dsa/devices/$grp_dir/read_buffers_reserved"
    fi
    if [ "$grp_read_buffers_allowed" != "" ]; then
      echo "$grp_read_buffers_allowed" > "/sys/bus/dsa/devices/$grp_dir/read_buffers_allowed"
    fi
    if [ "$grp_use_read_buffer_limit" != "" ]; then
      echo "$grp_use_read_buffer_limit" > "/sys/bus/dsa/devices/$grp_dir/use_read_buffer_limit"
    fi
    if [ "$grp_traffic_class_a" != "" ]; then
      echo "$grp_traffic_class_a" > "/sys/bus/dsa/devices/$grp_dir/traffic_class_a"
    fi
    if [ "$grp_traffic_class_b" != "" ]; then
      echo "$grp_traffic_class_b" > "/sys/bus/dsa/devices/$grp_dir/traffic_class_b"
    fi
    if [ "$grp_desc_progress_limit" != "" ]; then
      echo "$grp_desc_progress_limit" > "/sys/bus/dsa/devices/$grp_dir/desc_progress_limit"
    fi
    if [ "$grp_batch_progress_limit" != "" ]; then
      echo "$grp_batch_progress_limit" > "/sys/bus/dsa/devices/$grp_dir/batch_progress_limit"
    fi
  else
    echo "group $grp_dir not found"
    exit 1
  fi
}

function cmd_config_wq() {
  wq_group_id=""
  wq_size=""
  wq_priority=""
  wq_block_on_fault=""
  wq_prs_disable=""
  wq_threshold=""
  wq_type=""
  wq_name=""
  wq_driver_name=""
  wq_op_config=""
  wq_mode=""
  wq_max_batch_size=""
  wq_max_transfer_size=""
  wq_ats_disable=""

  ARGS=$(getopt -o g:s:p:b:r:t:y:n:d:o:m:c:x:a: \
--long group-id:,wq-size:,priority:,block-on-fault:,prs-disable:,\
threshold:,type:,name:,driver-name:,op-config:,mode:,max-batch-size:,\
max-transfer-size:,ats-disable: -n "$0" -- "$@")
  rtn=$?
  if [ $rtn != 0 ]; then
    echo "Terminating..."
    exit 1
  fi

  eval set -- "${ARGS}"

  while true
  do
    case "$1" in
    -g|--group-id)
      wq_group_id=$2
      shift 2
    ;;
    -s|--wq-size)
      wq_size=$2
      shift 2
    ;;
    -p|--priority)
      wq_priority=$2
      shift 2
    ;;
    -b|--block-on-fault)
      wq_block_on_fault=$2
      shift 2
    ;;
    -r|--prs-disable)
      wq_prs_disable=$2
      shift 2
    ;;
    -t|--threshold)
      wq_threshold=$2
      shift 2
    ;;
    -y|--type)
      wq_type=$2
      shift 2
    ;;
    -n|--name)
      wq_name=$2
      shift 2
    ;;
    -d|--driver-name)
      wq_driver_name=$2
      shift 2
    ;;
    -o|--op-config)
      wq_op_config=$2
      shift 2
    ;;
    -m|--mode)
      wq_mode=$2
      shift 2
    ;;
    -c|--max-batch-size)
      wq_max_batch_size=$2
      shift 2
    ;;
    -x|--max-transfer-size)
      wq_max_transfer_size=$2
      shift 2
    ;;
    -a|--ats-disable)
      wq_ats_disable=$2
      shift 2
    ;;
    --)
      shift
      break
    ;;
    *)
      echo "unknown option $1"
      exit 1
    ;;
    esac
  done

  dev_dir=$(echo "$1" | cut -d "/" -f 1)
  wq_dir=$(echo "$1" | cut -d "/" -f 2)

  if [[ -d "/sys/bus/dsa/devices/$dev_dir" ]] && [[ -d "/sys/bus/dsa/devices/$wq_dir" ]]; then
    if [ "$wq_group_id" != "" ]; then
      echo "$wq_group_id" > "/sys/bus/dsa/devices/$wq_dir/group_id"
    fi
    if [ "$wq_size" != "" ]; then
      echo "$wq_size" > "/sys/bus/dsa/devices/$wq_dir/size"
    fi
    if [ "$wq_priority" != "" ]; then
      echo "$wq_priority" > "/sys/bus/dsa/devices/$wq_dir/priority"
    fi
    if [ "$wq_block_on_fault" != "" ]; then
      echo "$wq_block_on_fault" > "/sys/bus/dsa/devices/$wq_dir/block_on_fault"
    fi
    if [ "$wq_prs_disable" != "" ]; then
      echo "$wq_prs_disable" > "/sys/bus/dsa/devices/$wq_dir/prs_disable"
    fi
    if [ "$wq_threshold" != "" ]; then
      echo "$wq_threshold" > "/sys/bus/dsa/devices/$wq_dir/threshold"
    fi
    if [ "$wq_type" != "" ]; then
      echo "$wq_type" > "/sys/bus/dsa/devices/$wq_dir/type"
    fi
    if [ "$wq_name" != "" ]; then
      echo "$wq_name" > "/sys/bus/dsa/devices/$wq_dir/name"
    fi
    if [ "$wq_driver_name" != "" ]; then
      echo "$wq_driver_name" > "/sys/bus/dsa/devices/$wq_dir/driver_name"
    fi
    if [ "$wq_op_config" != "" ]; then
      echo "$wq_op_config" > "/sys/bus/dsa/devices/$wq_dir/op_config"
    fi
    if [ "$wq_mode" != "" ]; then
      echo "$wq_mode" > "/sys/bus/dsa/devices/$wq_dir/mode"
    fi
    if [ "$wq_max_batch_size" != "" ]; then
      echo "$wq_max_batch_size" > "/sys/bus/dsa/devices/$wq_dir/max_batch_size"
    fi
    if [ "$wq_max_transfer_size" != "" ]; then
      echo "$wq_max_transfer_size" > "/sys/bus/dsa/devices/$wq_dir/max_transfer_size"
    fi
    if [ "$wq_ats_disable" != "" ]; then
      echo "$wq_ats_disable" > "/sys/bus/dsa/devices/$wq_dir/ats_disable"
    fi
  else
    echo "wq $dev_dir/$wq_dir not found"
    exit 1
  fi
}

function cmd_config_engine() {
  eng_group_id=""

  ARGS=$(getopt -o g: --long group-id: -n "$0" -- "$@")
  rtn=$?
  if [ $rtn != 0 ]; then
    echo "Terminating..."
    exit 1
  fi

  eval set -- "${ARGS}"

  while true
  do
    case "$1" in
    -g|--group-id)
      eng_group_id=$2;
      shift 2
    ;;
    --)
      shift
      break
    ;;
    *)
      echo "unknown option $1"
      exit 1
    ;;
    esac
  done

  eng_dir=$1

  if [ -d "/sys/bus/dsa/devices/$eng_dir" ]; then
    if [ "$eng_group_id" != "" ]; then
      echo "$eng_group_id" > "/sys/bus/dsa/devices/$eng_dir/group_id"
    fi
  else
    echo "engine $eng_dir not found"
    exit 1
  fi
}

case "$1" in
disable-device)
  shift
  cmd_disable_device "$@"
;;
enable-device)
  shift
  cmd_enable_device "$@"
;;
disable-wq)
  shift
  cmd_disable_wq "$@"
;;
enable-wq)
  shift
  cmd_enable_wq "$@"
;;
config-device)
  shift
  cmd_config_device "$@"
;;
config-group)
  shift
  cmd_config_group "$@"
;;
config-wq)
  shift
  cmd_config_wq "$@"
;;
config-engine)
  shift
  cmd_config_engine "$@"
;;
\?)
  echo "Unknown command: $1"
  exit 1
;;
esac

exit 0
