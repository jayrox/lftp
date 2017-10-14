#!/bin/bash
#
# Thanks to the work by gfjardim for providing the format for this docker.
# https://github.com/gfjardim/
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
apt-get install -qy -f lftp \
                      unrar

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
rm /mnt/lftp/lftp.lock
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
# After downloading from the FTP it will remove the FTP files
# It will then extract and RAR files that are CONTAINED in the root folder but not a subfolder of the folder. ie. it will not extract SUBS
# It will then delete the RAR files
# This script is designed to work with Scene Release file structures

local_dir="/mnt/downloads"

#lftp connection information.  May need to be modified for specific connection requirements
lftp << EOF
  set net:timeout 30
  set net:max-retries 10
  set net:reconnect-interval-base 5
  set net:reconnect-interval-multiplier 5
  set ftp:ssl-auth TLS
  set ftp:ssl-force true
  set ftp:ssl-protect-list yes
  set ftp:ssl-protect-data yes
  set ssl:verify-certificate off
  set mirror:use-pget-n 5
  open -p $port -u $login,$pass $host
  cd "$remote_dir"
  find . | grep [[:alnum:]] | sed -e 's~.~rmdir" "-f" "\".~' -e 's~$~\"~' | tac > /tmp/delete
  mirror -c -P2 -vvv --no-empty-dirs --Remove-source-files $remote_dir $local_dir
  source /tmp/delete
  quit 0
EOF

#start working in the mounted directory
cd $local_dir
#look for which folders exist.
for folder in */
#only try the following if there is a directory
do 
  if [ -d "$folder" ]; then
    #Enter each folder
    cd "$folder"
    #date
    #Look for the filename ending in .rar
    for filename in *.rar
    do echo "extracting $filename"
      #first do will extract the files from the rar and then delete the .rar file
      find . ! -name . -prune -type d -o -name "*.rar" -print -exec unrar e {} -y -o- \; -exec rm {} \;
  
      #other options to find to extract from (not used now)
      #find . -name "*part01.rar" -exec unrar e {} -y -o- \;
      #find . -name "*part001.rar" -exec unrar e {} -y -o- \;
      #find . -name "*.r00" -exec unrar e {} -y -o- \;
  
      #this do will then delete all the *.r01, *.r02 etc.
      find . ! -name . -prune -type d -o -name "*.r[0-9]*[0-9]" -print -exec rm {} \;
      #I also dont use the SFV files so lets delete them also
      find . ! -name . -prune -type d -o -name "*.sfv" -print -exec rm {} \;
      #find . -name "*.r*" -exec rm {} \;
    done
    #go back up a directory
    cd "..";
    chmod -R 777 "$folder"
  fi
done
exit 0
EOT

chmod -R +x /etc/service/ /etc/my_init.d/

#########################################
##                 CLEANUP             ##
#########################################

# Clean APT install files
apt-get clean -y
rm -rf /var/lib/apt/lists/* /var/cache/* /var/tmp/*
