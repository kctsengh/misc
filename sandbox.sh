#!/bin/bash
sudo apt-get  -y update
sudo apt-get install -y  sshpass
sudo apt-get install -y terminator
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
#sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@35.236.136.11
#sudo -- sh -c "echo \"35.236.136.11    gcp\" >> /etc/hosts"



sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@35.201.147.166
sudo -- sh -c "echo \"35.201.147.1    k1\" >> /etc/hosts"

sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@35.229.229.157
sudo -- sh -c "echo \"35.229.229.1    k3\" >> /etc/hosts"


sshpass -p  $TOKEN ssh-copy-id -o StrictHostKeyChecking=no root@35.185.170.73
sudo -- sh -c "echo \"35.185.170.73    k4\" >> /etc/hosts"



