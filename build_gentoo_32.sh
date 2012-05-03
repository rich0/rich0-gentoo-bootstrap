#!/bin/bash

# The region to install into
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

building="Gentoo 32 EBS"
start_time=`date +%Y-%m-%dT%H:%M:%S`

if [[ $region == "" ]]; then
    region="us-east-1"
fi

if [[ $group == "" ]]; then
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: set up group"
    group="gentoo-bootstrap"

    group_exists=`ec2-describe-group \
            --region $region \
            --filter group-name=$group \
            | wc -c`

    if [ $group_exists -eq 0 ]; then
        ec2-create-group --region $region $group --description "Gentoo Bootstrap"
    fi

    ec2-authorize --region $region $group -P tcp -p 22 -s 0.0.0.0/0

    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: group set up"
fi

if [[ $key == "" || $keyfile == "" ]]; then
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: set up key"
    key="gentoo-bootstrap_$region"
    keyfile="gentoo-bootstrap_$region.pem"
   
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

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: finding latest kernel-id"

latest_kernel=`ec2-describe-images \
--region $region \
--filter image-type=kernel \
--filter manifest-location=*pv-grub* \
--owner amazon \
--filter architecture=i386 \
| grep -v "hd00" \
| awk '{ print $3 "\t"  $2 }' \
| sed "s:.*/pv-grub-hd0[^0-9]*::" \
| sort \
| tail -n 1 \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: kernel-id = $latest_kernel"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: finding bootstrap image"

boot_image=`ec2-describe-images \
--region $region \
--owner amazon \
--filter architecture=i386 \
--filter image-type=machine \
--filter root-device-type=ebs \
--filter virtualization-type=paravirtual \
--filter kernel-id=$latest_kernel \
--filter manifest-location=amazon/amzn-ami-* \
| grep "^IMAGE" \
| tail -n 1 \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: bootstrap image = $boot_image"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: starting bootstrap instance"

instance=`ec2-run-instances \
--region $region \
$boot_image \
--group $group \
--key $key \
--instance-type c1.medium \
--block-device-mapping "/dev/sdf=:10" \
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

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: copying remote_gentoo_32.sh to remote server"

scp -o StrictHostKeyChecking=no -i $keyfile remote_gentoo_32.sh ec2-user@$server:/tmp/remote_gentoo_32.sh

if [ -f "32-bit/.config" ]; then
    scp -o StrictHostKeyChecking=no -i $keyfile 32-bit/.config ec2-user@$server:/tmp/.config
fi

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: setting remote_gentoo_32.sh as executable on remote server"

ssh -o StrictHostKeyChecking=no -i $keyfile ec2-user@$server "chmod 755 /tmp/remote_gentoo_32.sh"
ssh -o StrictHostKeyChecking=no -i $keyfile -t ec2-user@$server "sudo /tmp/remote_gentoo_32.sh"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if install is done"

stopped_check=0
while [ $stopped_check -eq 0 ]; do
    sleep 60
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if install is done (1 minute check)"
    let stopped_check=`ec2-describe-instances \
            --region $region \
            $instance \
            --filter instance-state-name=stopped \
            | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: install is done"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: get volume gentoo was installed on"
volume=`ec2-describe-volumes \
--region $region \
--filter attachment.instance-id=$instance \
--filter attachment.device=/dev/sdf \
| grep "^VOLUME" \
| awk '{ print $2 } '`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: volume = $volume"

name="Gentoo_32-bit-EBS-`date +%Y-%m-%d-%H-%M-%S`"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: creating snapshot"

snapshot=`ec2-create-snapshot \
--region $region \
$volume \
--description $name \
| awk '{ print $2 }'`

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if snapshot is done"

completed_check=0
while [ $completed_check -eq 0 ]; do
    sleep 60
    echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking if snapshot is done (1 minute check)"
    let completed_check=`ec2-describe-snapshots \
        --region $region \
        $snapshot \
        --filter status=completed \
        | wc -c`
done

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: snapshot is done"

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: register image"

gentoo_image=`ec2-register \
--region $region \
--name $name \
--description "Gentoo 32-bit EBS" \
--architecture i386 \
--kernel $latest_kernel \
--root-device-name /dev/sda1 \
--block-device-mapping "/dev/sda1=$snapshot" \
--block-device-mapping "/dev/sda2=ephemeral0" \
--block-device-mapping "/dev/sda3=ephemeral1" \
| awk '{ print $2 }'`

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

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: Wait 60 seconds, just in case, for server to finish coming up"

sleep 60

echo "$building $start_time - `date +%Y-%m-%dT%H:%M:%S`: checking connection"
up_check=`ssh -o StrictHostKeyChecking=no -i $keyfile -t ec2-user@$server "uname -a" | wc -c`

if [ up_check -ne 0 ]; then
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

