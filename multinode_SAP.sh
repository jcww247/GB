#!/bin/bash

BASE="/home/sap"
PORT=12455
# Execute options
ARGS=$(getopt -o "hp:n:c:r:wsudx" -l "help,count:,net" -n "multinode_SAP.sh" -- "$@");

net=4
count=1
eval set -- "$ARGS";

while true; do
    case "$1" in
        -n|--net)
            shift;
                    if [ -n "$1" ];
                    then
                        net="$1";
                        shift;
                    fi
            ;;
        -c|--count)
            shift;
                    if [ -n "$1" ];
                    then
                        count="$1";
                        shift;
                    fi
            ;;
        --)
            shift;
            break;
            ;;
    esac
done
	
#######################-------------------------------------------------------------------------IP TESTING	

# break here of net isn't 4 or 6
if [ ${net} -ne 4 ] && [ ${net} -ne 6 ]; then
    echo "invalid NETWORK setting, can only be 4 or 6!"
    exit 1;
fi
	
if [ ${net} = 4 ]; then
	IPADDRESS=$(ip addr | grep 'inet ' | grep -Ev 'inet 127|inet 192\.168|inet 10\.' | sed "s/[[:space:]]*inet \([0-9.]*\)\/.*/\1/")
fi
	
if [ ${net} = 6 ]; then
	IPADDRESS=$(ip -6 addr show dev eth0 | grep inet6 | awk -F '[ \t]+|/' '{print $3}' | grep -v ^fe80 | grep -v ^::1 | cut -f1-4 -d':' | head -1)
fi
#######################-------------------------------------------------------------------------END IP TESTING

# currently only for Ubuntu 16.04 & 18.04
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID}" != "16.04" ]] && [[ "${VERSION_ID}" != "18.04" ]] ; then
            echo "This script only supports Ubuntu 16.04 & 18.04 LTS, exiting."
            exit 1
        fi
    else
        # no, thats not ok!
        echo "This script only supports Ubuntu 16.04 & 18.04 LTS, exiting."
        exit 1
    fi
	

#install Deps

	sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
	sudo apt-get -y upgrade
	sudo apt-get -y dist-upgrade
	sudo apt-get -y autoremove
	sudo apt-get -y install wget nano htop jq git curl
	sudo apt-get -y install libzmq3-dev libzmq5
	sudo apt-get -y install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev lshw
	sudo apt-get -y install libevent-dev libbz2-dev libicu-dev python-dev g++
	sudo apt -y install software-properties-common
	sudo add-apt-repository ppa:bitcoin/bitcoin -y
	sudo apt-get -y update
	sudo apt-get -y install libdb4.8-dev libdb4.8++-dev bsdmainutils libgmp3-dev ufw pkg-config autotools-dev redis-server npm nodejs nodejs-legacy
	sudo apt-get -y install libminiupnpc-dev
	sudo apt-get -y install fail2ban
	sudo service fail2ban restart
	sudo apt-get install -y libdb5.3++-dev libdb++-dev libdb5.3-dev libdb-dev && ldconfig
	sudo apt-get install -y unzip libzmq3-dev build-essential libtool autoconf automake libboost-dev libssl-dev libboost-all-dev libqrencode-dev libminiupnpc-dev libboost-system1.58.0 libboost1.58-all-dev libdb4.8++ libdb4.8 libdb4.8-dev libdb4.8++-dev libevent-pthreads-2.0-5
	sudo apt-get update

#Create 5GB swap file
if grep -q "SwapTotal" /proc/meminfo; then
    echo -e "${GREEN}Skipping disk swap configuration...${NC} \n"
else
    echo -e "${YELLOW}Creating 5GB disk swap file. \nThis may take a few minutes!${NC} \a"
    touch /var/swap.img
    chmod 600 swap.img
    dd if=/dev/zero of=/var/swap.img bs=1024k count=5000
    mkswap /var/swap.img 2> /dev/null
    swapon /var/swap.img 2> /dev/null
    if [ $? -eq 0 ]; then
        echo '/var/swap.img none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap was created successfully!${NC} \n"
    else
        echo -e "${YELLOW}Operation not permitted! Optional swap was not created.${NC} \a"
        rm /var/swap.img
    fi
fi

echo -e "Installing and setting up firewall to allow ingress on port 8120"
  ufw allow 12455/tcp comment "GoBYTE MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1

#Download Latest
echo 'Downloading latest version:  wget https://github.com/gobytecoin/gobyte/releases/download/v0.12.2.4/GoByteCore-0.12.2.4_Linux64.tar.gz' &&  wget https://github.com/gobytecoin/gobyte/releases/download/v0.12.2.4/GoByteCore-0.12.2.4_Linux64.tar.gz
			
#Install Latest
echo '==========================================================================='
echo 'Extract new methuselah: \n# tar -xzf GoByteCore-0.12.2.4_Linux64/usr/local/bin.tar.gz -C /usr/local/bin' && tar -xzf GoByteCore-0.12.2.4_Linux64/usr/local/bin.tar.gz -C /usr/local/bin

rm tar -xzf GoByteCore-0.12.2.4_Linux64.tar.gz

# our new mnode unpriv user acc is added
if id "sap" >/dev/null 2>&1; then
    echo "user exists already, do nothing" 
else
    echo "Adding new system user sap"
    adduser --disabled-password --gecos "" sap
fi

netDisable=$(lshw -c network | grep -c 'network DISABLED')
venet0=$(cat /etc/network/interfaces | grep -c venet)

