#!/bin/bash -eu

echo "Creating edge"

cat << EOF > nsx.ini
[nsxv]
nsx_manager = $NSX_EDGE_GEN_NSX_MANAGER_ADDRESS
nsx_username = $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_USER
nsx_password = $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_PASSWD

[vcenter]
vcenter = $VCENTER_HOST
vcenter_user = $VCENTER_USR
vcenter_passwd = $VCENTER_PWD

[defaults]
transport_zone = $NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE
datacenter_name = $VCENTER_DATA_CENTER
edge_datastore =  $NSX_EDGE_GEN_EDGE_DATASTORE
edge_cluster = $NSX_EDGE_GEN_EDGE_CLUSTER
EOF

pynsxv_local() {
  /opt/pynsxv/cli.py "$@"
}

get_cidr() {
  IP=$1
  MASK=$2
  FIRST_THREE=$(echo $IP|cut -d. -f 1,2,3)
  echo "$FIRST_THREE.0/$MASK"
}

# Create an edge

pynsxv_local esg create \
  --esg_name "$NSX_EDGE_GEN_NAME" \
  --esg_password "$ESG_CLI_PASSWORD_1" \
  --portgroup "$ESG_UPLINK_PG" \
  --esg_remote_access True

# Add Cert

echo "$ERT_SSL_CERT" > cert.crt
echo "$ERT_SSL_PRIVATE_KEY" > cert_pkcs8.key

# Python doesn't output PKCS5 keys, but NSX requires it. Dumb hack to get around this

openssl rsa -in cert_pkcs8.key -out cert.key


pynsxv_local cert create_self_signed \
  --scope_id $NSX_EDGE_GEN_NAME \
  --cert cert.crt \
  --private_key cert.key

# Connect the edge to a backbone

pynsxv_local esg cfg_interface \
  --esg_name $NSX_EDGE_GEN_NAME \
  --portgroup $ESG_UPLINK_PG \
  --vnic_index 0 \
  --vnic_type uplink \
  --vnic_name "Uplink" \
  --vnic_ip $ESG_UPLINK_IP \
  --vnic_mask $ESG_UPLINK_MASK

# Connect the internal interfaces

pynsxv_local esg cfg_interface \
  --esg_name $NSX_EDGE_GEN_NAME \
  --portgroup $ESG_INTERNAL_PG_1 \
  --vnic_index 1 \
  --vnic_type uplink \
  --vnic_name "vnic1" \
  --vnic_ip $ESG_INTERNAL_IP_1 \
  --vnic_mask $ESG_INTERNAL_MASK_1

pynsxv_local esg cfg_interface \
  --esg_name $NSX_EDGE_GEN_NAME \
  --portgroup $ESG_INTERNAL_PG_2 \
  --vnic_index 2 \
  --vnic_type uplink \
  --vnic_name "vnic2" \
  --vnic_ip $ESG_INTERNAL_IP_2 \
  --vnic_mask $ESG_INTERNAL_MASK_2

# Configure ospf

pynsxv_local esg routing_ospf \
  --esg_name $NSX_EDGE_GEN_NAME \
  --vnic_ip $ESG_UPLINK_IP \
  -area $ESG_OSPF_AREA \
  -auth_type md5 \
  -auth_value $ESG_OSPF_PASSWORD

# configure default gateway and static routes

pynsxv_local esg set_dgw \
  --esg_name $NSX_EDGE_GEN_NAME \
  --next_hop $ESG_DEFAULT_GATEWAY

IFS=',' read -ra ROUTES <<<"$T0_STATIC_ROUTES"
unset $IFS
for i in "${ROUTES[@]}"; do
  pynsxv_local esg add_route \
    --esg_name $NSX_EDGE_GEN_NAME \
    --route_net $i \
    --next_hop $T0_ROUTER_IP
done

pynsxv_local esg create_ipset \
  --esg_name $NSX_EDGE_GEN_NAME \
  --ipset_name "Slot-$HAAS_SLOT-Networks" \
  --ipset_value $HAAS_SLOT_NETWORKS

