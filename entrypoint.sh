#!/bin/bash

MY_IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $7}')

setup_networking() {
    echo "Setting up static PAT to access VMs"
    for i in $(seq 0 9); do
        iptables -t nat -A PREROUTING -p tcp --dport $(expr $i + 1022) -j DNAT --to-destination 192.168.122.$(expr $i + 100):22
    done
    iptables -I FORWARD 1 -j ACCEPT
}

start_service() {
    local SERVICE=$1
    eval "service ${SERVICE} restart"
    sleep 0.5
    eval "service ${SERVICE} status"
    RC=$?
    if [ $RC -gt 0 ]; then
        echo -ne "Failed to start ${SERVICE}"
        exit 1
    fi
    echo -ne "\nService ${SERVICE} started...\n"
    return ${RC}
}

setup_ssh() {
    start_service "ssh"
    chown oneadmin:root /var/lib/one/.ssh/id_rsa
    chown oneadmin:root /var/lib/one/.ssh/id_rsa.pub
    cat /var/lib/one/.ssh/id_rsa.pub > /var/lib/one/.ssh/authorized_keys 
    ssh-keyscan $(hostname) > /var/lib/one/.ssh/known_hosts
}


setup_ssh

start_service "virtlogd"
start_service "libvirt-bin"
start_service "opennebula"
start_service "opennebula-sunstone"

setup_networking

echo "All OpenNebula services have started. Web UI is at http://${MY_IP}:9869"
echo "VMs will be accessible at ${MY_IP}:1022, ${MY_IP}:1023, etc."
echo "For example 'ssh -i id_rsa -p 1022 root@${MY_IP}' will log into the VM with the first allocatable IP"
echo "Attempting to bootstrap the cluster"

add_localhost_node() {
    echo "Attempting to add localhost as a node"
    addcmd="onehost create $(hostname) -i kvm -v kvm"
    checkcmd="onehost show $(hostname) -x | xml_grep STATE --text_only"
    local delcmd="onehost delete $(hostname)"
    local upstate=2
    local mystate=0
    local errstate=3
    local wait=30
    
    echo "Checking if local node already exists"
    onehost show $(hostname)
    if [[ $? -eq 0 ]]; then
        echo -ne "\nLocal node already added\n"
        return 0
    fi

    i=1
    echo "Adding localhost node"
    eval "${addcmd}"
    while [[ $i -le $wait && $mystate -ne $upstate ]]; do
        mystate=$(eval "${checkcmd}")
        if [[ $mystate -eq $errstate ]]; then
            eval "${delcmd}"
            echo -ne "waiting $i "        
            sleep 1
            eval "${addcmd}"
        elif [[ $mystate -ne $upstate ]]; then
            echo -ne "waiting $i "        
            sleep 1
        fi
        i=$(($i + 1))
    done

    if [[ ${mystate} -eq ${upstate} ]]; then
        echo -ne "\nAdded localhost node\n"
    else
        echo -ne "\nFailed to add localhost node\n"
        echo -ne "\nRetry later with command \"${addcmd}\"\n"
    fi
}

add_ssh_keys_to_oneadmin() {
    echo -ne "\nAdding ssh keys to oneadmin user"
    local TMP_FILE=$(mktemp) || return 1
    local checkcmd="oneuser show 0 -x | xml_grep SSH_PUBLIC_KEY --text_only"
    ONEADMIN_OS_USER_KEY=$(cat /var/lib/one/.ssh/id*pub 2>/dev/null)

    existing=$(eval "${checkcmd}")
    if [[ existing == ONEADMIN_OS_USER_KEY ]]; then
        echo "SSH key already added"
        return 0
    fi

    cat > "${TMP_FILE}"<< EOF
SSH_PUBLIC_KEY="${ONEADMIN_OS_USER_KEY}"
EOF

    oneuser update 0 "${TMP_FILE}" || return 1
    rm "${TMP_FILE}"
}


create_default_network() {
    echo "Creating default network"
    local checkcmd="onevnet show net-default"
    local TMP_FILE=$(mktemp) || return 1

    echo "Checking if default network already exists"
    eval "${checkcmd}"
    exists=$?
    if [[ $exists -eq 0 ]]; then
        echo "Default network already exists"
        return 0
    fi

    cat > "${TMP_FILE}"<< EOF
NAME            = "net-default"
VN_MAD          = "dummy"
BRIDGE          = "virbr0"
NETWORK_ADDRESS = "192.168.122.0"
NETWORK_MASK    = "255.255.255.0"
DNS             = "1.1.1.1"
GATEWAY         = "192.168.122.1"
AR=[TYPE = "IP4", IP = "192.168.122.100", SIZE = "100" ]
EOF

    onevnet create "${TMP_FILE}" || return 1
    rm "${TMP_FILE}"
}

create_debian_template() {
    echo "Creating Debian 9 - KVM template"
    local checkcmd="onetemplate show debian9"
    local addcmd="onemarketapp export \"Debian 9 - KVM\" debian9 --datastore default"
    local TMP_FILE=$(mktemp) || return 1

    echo "Checking if template already exists"
    eval "${checkcmd}"
    exists=$?
    if [[ $exists -eq 0 ]]; then
        echo "Debian9 template already exists"
        return 0
    fi

    eval "${addcmd}"
    
    cat > "${TMP_FILE}"<< EOF
NIC=[
  NETWORK="net-default",
  NETWORK_UNAME="oneadmin",
  SECURITY_GROUPS="0" ]
EOF

    onetemplate update 0 -a "${TMP_FILE}" >/dev/null
    rm "${TMP_FILE}"
    echo "Template updated"
}

add_localhost_node
add_ssh_keys_to_oneadmin
create_default_network
create_debian_template


# Sleep and wait for the kill
echo "Entering sleeping loop..."
trap : TERM INT; sleep infinity & wait