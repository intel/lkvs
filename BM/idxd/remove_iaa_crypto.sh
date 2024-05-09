#!/bin/bash

iaa_dev_id="0cfe"
num_iaa=$(lspci -d:${iaa_dev_id} | wc -l)

for ((i = 1; i < num_iaa * 2; i += 2)); do
  echo disable wq iax${i}/wq${i}.0
  accel-config disable-wq iax${i}/wq${i}.0
  echo disable iaa iax${i}
  accel-config disable-device iax${i}
done

rmmod iaa_crypto
