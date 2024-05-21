#!/bin/bash
sudo apt-get  -y update
sudo apt-get install -y  sshpass
sudo apt-get install -y terminator

if ! [ -f ~/.ssh/id_rsa ]; then
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
fi


sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@34.172.154.67

cat <<EOT>> ~/.ssh/config
Host ubt
  HostName 34.172.154.67
  User root
EOT