pynsxv_local esg set_fw_status \
  --esg_name $NSX_EDGE_GEN_NAME \
  --fw deny

pynsxv_local esg create_fw_rule \
  --esg_name $NSX_EDGE_GEN_NAME \
  --rule_src any \
  --rule_dst "Slot-$HAAS_SLOT-Networks" \
  --rule_app any \
  --rule_action 'accept' \
  --rule_description 'Allow Inbound Access'

pynsxv_local esg create_fw_rule \
  --esg_name $NSX_EDGE_GEN_NAME \
  --rule_src "Slot-$HAAS_SLOT-Networks" \
  --rule_dst "Slot-$HAAS_SLOT-Networks" \
  --rule_app any \
  --rule_action 'accept' \
  --rule_description 'Allow intra firewall access'

pynsxv_local esg create_fw_rule \
  --esg_name $NSX_EDGE_GEN_NAME \
  --rule_src "Slot-$HAAS_SLOT-Networks" \
  --rule_dst g-Pivotal-Internal-Networks \
  --rule_app any \
  --rule_action 'deny' \
  --rule_description 'No internal access'

pynsxv_local esg create_fw_rule \
  --esg_name $NSX_EDGE_GEN_NAME \
  --rule_src "Slot-$HAAS_SLOT-Networks" \
  --rule_dst any --rule_app any \
  --rule_action 'accept' \
  --rule_description 'Allow outbound Access'

# enable Load Balancer
pynsxv_local lb --esg_name $NSX_EDGE_GEN_NAME  enable_lb

# add LB IP to the interface
pynsxv_local esg cfg_interface \
  --esg_name $NSX_EDGE_GEN_NAME \
  --portgroup $ESG_INTERNAL_PG_1 \
  --vnic_index 1 \
  --vnic_type uplink \
  --vnic_name "vnic1" \
  --vnic_ip $ESG_INTERNAL_IP_1 \
  --vnic_mask $ESG_INTERNAL_MASK_1 \
  --vnic_secondary_ip $ESG_INTERNAL_LB_IP_1

# create Application Profiles
pynsxv_local lb add_profile \
  --esg_name $NSX_EDGE_GEN_NAME \
  --profile_name URL-Switching-HTTP --protocol HTTP

pynsxv_local lb add_profile \
  --esg_name $NSX_EDGE_GEN_NAME \
  --profile_name URL-Switching-HTTPS \
  --protocol HTTPS --xforwardedfor true \
  --cert_name opsmgr.haas-$HAAS_SLOT.pez.pivotal.io \
  --pool_side_ssl true

# create pools with members

pynsxv_local lb add_pool \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name OpsManager-HTTP-Pool \
  --monitor default_http_monitor

pynsxv_local lb add_member \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name OpsManager-HTTP-Pool \
  --member_name OpsManager \
  --member $OM01_NAT_IP \
  --port 80 \
  --monitor_port 80

pynsxv_local lb add_pool \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name OpsManager-HTTPS-Pool \
  --monitor default_https_monitor

pynsxv_local lb add_member \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name OpsManager-HTTPS-Pool \
  --member_name OpsManager \
  --member $OM01_NAT_IP \
  --port 443 \
  --monitor_port 443

pynsxv_local lb add_pool \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name PAS-GoRouterVIP-HTTP-Pool \
  --monitor default_tcp_monitor

pynsxv_local lb add_member \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name PAS-GoRouterVIP-HTTP-Pool \
  --member_name PAS-GoRouterVIP \
  --member $PAS_GOROUTER_VIP_NAT_IP \
  --port 80 \
  --monitor_port 80

pynsxv_local lb add_pool \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name PAS-GoRouterVIP-HTTPS-Pool \
  --monitor default_tcp_monitor

pynsxv_local lb add_member \
  --esg_name $NSX_EDGE_GEN_NAME \
  --pool_name PAS-GoRouterVIP-HTTPS-Pool \
  --member_name PAS-GoRouterVIP \
  --member $PAS_GOROUTER_VIP_NAT_IP \
  --port 443 \
  --monitor_port 443

