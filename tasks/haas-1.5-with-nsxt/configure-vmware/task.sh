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

# add new portgroups

/opt/pyvmomi/add_portgroup_to_vswitch.py \
  --user $ESX_USR \
  --password $ESX_PWD \
  --host $ESX_HOST \
  --portgroup TEP \
  --vlanid 0 \
  --vswitch vSwitch0

/opt/pyvmomi/add_portgroup_to_vswitch.py \
  --user $ESX_USR \
  --password $ESX_PWD \
  --host $ESX_HOST \
  --portgroup T0-Uplink \
  --vlanid $SECOND_VLAN \
  --vswitch vSwitch1

# change MTU

/opt/pyvmomi/update_vswitch_mtu.py \
   --user $ESX_USR \
   --password $ESX_PWD \
   --host $ESX_HOST \
   --mtu $MTU \
   --vswitch vSwitch0
