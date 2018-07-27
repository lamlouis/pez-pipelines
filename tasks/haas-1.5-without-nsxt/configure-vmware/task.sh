#!/bin/bash -eu
#

# create vSwitch1

/opt/pyvmomi/add_vswitch_to_host.py \
  --user $ESX_USR \
  --password $ESX_PWD \
  --host $ESX_HOST \
  --vswitch vSwitch1 \
  --uplink1 vmnic4 \
  --uplink2 vmnic5

# add new portgroup

/opt/pyvmomi/add_portgroup_to_vswitch.py \
  --user $ESX_USR \
  --password $ESX_PWD \
  --host $ESX_HOST \
  --portgroup PAS\
  --vlanid $SECOND_VLAN \
  --vswitch vSwitch1
