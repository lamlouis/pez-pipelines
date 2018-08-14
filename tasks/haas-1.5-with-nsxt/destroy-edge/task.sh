#!/bin/bash -eu

echo "Destroying edge"

cat << EOF > nsx.ini
[nsxv]
nsx_manager = $NSX_EDGE_GEN_NSX_MANAGER_ADDRESS
nsx_username = $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_USER
nsx_password = $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_PASSWD

[vcenter]
vcenter = $MGMT_VCENTER_HOST
vcenter_user = $MGMT_VCENTER_USR
vcenter_passwd = $MGMT_VCENTER_PWD

[defaults]
transport_zone = $NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE
datacenter_name = $MGMT_VCENTER_DATA_CENTER
edge_datastore =  $NSX_EDGE_GEN_EDGE_DATASTORE
edge_cluster = $NSX_EDGE_GEN_EDGE_CLUSTER
EOF

pynsxv_local() {
  /opt/pynsxv/cli.py "$@"
  return $?
}

# delete the NAT rules on sc2-esg-external-zone
echo "deleting NAT on $NSX_EDGE_EXTERNAL_ZONE"

# pick out the first 3 octets of the IP address
NET=`echo $ESG_INTERNAL_IP_1 | sed 's/\.[0-9]*$//'`

pynsxv_local nat get_nat_rules_tip \
  --esg_name $NSX_EDGE_EXTERNAL_ZONE \
  --original_ip $HAAS_SLOT_NAT_IP \
  --translated_ip $NET \
  | while read ruleID; do
	if  [[ $ruleID =~ ^[0-9]+$ ]]; then
		echo "Deleting rule $ruleID"
	 	pynsxv_local nat delete_nat -n $NSX_EDGE_EXTERNAL_ZONE -r $ruleID
	else
		echo "Error: $ruleID"
	fi
done

# delete the edge

echo "deleting edge"

pynsxv_local esg delete \
  --esg_name $NSX_EDGE_GEN_NAME
