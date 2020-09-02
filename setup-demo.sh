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
ec2=0
ec2server=
output=./output

usage() {
    echo -e "\nSetup aws iot sensor demo environment"
    echo -e ""
    echo -e "./setup-demo.sh [arguments]"
    echo -e "\t-h | --help"
    echo -e "\t-t | --type [sensor type]"
    echo -e "\t    type:"
    echo -e "\t\tht : Humidity & Temperature sensor (Si7021)"
    echo -e "\t\tlu : Ambient Light sensor (APDS-9301)"
    echo -e "\t\tpt : Digital pressure sensor (BMP180)"
    echo -e "\t-m | --mac [mac address]"
    echo -e "\t    mac address:"
    echo -e "\t\txx:xx:xx:xx:xx:xx"
    echo -e "\t-u | --username [username] : Node-Red login username, default is 'admin'"
    echo -e "\t-p | --password [password] : Node-Red login password, default is '12345678'"
    echo -e "\t-c | --credential [ssid] [security] [password] : generate Amazon FreeRTOS Credential file"
    echo -e "\t    ssid: WiFi SSID (only support 2.4GHz)"
    echo -e "\t    security: WiFi security"
    echo -e "\t\topen : Open"
    echo -e "\t\twep : WEP"
    echo -e "\t\twpa : WPA"
    echo -e "\t\twpa2 : WPA2"
    echo -e "\t    password: WiFi password"
    echo -e "\t-k | --keypair : path to exist certificate key file,"
    echo -e "\t                 if provide this key, script will doesn't create ec2 server"
    echo -e "\t-s | --sshserver : exist ssh server"
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
    -u|--username)
        username="${2}"
        shift
        ;;
    -p|--password)
        ssid="${2}"
        pwhash=$(python scripts/hash-pw.py ${password})
        shift
        ;;
    -c|--credential)
        credential=1
        ssid="${2}"
        sec="${3}"
        shift 2

        case "${sec}" in
        wep)
            security=1
            wifipw="${2}"
            shift
            ;;
        wpa)
            security=2
            wifipw="${2}"
            shift
            ;;
        wpa2)
            security=3
            wifipw="${2}"
            shift
            ;;
        open)
            security=0
            ;;
        *)
            echo "ERROR: unsupported wifi security type"
            exit 1
            ;;
        esac
        ;;
    -k|--keypair)
        ec2=1
        kpfile="${2}"
        shift
        ;;
    -s|--sshserver)
        ec2ssh="ec2-user@"${2}
        ec2url="http://${2}:1880/ui"
        shift
        ;;
    -h|--help)
        usage
        exit
        ;;
    *)
        echo "ERROR: unknown parameter : ${1}"
        exit 1
        ;;
    esac
    shift
done

DSN=$(echo ${mac,,} | sed 's/://g')
EC2KP=key-${type}-${DSN}

if [ -z "$mac" ] || [ -z "$type" ]; then
    usage
    exit 1
fi

endpoint=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --output text)


if [ ! -d ${output} ]; then
    mkdir -p ./output
fi

# generate flows.json
./scripts/gen-sensor-flow.sh ${type} ${mac} ${endpoint} ${output}/flows.json

if [ $ec2 -eq 0 ]; then
# create ec2 key pair
    echo -e "generate ec2 key pair\n"
    aws ec2 create-key-pair --key-name ${EC2KP} --query 'KeyMaterial' --output text > ${output}/${EC2KP}.pem
    chmod 400 ${output}/${EC2KP}.pem
fi

# create IoT device key and certificate
echo -e "generate IoT device key and certificate\n"
certificateArn=$(aws iot create-keys-and-certificate \
                    --set-as-active \
                    --certificate-pem-outfile ${output}/sensor-${type}-${DSN}.cert.pem \
                    --public-key-outfile ${output}/sensor-${type}-${DSN}.public.key \
                    --private-key-outfile ${output}/sensor-${type}-${DSN}.private.key \
                    --query 'certificateArn' --output text)

echo ${certificateArn} > ${output}/sensor-${type}-${DSN}.certarn.txt
# generate root-CA.crt
curl --silent --output ${output}/root-CA.crt https://www.amazontrust.com/repository/AmazonRootCA1.pem

# generate IoT thing stack parameters
cat << EOF > ${output}/aws-iot-thing-policies-params.json
[
  {
    "ParameterKey": "IoTSensorDSN",
    "ParameterValue": "${DSN}"
  },
  {
    "ParameterKey": "IoTSensorType",
    "ParameterValue": "${type}"
  },
  {
    "ParameterKey": "CertificateARN",
    "ParameterValue": "${certificateArn}"
  }
]
EOF

# create aws-iot-thing-policies stack
echo -e "create aws iot thing and policies stack\n"
aws cloudformation create-stack \
                    --stack-name aws-iot-thing-policies-${DSN} \
                    --template-body file://templates/aws-iot-thing-policies.template \
                    --parameters file://${output}/aws-iot-thing-policies-params.json \
                    --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete  \
                        --stack-name aws-iot-thing-policies-${DSN}
