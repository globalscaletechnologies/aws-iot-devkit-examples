#!/bin/bash

thing=${1,,}
ssid=$2
security=$3
password=$4
output=./output

f_certificate=${output}/${thing}.cert.pem
f_privatekey=${output}/${thing}.private.key


f_clientcredential=./templates/aws_clientcredential.templ
f_clientcredential_keys=./templates/aws_clientcredential_keys.templ

f_output=${output}/aws_clientcredential_keys.h
f_output1=${output}/aws_clientcredential.h
f_tmp=./${thing}-tmp

cp ${f_clientcredential} ${f_output1}


# xxxx.cert.pem
line=$(awk '/<ClientCertificatePEM>/ {print NR}' ${f_clientcredential_keys})
num=$(cat ${f_privatekey} | wc -l)
awk 'NR <'${line}' {print}' ${f_clientcredential_keys} > ${f_tmp}
awk 'NR < '${num}' {printf "\"%s\\n\"\\\n", $0} ;NR == '${num}' {printf "\"%s\\n\"\n", $0}' ${f_certificate} >> ${f_tmp}
awk 'NR >'${line}' {print}' ${f_clientcredential_keys} >> ${f_tmp}


# xxxx.private.key
line=$(awk '/<ClientPrivateKeyPEM>/ {print NR}' ${f_tmp})
num=$(cat ${f_privatekey} | wc -l)
awk 'NR <'${line}' {print}' ${f_tmp} > ${f_output}
awk 'NR < '${num}' {printf "\"%s\\n\"\\\n", $0} ;NR == '${num}'  {printf "\"%s\\n\"\n", $0}' ${f_privatekey} >> ${f_output}
awk 'NR >'${line}' {print}' ${f_tmp} >> ${f_output}

rm ${f_tmp}
sync


# get endpoint url
endpoint=$( aws iot describe-endpoint | jq '.endpointAddress')

cp ${f_clientcredential} ${f_output1}
sed -i 's/<IOTEndpoint>/'${endpoint}'/g' ${f_output1}
sed -i 's/<IOTThingName>/\"'${thing}'\"/g' ${f_output1}
if [ -n "${ssid}" ]; then
    sed -i 's/<WiFiSSID>/\"'${ssid}'\"/g' ${f_output1}
fi

xsecurity=""
case "$security" in
    0) xsecurity="eWiFiSecurityOpen" ;;
    1) xsecurity="eWiFiSecurityWEP" ;;
    2) xsecurity="eWiFiSecurityWPA" ;;
    *) xsecurity="eWiFiSecurityWPA2" ;;
esac
sed -i 's/<WiFiSecurity>/'${xsecurity}'/g' ${f_output1}
sed -i 's/<WiFiPasswd>/\"'${password}'\"/g' ${f_output1}
sync

exit 0
