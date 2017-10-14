#!/bin/bash
#
# Thanks to the work by gfjardim for providing the format for this docker.
# https://github.com/gfjardim/
#
# Thanks to the work of Scott-St for providing the container this one was modified from.
# https://github.com/Scott-St/lftp
#
# Created Oct 4, 2015
# Modified Oct 14, 2017
#
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

# Install Required Programs
apt-get update -qq
apt-get install -qy -f lftp

# Startup Script
cat <<'EOT' > /etc/my_init.d/config.sh
#!/bin/bash

# Find FTP_PORT, FTP_USER, FTP_PASSWORD, FTP_HOST, FTP_REMOTE_DIR in the control script and replace it with the environment variable

# If the port environment variable is not set assume port 990
if [[ -z $FTP_PORT ]]; then
  FTP_PORT=990
fi

# If the Remote Host Directory environment variable is not set assume /
if [[ -z $FTP_REMOTE_DIR ]]; then
  FTP_REMOTE_DIR="/."
fi

# Replace variables in the control script
sed -i -e "s#FTP_PORT#${FTP_PORT}#" /etc/lftp/syncControl.sh
sed -i -e "s#FTP_USER#${FTP_USER}#" /etc/lftp/syncControl.sh
sed -i -e "s#FTP_PASSWORD#${FTP_PASSWORD}#" /etc/lftp/syncControl.sh
sed -i -e "s#FTP_HOST#${FTP_HOST}#" /etc/lftp/syncControl.sh
sed -i -e "s#FTP_REMOTE_DIR#${FTP_REMOTE_DIR}#" /etc/lftp/syncControl.sh

# If no cron time is specified use daily at 1AM
if [[ -z $FTP_CRON_JOB ]]; then
  $FTP_CRON_JOB="0 1 * * *"
fi

if [ ! -d "/mnt/lftp" ]; then
  mkdir -p /mnt/lftp
fi

# Copy the ftp script to the unraid mounted folder
# Check if the FTP script file exists in the mounted directory.  Only copy it if it does not exist.
if [ ! -f "/mnt/lftp/syncftp.sh" ]; then
  cp /etc/lftp/syncftp.sh /mnt/lftp/syncftp.sh
fi

# Make sure the script is writable by all.  In case you want to modify it.
chmod 777 /mnt/lftp/syncftp.sh

# Make sure the script is executable
chmod +x /etc/lftp/syncControl.sh

# Add a cron to run the script, if it doesn't already exist
FTP_CRON_JOB+=" /etc/lftp/syncControl.sh >> /mnt/lftp/syncftp.log 2>&1"
crontab  -l | grep -q 'syncControl' && echo 'job exists' || { cat; echo "$FTP_CRON_JOB"; } | crontab -

# Remove lftp lock file if it exists
if [ -f "/mnt/lftp/lftp.lock" ]; then
  rm /mnt/lftp/lftp.lock
fi
EOT

mkdir -p /etc/lftp

# Create Sync Control Script
cat <<'EOT' > /etc/lftp/syncControl.sh
#!/bin/bash
login=FTP_USER
pass=FTP_PASSWORD
host=FTP_HOST
port=FTP_PORT
remote_dir=FTP_REMOTE_DIR
  
source /mnt/lftp/syncftp.sh
EOT


# Create Sync FTP Script
cat <<'EOT' > /etc/lftp/syncftp.sh
#!/bin/bash
#
# Variables are stored in /etc/lftp/syncControl.sh
# They are written from the docker into this file.
# The variables are: 
# login=FTP_USER
# pass=FTP_PASSWORD
# host=FTP_HOST
# port=FTP_PORT
# remote_dir=FTP_REMOTE_DIR
#
# This script is called from /etc/lftp/syncControl.sh
#
# This script will enter the FTP, mirror the completed directory to the locally mounted directory (unraid server mnt/cache/downloads share by default)
#
# This source version was set to handle extracting and clean up.
# I prefer to not download most of the junk to start with so I ignored it from downloading at all.
# Files like .png, .jpg, .jpeg, .nfo, .gif, .srt, .txt, sample, subs and proof are ignored.
#
# I also prefer to handle file extractions and clean up as part of another process.
# This file is saved to /mnt/lftp/syncftp.sh on inital run, feel free to make changes

# Define a timestamp function
timestamp() {
  date +"%Y-%m-%d_%H-%M-%S"
}

local_dir="/mnt/downloads"

lock_file="/mnt/lftp/lftp.lock"
trap "rm -f $lock_file" SIGINT SIGTERM

if [[ -e "$lock_file" ]]
then
	echo "$(timestamp): lftp is already running."
	exit 0
fi

touch "$lock_file"
echo "$(timestamp): lftp is now running."

args="-v -c -L --no-empty-dirs --Remove-source-files --loop -x '(\.png|\.jpg|\.nfo|\.jpeg|\.gif|\.srt|\.txt|[Ss][Aa][Mm][Pp][Ll][Ee]|[Ss][Uu][Bb][Ss]|[Pp][Rr][Oo][Ff][Ff])'"

# Optional - The number of parallel files to download. It is set to download 5 file at a time.
parallel="5"
# Optional - set maximum number of connections lftp can open
default_pget="5"
# Optional - Set the number of connections per file lftp can open
pget_mirror="5"

# 10485760 = 10 
# 20485760 = 20
# 104857600 = 100
lftp -p "$port" -u "$login,$pass" "sftp://$host" <<-EOF
  set ftp:ssl-auth TLS
  set ftp:ssl-force true
  set ftp:ssl-protect-list yes
  set ftp:ssl-protect-data yes
  set ssl:verify-certificate off
  set mirror:parallel-transfer-count "$parallel"
  set pget:default-n $default_pget
  set mirror:use-pget-n $pget_mirror
  set net:limit-total-rate 104857600:0 
  set xfer:log-file "/mnt/lftp/xfer.log"
  mirror $args "$remote_dir" "$local_dir"
  quit 0
EOF

#start working in the mounted directory
cd $local_dir
#look for which folders exist.
for folder in */
#only try the following if there is a directory
do 
  if [ -d "$folder" ]; then
    #echo $folder
    chmod -R 777 "$folder"
  fi
done

rm -f "$lock_file"
echo "$(timestamp): lftp is now exiting."
exit 0
EOT

chmod -R +x /etc/service/ /etc/my_init.d/

#########################################
##                 CLEANUP             ##
#########################################

# Clean APT install files
apt-get clean -y
rm -rf /var/lib/apt/lists/* /var/cache/* /var/tmp/*
