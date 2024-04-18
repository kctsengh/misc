#!/bin/bash
sudo apt-get  -y update
sudo apt-get install -y  sshpass
sudo apt-get install -y terminator
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1


sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@35.185.170.73
sudo -- sh -c "echo \"35.185.170.73    k4\" >> /etc/hosts"

cat <<EOT>> ~/.ssh/config

Host k4
  HostName 35.185.170.73
  User root
EOT

