#!/bin/bash

#########################################
##        ENVIRONMENTAL CONFIG         ##
#########################################

# Configure user nobody to match unRAID's settings
export DEBIAN_FRONTEND="noninteractive"
usermod -u 99 nobody
usermod -g 100 nobody
usermod -d /home nobody
chown -R nobody:users /home

# Disable some services
rm -rf /etc/service/sshd /etc/service/syslog-ng /etc/my_init.d/00_regen_ssh_host_keys.sh

#########################################
##    REPOSITORIES AND DEPENDENCIES    ##
#########################################

# Repositories
add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ trusty universe multiverse"
add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ trusty-updates universe multiverse"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu/ trusty-proposed restricted main multiverse universe"
# Install Dependencies
apt-get update -qq
apt-get install -qy -f lftp \
                      unrar

# Sync FTP Script
mkdir -p /etc/lftp

cat <<'EOT' > /etc/lftp/syncftp.sh
#!/bin/bash
# This script will enter the FTP, mirror the completed directory to the locally mounted directory (unraid server mnt/cache/downloads share by default)
# After downloading from the FTP it will remove the FTP files
# It will then extract and RAR files that are CONTAINED in the root folder but not a subfolder of the folder. ie. it will not extract SUBS
# It will then delete the RAR files
# This script is designed to work with Scene Release file structures

login=$FTP_USER
pass=$FTP_PASSWORD
host=$FTP_HOST
port=$FTP_PORT
remote_dir=/home/rtorrentuser/complete/.
local_dir="/var/downloads"

EOT

#########################################
##                 CLEANUP             ##
#########################################

# Clean APT install files
apt-get clean -y
rm -rf /var/lib/apt/lists/* /var/cache/* /var/tmp/*