# Create Virtual Servers
pynsxv_local lb add_vip \
  --esg_name $NSX_EDGE_GEN_NAME \
  --vip_name VS-URL-Switching-HTTP \
  --pool_name PAS-GoRouterVIP-HTTP-Pool \
  --profile_name URL-Switching-HTTP \
  --vip_ip $ESG_INTERNAL_LB_IP_1 \
  --port 80 \
  --protocol HTTP

pynsxv_local lb add_vip \
  --esg_name $NSX_EDGE_GEN_NAME \
  --vip_name VS-URL-Switching-HTTPS \
  --pool_name PAS-GoRouterVIP-HTTPS-Pool \
  --profile_name URL-Switching-HTTPS \
  --vip_ip $ESG_INTERNAL_LB_IP_1 \
  --port 443 \
  --protocol HTTPS

## creating rules doesn't work because somehow the \r\n are not intrepreted, so it's hardcoded in the docker image for now.

# Create Application Rules
#pynsxv_local lb add_rule \
#  --esg_name $NSX_EDGE_GEN_NAME \
#  --rule_name URL-Switching-HTTP \
#  --rule_script "acl OM hdr_beg(host) -i opsmgr \r\n use_backend OpsManager-HTTP-Pool if OM"

#pynsxv_local lb add_rule \
#  --esg_name $NSX_EDGE_GEN_NAME \
#  --rule_name URL-Switching-HTTPS \
#  --rule_script 'acl OM hdr_beg(host) -i opsmgr \r\n use_backend OpsManager-HTTPS-Pool if OM'

# doesn't matter the rule name. It's hardcoded.
pynsxv_local lb add_rule \
  --esg_name $NSX_EDGE_GEN_NAME \
  --rule_name Whatever \
  --rule_script 'whatever'

# add rules to virtual servers

pynsxv_local lb add_rule_to_vip \
  --esg_name $NSX_EDGE_GEN_NAME \
  --vip_name VS-URL-Switching-HTTP \
  --rule_name URL-Switching-HTTP

pynsxv_local lb add_rule_to_vip \
  --esg_name $NSX_EDGE_GEN_NAME \
  --vip_name VS-URL-Switching-HTTPS \
  --rule_name URL-Switching-HTTPS

# NAT rule $ESG_INTERNAL_LB_IP_1 is also used for PAT

# ssh to OM01
pynsxv_local nat add_nat \
  --esg_name $NSX_EDGE_GEN_NAME \
  --nat_type dnat \
  --original_ip $ESG_INTERNAL_LB_IP_1 \
  --translated_ip $OM01_NAT_IP \
  --original_port 22 \
  --translated_port 22 \
  --nat_vnic=0 \
  --protocol=tcp \
  --description='SSH to OM01'

# Diego SSH
pynsxv_local nat add_nat \
  --esg_name $NSX_EDGE_GEN_NAME \
  --nat_type dnat \
  --original_ip $ESG_INTERNAL_LB_IP_1 \
  --translated_ip $PAS_SSHPROXY_VIP_NAT_IP \
  --original_port 2222 \
  --translated_port 2222 \
  --nat_vnic=0 \
  --protocol=tcp \
  --description='Diego SSH'


# TCP Router
pynsxv_local nat add_nat \
  --esg_name $NSX_EDGE_GEN_NAME \
  --nat_type dnat \
  --original_ip $ESG_INTERNAL_LB_IP_1 \
  --translated_ip $PAS_TCPROUTER_VIP_NAT_IP \
  --original_port 10000-10050 \
  --translated_port 10000-10050 \
  --nat_vnic=0 \
  --protocol=tcp \
  --description='TCP Routing'


# Jumpbox
pynsxv_local nat add_nat \
  --esg_name $NSX_EDGE_GEN_NAME \
  --nat_type dnat \
  --original_ip $ESG_INTERNAL_LB_IP_1 \
  --translated_ip $JUMPBOX_IP \
  --original_port 3389 \
  --translated_port 3389 \
  --nat_vnic=1 \
  --protocol=tcp \
  --description='Jumpbox'
