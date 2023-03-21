#!/bin/sh

#bash <(curl -s "https://raw.githubusercontent.com/nguyendkn/3proxy/main/install.sh")
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
# Function to generate a random 64-bit IPv6 address using an existing IPv6 prefix
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install 3proxy
install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/nguyendkn/3proxy/raw/main/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Function to generate 3proxy configuration file without authentication
gen_3proxy_no_auth() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth none
allow *

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate data.txt containing IPs and ports
gen_data_no_auth() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables rules for each proxy port
gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Function to generate ifconfig commands to add IPv6 addresses
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

echo "installing apps"
yum -y install gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data_no_auth >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh

chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

# Update the 3proxy configuration with the generated data
gen_3proxy_no_auth >/usr/local/etc/3proxy/3proxy.cfg

# Add commands to /etc/rc.local to run on system startup
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

# Run the commands in /etc/rc.local
bash /etc/rc.local

echo "IPv6 proxies without authentication have been generated and are ready to use."
