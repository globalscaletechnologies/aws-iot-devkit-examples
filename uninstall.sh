#!/bin/bash



mac=
type=
username="admin"
password="12345678"
pwhash="$2b$10$HMg1tI4h.IJTRTvZLLglyu4ydDDV6reaak9b/gfdGw1vk1WF7jhAO"
credential=0
ssid=
security=
wifipw=
output=./output

usage() {
    echo -e "\nSetup aws iot sensor demo environment"
    echo -e ""
    echo -e "./uninstall.sh [arguments]"
    echo -e "\t-h | --help"
    echo -e "\t-t | --type [sensor type]"
    echo -e "\t    type:"
    echo -e "\t\tht : Humidity & Temperature sensor (Si7021)"
    echo -e "\t\tlu : Ambient Light sensor (APDS-9301)"
    echo -e "\t\tpt : Digital pressure sensor (BMP180)"
    echo -e "\t-m | --mac [mac address]"
    echo -e "\t    mac address:"
    echo -e "\t\txx:xx:xx:xx:xx:xx"
    echo -e ""
}

while [[ $# -gt 0 ]]
do
    key="${1}"
    case ${key} in
    -t|--type)
        type="${2}"
        shift
        ;;
    -m|--mac)
        mac="${2,,}"
        shift
        ;;
    -h|--help)
        usage
        exit
        ;;
    *)
        echo "ERROR: unknown parameter"
        exit 1
        ;;
    esac
    shift
done

DSN=$(echo ${mac,,} | sed 's/://g')
EC2KP=key-${type}-${DSN}

if [ -z "$mac" ] || [ -z "$type" ]; then
    printf "usage: %s [mac] [ht | lu | pt]\n" $0
    exit 1
fi


output=./output

if [ ! -d "${output}" ]; then
    echo -e "${output} folder is not exist\n"
    exit 0
fi

echo -e "delete aws iot thing and policies stack\n"
aws cloudformation delete-stack \
                    --stack-name aws-iot-thing-policies-stack

aws cloudformation wait stack-delete-complete  \
                        --stack-name aws-iot-thing-policies-stack


echo -e "delete aws ec2 node-red server stack\n"
aws cloudformation delete-stack \
                    --stack-name aws-ec2-nodered-stack

aws cloudformation wait stack-delete-complete  \
                        --stack-name aws-ec2-nodered-stack


# delete ec2 key-pair
echo -e "delete ec2 key pair\n"
aws ec2 delete-key-pair --key-name ${EC2KP}

# get certificate Id
echo -e "delete aws thing certificate\n"
certificateArn=$(cat ${output}/sensor-${type}-${DSN}.certarn.txt)
certificateId=$(echo ${certificateArn} | awk -F"/" '{print$2}')
# deactivate certificates
aws iot update-certificate \
       --certificate-id ${certificateId} \
       --new-status INACTIVE
# delete certificates
aws iot delete-certificate --certificate-id ${certificateId}

echo -e "delete completed\n"
exit 0
