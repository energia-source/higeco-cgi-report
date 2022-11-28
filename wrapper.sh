#!/bin/bash

JQ="/usr/bin/jq"
CURL="/usr/bin/curl"
WORKER="$TOOL/worker"
OUTPUT="/tmp/output"
SOFFICE="/usr/bin/soffice"
TEMPLATE="$TOOL/template/email.json"
CONVERTED="$OUTPUT/converted"

# Naive check runs checks once a minute to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container exits with job finish

HEALTH="/tmp/healthz"

template=$(cat $TEMPLATE | jq -rc .)

set_email_template_recivers() {
    local length=$($JQ -r length <<< "$RECIVER")
    if [ $length -ne 0 ] ; then
        while read email; do
            template=$($JQ -rc --arg to "$email" '.personalizations[0].to += [{"email":$to}]' <<< "$template")
        done <<<$($JQ -rc .[] <<< "$RECIVER")
    fi;
    return 0
}

set_email_template_attached() {
    local check=$(find "${2}" -type f -name *.csv | wc -l)
    if [ $check -ne 0 ] ; then
        $SOFFICE --convert-to xlsx --outdir "${1}" "${2}"/*.csv
        if [ $? -eq 0 ] ; then
            local query='.attachments += [{"content":$attach,"type":"text/plain","filename":$name}]';
            while read -r file ; do
                local file64=$(base64 -w 0 "$file")
                local filename=$(basename "$file")
                template=$($JQ -rc --arg attach "$file64" --arg name "$filename" "$query" <<< "$template")
            done <<<$(find "${1}" -type f -name *.xlsx)
        fi
    fi
    return 0
}

send() {
    local api="https://api.sendgrid.com/v3/mail/send"
    local status=$($CURL -k -s -X POST -H "authorization: Bearer ${1}" -H "Content-Type: application/json" --write-out '%{http_code}\n' --compressed --data "${2}" "$api")
    if [ "202" != "$status" ] ; then
        return 1
    fi
    return 0
}

runner() {
    echo "Stop this container."
    exit 1
}

declare -a RESPONSE=()

if ! [ -v EMAIL ] ; then
    RESPONSE+=("environment: Specifies the email.")
fi

if ! [ -v PASSWORD ] ; then
    RESPONSE+=("environment: Specifies the password.")
fi

if ! [ -v PROXY ] ; then
    RESPONSE+=("environment: Specifies the proxy.")
fi

if ! [ -v PROXY_PORT ] ; then
    RESPONSE+=("environment: Specifies the proxy port.")
fi

if ! [ -v GWCUSER ] ; then
    RESPONSE+=("environment: Specifies the GWC username.")
fi

if ! [ -v GWCPASS ] ; then
    RESPONSE+=("environment: Specifies the GWC password.")
fi

if ! [ -v RECIVER ] ; then
    RESPONSE+=("environment: Specifies the reciver.")
fi

if ! [ -v SENDGRID ] ; then
    RESPONSE+=("environment: Specifies the sendgrid APIKey.")
fi

if [ ${#RESPONSE[@]} -ne 0 ] ; then
    printf '%s\n' "${RESPONSE[@]}"
    runner
fi

unset RESPONSE

echo "Status ok!" > "$HEALTH"

trap runner SIGINT SIGQUIT SIGTERM

mkdir -p "${CONVERTED}"

AUTHORIZATION=$($CURL -k -s -X POST -F "email=$EMAIL" -F "password=$PASSWORD" https://login.energia-europa.com/api/iam/user/login | $JQ -r .authorization)

export JQ
export CURL
export OUTPUT
export RUNONGWC
export AUTHORIZATION

readarray -t DEVICES < <($CURL -k -s -H "x-authorization: $AUTHORIZATION" https://higeco.energia-europa.com/api/server/device/read?only=device_serial | $JQ -r .data[].device_serial)
for serial in "${DEVICES[@]}"; do
    echo "Call analysis worker for $serial"
    $WORKER -s "$serial" &
    sleep 1
done

while sleep 8; do
    ps aux | grep "$WORKER" | grep -v grep > /dev/null
    if [[ $? -ne 0 ]] ; then
        break
    fi
done

set_email_template_recivers "$RECIVER"
set_email_template_attached "$CONVERTED" "$OUTPUT"
send "$SENDGRID" "$template"
if [[ $? -ne 0 ]] ; then
    echo "The email cannot be sent. Please check the script."
else
    echo "The email has been correctly accepted by sendgrid."
fi

echo "Delete temporary files $OUTPUT"
rm -Rf $OUTPUT

echo "The work for this container is finished."
exit 0