if [ $ec2 -eq 0 ]; then
    # generate ec2-node-red server stack parameters
    cat << EOF > ${output}/aws-ec2-nodered-srv-params.json
[
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "${EC2KP}"
  },
  {
    "ParameterKey": "InstanceType",
    "ParameterValue": "t2.micro"
  },
  {
    "ParameterKey": "SSHLocation",
    "ParameterValue": "0.0.0.0/0"
  },
  {
    "ParameterKey": "NodeRedUsername",
    "ParameterValue": "${username}"
  },
  {
    "ParameterKey": "NodeRedPassHash",
    "ParameterValue": "${pwhash}"
  }
]
EOF

    # create aws ec2 node-red server stack
    echo -e "create aws ec2 node-red server stack\n"
    aws cloudformation create-stack \
                        --stack-name aws-ec2-nodered-stack \
                        --template-body file://templates/aws-ec2-nodered-srv.template \
                        --parameters file://${output}/aws-ec2-nodered-srv-params.json

    aws cloudformation wait stack-create-complete  \
                            --stack-name aws-ec2-nodered-stack

    # get EC2 ssh info
    ec2url=$(aws cloudformation describe-stacks \
                                --stack-name aws-ec2-nodered-stack \
                                --query 'Stacks[0].Outputs[0].OutputValue' \
                                --output text)
    ec2ssh=$(aws cloudformation describe-stacks \
                                --stack-name aws-ec2-nodered-stack \
                                --query 'Stacks[0].Outputs[1].OutputValue' \
                                --output text)

    # upload device key and certificate to ec2
    scp -o StrictHostKeyChecking=no -i ${output}/${EC2KP}.pem ${output}/root-CA.crt ${ec2ssh}:/home/ec2-user/.node-red/certs/root-CA.crt > /dev/null
    scp -o StrictHostKeyChecking=no -i ${output}/${EC2KP}.pem ${output}/sensor-${type}-${DSN}.cert.pem ${ec2ssh}:/home/ec2-user/.node-red/certs/app-sensor-${type}-${DSN}.cert.pem > /dev/null
    scp -o StrictHostKeyChecking=no -i ${output}/${EC2KP}.pem ${output}/sensor-${type}-${DSN}.private.key ${ec2ssh}:/home/ec2-user/.node-red/certs/app-sensor-${type}-${DSN}.private.key > /dev/null

    # upload flows.json to ec2
    scp -o StrictHostKeyChecking=no -i ${output}/${EC2KP}.pem ${output}/flows.json ${ec2ssh}:/home/ec2-user/.node-red/flows.json > /dev/null

    # wait node-red service restart
    sleep 60

    echo -e "setup completed!\n"
    echo -e "Node-Red url: ${ec2url}\n"
    echo -e "EC2 ssh: ssh -i ${output}/${EC2KP}.pem ${ec2ssh}\n"

    if [ ${credential} -gt 0 ]; then
        ./scripts/cert2awsclientcredential.sh sensor-${type}-${DSN} ${ssid} ${security} ${wifipw}
        echo
        echo -e "Amazon FreeRTOS credential files"
        echo -e "  - ${output}/aws_clientcredential.h"
        echo -e "  - ${output}/aws_clientcredential_keys.h"
    fi
else
    # upload device key and certificate to ec2
    scp -o StrictHostKeyChecking=no -i ${kpfile} ${output}/root-CA.crt ${ec2ssh}:/home/ec2-user/.node-red/certs/root-CA.crt > /dev/null
    scp -o StrictHostKeyChecking=no -i ${kpfile} ${output}/sensor-${type}-${DSN}.cert.pem ${ec2ssh}:/home/ec2-user/.node-red/certs/app-sensor-${type}-${DSN}.cert.pem > /dev/null
    scp -o StrictHostKeyChecking=no -i ${kpfile} ${output}/sensor-${type}-${DSN}.private.key ${ec2ssh}:/home/ec2-user/.node-red/certs/app-sensor-${type}-${DSN}.private.key > /dev/null

    # upload flows.json to ec2
    scp -o StrictHostKeyChecking=no -i ${kpfile} ${output}/flows.json ${ec2ssh}:/home/ec2-user/.node-red/flows-${type}-${DSN}.json > /dev/null

    echo -e "setup completed!\n"
    echo -e "Node-Red url: ${ec2url}\n"
    echo -e "EC2 ssh: ssh -i ${kpfile} ${ec2ssh}\n"
    echo
    echo -e "Please add ${output}/flows.json to Node-Red server manually\n"

    if [ ${credential} -gt 0 ]; then
        ./scripts/cert2awsclientcredential.sh sensor-${type}-${DSN} ${ssid} ${security} ${wifipw}
        echo
        echo -e "Amazon FreeRTOS credential files"
        echo -e "  - ${output}/aws_clientcredential.h"
        echo -e "  - ${output}/aws_clientcredential_keys.h"
    fi
fi

exit 0
