#!/bin/bash

#-------------------------------------------------------------------------------
# update_gentoo_64.sh
#-------------------------------------------------------------------------------
# Copyright 2012 Dowd and Associates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#-------------------------------------------------------------------------------

# The region to install into
#region="us-east-1"
region=$1

# The security group to use. 22/tcp needs to be open
# Leave empty to have a group created
#group="default"
group=$2

# The ec2 key pair to use
# Leave empty to have a key created
#key="example"
key=$3

# The fully qualified path to private key of the ec2 key pair
# Leave empty to have a key created
#keyfile="$HOME/.ssh/example.pem"
keyfile=$4

#-----

building="Gentoo 64 EBS"
start_time=`date +%Y-%m-%dT%H:%M:%S`

architecture="x86_64"
instance_type="c1.medium"

if [[ $region == "" ]]; then
    region="us-east-1"
fi

if [[ $group == "" ]]; then
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: set up group"
    group="gentoo-bootstrap_64-bit"

    group_exists=`ec2-describe-group \
            --region $region \
            --filter group-name=$group \
            | wc -c`

    if [ $group_exists -eq 0 ]; then
        ec2-create-group --region $region $group --description "Gentoo Bootstrap 64-bit"
    fi

    ec2-authorize --region $region $group -P tcp -p 22 -s 0.0.0.0/0

    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: group set up"
fi

if [[ $key == "" || $keyfile == "" ]]; then
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: set up key"
    key="gentoo-bootstrap_64-bit_$region"
    keyfile="gentoo-bootstrap_64-bit_$region.pem"
   
    if [ ! -f $keyfile ]; then
        ec2-add-keypair --region $region $key | sed 1d > $keyfile
    fi

    chmod 600 $keyfile
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: key set up"
fi

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: region = $region"
echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: group = $group"
echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: key = $key"
echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: keyfile = $keyfile"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: finding latest gentoo image"

boot_image=`ec2-describe-images \
--region $region \
--owner self \
--filter architecture=$architecture \
--filter image-type=machine \
--filter root-device-type=ebs \
--filter virtualization-type=paravirtual \
--filter manifest-location=902460189751/Gentoo_* \
--filter is-public=true \
| grep "^IMAGE" \
|  awk '{ print $3 " " $2 }' \
| sort \
| tail -n 1 \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: gentoo image = $boot_image"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: starting gentoo instance"

instance=`ec2-run-instances \
--region $region \
$boot_image \
--group $group \
--key $key \
--instance-type $instance_type \
| grep "^INSTANCE" \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: bootstrap instance = $instance"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: start checking if instance is running"
running_check=0
while [ $running_check -eq 0 ]; do
    sleep 10
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if instance is running (10 second check)"
    let running_check=`ec2-describe-instances \
            --region $region \
            $instance \
            --filter instance-state-name=running \
            | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: instance is running"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: getting hostname"

server=`ec2-describe-instances \
--region $region \
$instance \
--filter instance-state-name=running \
| grep "^INSTANCE" \
| awk '{ print $4 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: hostname = $server"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: Wait 60 seconds, just in case, for server to finish coming up"

sleep 60

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: copying files to remote server"

scp -o StrictHostKeyChecking=no -i $keyfile ${architecture}/* ${architecture}/.* ec2-user@$server:/tmp

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: setting update_gentoo.sh as executable on remote server"

ssh -o StrictHostKeyChecking=no -i $keyfile ec2-user@$server "chmod 755 /tmp/update_gentoo.sh"
ssh -o StrictHostKeyChecking=no -i $keyfile -t ec2-user@$server "sudo /tmp/update_gentoo.sh"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if update is done"

stopped_check=0
while [ $stopped_check -eq 0 ]; do
    sleep 60
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if update is done (1 minute check)"
    let stopped_check=`ec2-describe-instances \
            --region $region \
            $instance \
            --filter instance-state-name=stopped \
            | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: update is done"

name="Gentoo_64-bit-EBS-`date +%Y-%m-%d-%H-%M-%S`"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: creating image"

gentoo_image=`ec2-create-image \
--region $region \
--name $name \
--description "Gentoo 64-bit EBS" \
$instance \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if image is done"

completed_check=0
while [ $completed_check -eq 0 ]; do
    sleep 60
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if image is done (1 minute check)"
    let completed_check=`ec2-describe-images \
        --region $region \
        $gentoo_image \
        --filter state=available \
        | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: image is done"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: image-id = $gentoo_image"

gentoo_instance=`ec2-run-instances \
--region $region \
$gentoo_image \
--group $group \
--key $key \
--instance-type t1.micro \
| grep "^INSTANCE" \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: gentoo instance = $gentoo_instance"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: start checking if instance is running"
running_check=0
while [ $running_check -eq 0 ]; do
    sleep 10
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if instance is running (10 second check)"
    let running_check=`ec2-describe-instances \
            --region $region \
            $gentoo_instance \
            --filter instance-state-name=running \
            | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: instance is running"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: getting hostname"

server=`ec2-describe-instances \
--region $region \
$gentoo_instance \
--filter instance-state-name=running \
| grep "^INSTANCE" \
| awk '{ print $4 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: hostname = $server"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: Wait 120 seconds, just in case, for server to finish coming up"

sleep 120

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking connection"
up_check=`ssh -o StrictHostKeyChecking=no -i $keyfile -t ec2-user@$server "uname -a" | wc -c`

if [ $up_check -ne 0 ]; then
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: connection successful"
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: terminating instances"
    ec2-terminate-instances --region $region $instance $gentoo_instance
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: instances terminated"
else
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: connection successful"
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: stopping instance"
    ec2-stop-instances --region $region $gentoo_instance
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: instance stopped"
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: bootstrap instance: $instance"
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: gentoo instance: $gentoo_instance"
fi

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: gentoo image-id = $gentoo_image"
echo "-----"
echo "ec2-modify-image-attribute --region $region $gentoo_image --launch-permission --add all"
echo "<tr><td>$region</td><td>$gentoo_image</td><td>$architecture</td><td>ebs</td><td>$latest_kernel</td><td>$name</td></tr>"

