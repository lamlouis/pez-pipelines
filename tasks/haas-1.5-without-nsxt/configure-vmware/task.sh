#!/bin/bash -eu
#

# create vSwitch1

/opt/pyvmomi/add_vswitch_to_host.py \
  --user $HAAS_SLOT_VCENTER_USR \
  --password $HAAS_SLOT_VCENTER_PWD \
  --host $HAAS_SLOT_VCENTER_HOST \
  --vswitch vSwitch1 \
  --uplink1 vmnic4 \
  --uplink2 vmnic5

# add new portgroup

/opt/pyvmomi/add_portgroup_to_vswitch.py \
  --user $HAAS_SLOT_VCENTER_USR \
  --password $HAAS_SLOT_VCENTER_PWD \
  --host $HAAS_SLOT_VCENTER_HOST \
  --portgroup PAS\
  --vlanid $SECOND_VLAN \
  --vswitch vSwitch1
