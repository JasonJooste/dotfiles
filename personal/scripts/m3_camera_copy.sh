#! /usr/bin/bash
set -e
# Recursive (needed for nested dirs), no overwrites, dump directory
read -p "Server IP address: " ip_addr
# Trim spaces
ip_addr=$(echo "$ip_addr" | xargs)
wget -q -r -nc -nd -A "*jpg" -P ~/Pictures/Camera ftp://$ip_addr:9999/DCIM/Camera
echo "Copied photos"
wget -q -r -nc -nd -A "*mp4" -P ~/Videos/Camera ftp://$ip_addr:9999/DCIM/Camera
echo "Copied videos"
wget -q -r -nc -nd -P ~/Documents/diary/audio ftp://$ip_addr:9999/Recordings
echo "Copied Audio"
