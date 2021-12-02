#!/usr/bin/env bash
#This script does no sanity checking, nor does it account for failures
#in starting the dependency daemons. Use with caution.

HOST_IP="10.148.7.1"
BR_NAME="br_main"
DIR_NAME="${HOME}/.etc/make_me_a_router"
PID_DIR_NAME="${DIR_NAME}/router_pids"
STATE_STORE_DIR="${DIR_NAME}/old_state"

function usage {
    echo "Usage:"
    echo "make_me_a_router.sh <input_nic> <output_nic>"
    echo "For now, output NIC must NOT be WiFi".
}

function take_down_nic {
    local nic=$1
    sudo ip link set down ${nic}
}

function bring_up_nic {
    local nic=$1
    sudo ip link set up ${nic}
}

function set_static_ip {
    local nic=$1
    local ip_str=$2
    sudo ip address ${ip_str} dev ${nic} 
}

function set_static_ip_on_nic {
    local nic=$1
    local ip_str=$2
    take_down_nic ${nic}
    set_static_ip ${nic} ${ip_str}
    bring_up_nic ${nic}
}


#bridge_stuff:

function set_up_bridge {
    #Check if bridge already up:
    local is_up=$(sudo brctl show | awk "\$1~/${BR_NAME}/")
    if [ ${is_up} != ""  ]; then
        take_down_bridge
    fi

    sudo brctl addbr "${BR_NAME}"
    set_static_ip_on_nic "${BR_NAME}" "${HOST_IP}"
}

function take_down_bridge {
    local bridge=$1
    take_down_nic ${bridge}
    sudo brctl delbr ${bridge}
}

function add_nic_to_bridge {
   local nic=$1
   sudo brctl addif "${BR_NAME}" dev "${nic}"
}


#Firewall
function init_firewall {
	#Save the old and busted:
	save_old_firewall

	#Remove the old and busted:
	sudo iptables-flush
        
	#Establish the new hotness:
	cat iptables-template.save | sed "s/<out_nic>/${out_nic}/g" | \
sed 's/<in_nic>/${in_nic}/g' | sudo iptables-restore
}

function save_old_firewall {
   sudo iptables-save > ${STATE_STORE_DIR}/iptables-old.save
}

function restore_old_firewall {
   sudo iptables-flush
   sudo iptables-restore < ${STATE_STORE_DIR}/iptables-old.save
   rm -rfd ${STATE_STORE_DIR}/iptables-old.save
}

function kill_if_alive {
    local file="${PID_DIR_NAME}/${1}"
    #echo "File: ${file}"
    if [ ! -e "${file}" ]; then
        return 0
    fi
    #echo "Made it here"
    local pid="$(head -n1 ${file})"
    local it_lives="$(sudo ps aux | grep ${pid})"
    #echo "it_lives: ${it_lives}"
    if [ "${it_lives}x" != "x" ]; then
	#Kill it with fire:
	#echo "in the killzone"
        sudo kill -9 ${pid}
	rm -rf "${file}"
    fi
}

function store_pid {
    local program_name="$(basename $1)"
    local pid=$2

    echo "$pid" > ${PID_DIR_NAME}/${program_name}.pid
}

#DHCP
function start_dhcp_server {
    kill_if_alive "isc-dhcp-server"
    isc-dhcp-server& #Add arguments
    #get PID
    local pid="${!}"
    #store it.
    store_pid "isc-dhcp-server" "${pid}"
}

#DNS
function start_dns_server {
    kill_if_alive "named"
    named&  #Add arguments
    #get PID
    local pid="${!}"
    #store it.
    store_pid "named" "${pid}"
}

function undo {
    kill_if_alive "isc-dhcp-server"
    kill_if_alive "named"
    restore_old_firewall
}

#Are we being sourced?
#This ONLY works on Bash:
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [ ${sourced} -lt 1 ]; then
    if [ $# -eq 2 ]; then
	out_nic=$1
	in_nic=$2

	set_up_bridge
	add_nic_to_bridge "${in_nic}"
	start_dhcp_server
	start_dns_server
        echo "Your router's ready."
	#echo "To shut it down, run this command again with the \"undo\" argument"
    else
        usage
    fi
else
    echo "We are being sourced"
fi

