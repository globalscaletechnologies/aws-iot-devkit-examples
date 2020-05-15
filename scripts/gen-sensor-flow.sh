#!/bin/bash

# $1: sensor type (ht | lu | pt)
# $2: mac address (xx:xx:xx:xx:xx:xx)
# $3: aws iot endpoint
# $4: output file

type=${1,,}
mac=$(echo ${2,,} | sed 's/://g')
endpoint=$3
f_out=$4
f_flow=/tmp/$(uuidgen)-flows.json
user=ec2-user

function _id {
    id=$(uuidgen | awk -F"-" '{printf "%s.%s", $1, substr($5,0,6)}')
    echo $id
}

if [ $# -ne 4 ]; then
    echo
    echo "usage: $0 [sensor-type] [mac-address] [aws-iot-endpoint] [output-file]"
    echo
    exit 1
fi

case $type in
 'ht')
    cp ./flow/sensor-ht-flows.json ${f_flow}
 ;;
 'lu')
    cp ./flow/sensor-lu-flows.json ${f_flow}
 ;;
 'pt')
    cp ./flow/sensor-pt-flows.json ${f_flow}
 ;;
esac

if [ ! -f ${f_flow} ]; then
    echo "unable download template file"
    exit 1
fi

idx=0

while true
do
    id=$(cat ${f_flow} | jq -r '.['${idx}'].id')
    if [ "${id}" == "null" ]; then
        break;
    fi
    sed -i 's/'${id}'/'$(_id)'/g' ${f_flow}
    idx=$((idx + 1))
done

sed -i 's/<MAC>/'${mac}'/g' ${f_flow}
sed -i 's/<ENDPOINT>/'${endpoint}'/g' ${f_flow}
sed -i 's/<USER>/'${user}'/g' ${f_flow}

mv ${f_flow} ${f_out}

sync

exit 0