if [ $netDisable -ge 1 ]; then
	if [ $venet0 -ge 1 ]; 
	then
		dev2=venet0
	else
		echo 'Cannot use this script at this time'
		exit 1
	fi
else
	dev2=$(lshw -c network | grep logical | cut -d':' -f2 | cut -d' ' -f2)
fi

# individual data dirs for now to avoid problems
echo "* Creating masternode directories"
mkdir -p "$BASE"/multinode
for NUM in $(seq 1 ${count}); do
    if [ ! -d "$BASE"/multinode/SAP_"${NUM}" ]; then
        echo "creating data directory $BASE/multinode/SAP_${NUM}" 
        mkdir -p "$BASE"/multinode/SAP_"${NUM}" 
		#Generating Random Password for GoBYTE JSON RPC
		USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
		USERPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
		read -e -p "MasterNode Key for SAP_"${NUM}": " MKey
		echo "rpcallowip=127.0.0.1
rpcuser=$USER
rpcpassword=$USERPASS
server=1
daemon=1
listen=1
maxconnections=256
masternode=1
masternodeprivkey=$MKey
promode=1
addnode=45.32.101.119
addnode=206.189.159.65
addnode=149.28.29.18
addnode=31.211.71.205
addnode=45.76.38.25
addnode=146.185.163.186	
addnode=149.28.122.56
addnode=103.72.162.239
addnode=45.77.232.81
addnode=142.93.96.234
addnode=139.180.218.25
addnode=208.97.140.229
addnode=142.93.5.22
addnode=199.247.13.3
addnode=95.216.109.196
addnode=45.77.133.160
addnode=212.47.242.142
addnode=172.107.168.70
addnode=45.32.151.3
addnode=80.240.23.227
addnode=206.189.124.160
addnode=87.106.153.89
addnode=95.216.109.193
addnode=142.93.48.76
addnode=159.203.114.76
addnode=142.93.239.148
addnode=75.102.39.145
addnode=80.240.31.18
addnode=75.102.39.110
addnode=174.138.0.251
addnode=209.250.246.136" |sudo tee -a "$BASE"/multinode/SAP_"${NUM}"/gobyte.conf >/dev/null
echo 'bind=192.168.1.'"${NUM}"':'"$PORT" >> "$BASE"/multinode/SAP_"${NUM}"/gobyte.conf
echo 'rpcport=8119'"${NUM}" >> "$BASE"/multinode/SAP_"${NUM}"/gobyte.conf

echo 'ip addr del 192.168.1.'"${NUM}"'/32 dev '"$dev2"':'"${NUM}" >> start_multinode.sh
echo 'ip addr add 192.168.1.'"${NUM}"'/32 dev '"$dev2"':'"${NUM}" >> start_multinode.sh
echo "runuser -l sap -c 'gobyted -daemon -pid=$BASE/multinode/SAP_${NUM}/gobyte.pid -conf=$BASE/multinode/SAP_${NUM}/gobyte.conf -datadir=$BASE/multinode/SAP_${NUM}'" >> start_multinode.sh

echo 'ip addr del 192.168.1.'"${NUM}"'/32 dev '"$dev2"':'"${NUM}" >> stop_multinode.sh
echo "gobyte-cli -conf=$BASE/multinode/SAP_${NUM}/goybte.conf -datadir=$BASE/multinode/SAP_${NUM} stop" >> stop_multinode.sh

echo "echo '====================================================${NUM}========================================================================'" >> mn_status.sh
echo "gobyte-cli -conf=$BASE/multinode/SAP_${NUM}/gobyte.conf -datadir=$BASE/multinode/SAP_${NUM} masternode status" >> mn_status.sh

echo "echo '====================================================${NUM}========================================================================'" >> mn_getinfo.sh
echo "gobyte-cli -conf=$BASE/multinode/SAP_${NUM}/gobyte.conf -datadir=$BASE/multinode/SAP_${NUM} getinfo" >> mn_getinfo.sh
# When Blocks are synched, it copies the wallet into the remaining Mns Wallet automatically
echo "echo 'stop MN${NUM}'"
    echo "gobyte-cli -conf=$BASE/multinode/SAP_${NUM}/gobyte.conf -datadir=$BASE/multinode/SAP_${NUM} stop" >> mn_sync_block.sh
    if (( ${NUM} > 1)) ; then
        echo "echo 'copy MN1 blocks folder into masternode ${NUM}'" >> mn_sync_block.sh
        echo "sudo yes | cp -R $BASE/multinode/SAP_1/blocks/ $BASE/multinode/SAP_${NUM}/blocks" >> mn_sync_block.sh
    fi

fi
done

chmod +x start_multinode.sh
chmod +x stop_multinode.sh
chmod +x mn_status.sh
chmod +x mn_getinfo.sh
cat start_multinode.sh >> /usr/local/bin/start_multinode.sh
cat stop_multinode.sh >> /usr/local/bin/stop_multinode.sh
cat mn_getinfo.sh >> /usr/local/bin/mn_getinfo.sh
cat mn_status.sh >> /usr/local/bin/mn_status.sh
chown -R sap:sap /home/sap/multinode
chmod -R g=u /home/sap/multinode
#command below starts all MNs, so it creates requirements per user. Need to shut it off manually to prevent high cpu
./start_multinode.sh

echo 'run start_multinode.sh to start the multinode'
echo 'run stop_multinode.sh to stop it'
echo 'run mn_getinfo.sh to see the status of all of the nodes'
echo 'run mn_status.sh for masternode debug of all the nodes'
echo "in masternode.conf file use the external IP address as the address ex. MN1 $IPADDRESS:8120 privekey tx_id tx_index"
