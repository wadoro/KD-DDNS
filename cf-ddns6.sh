#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Can retrieve cloudflare Domain id and list zone's, because, lazy

# Place at:
# curl https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1


# Usage:
# cf-ddns.sh -k cloudflare-api-key \
#            -u user@example.com \
#            -h host.example.com \     # fqdn of the record you want to update
#            -z example.com \          # will show you all zones if forgot, but you need this
#            -t A|AAAA                 # specify ipv4/ipv6, default: ipv4

# Optional flags:
#            -f false|true \           # force dns update, disregard local stored ip

# default config

# API key, see https://www.cloudflare.com/a/account/my-account,
# incorrect api-key results in E_UNAUTH error
CFKEY=youkey

# Username, eg: user@example.com
CFUSER=youuser

# Zone name, eg: example.com
CFZONE_NAME=zhuyuming

# Hostname to update, eg: homeserver.example.com
CFRECORD_NAME=ziyuming

# Record type, A(IPv4)|AAAA(IPv6), default IPv4
CFRECORD_TYPE=AAAA

# Cloudflare TTL for record, between 120 and 86400 seconds
CFTTL=1

# Ignore local file, update ip anyway
FORCE=false

WANIPSITE="http://ipv4.icanhazip.com"

# Site to retrieve WAN ip, other examples are: bot.whatismyipaddress.com, https://api.ipify.org/ ...
if [ "$CFRECORD_TYPE" = "A" ]; then
  :
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="http://ipv6.icanhazip.com"
else
  echo "$CFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi

# get parameter
while getopts k:u:h:z:t:f: opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;;
    u) CFUSER=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
  esac
done

# If required settings are missing just exit
if [ "$CFKEY" = "" ]; then
  echo "Missing api-key, get at: https://www.cloudflare.com/a/account/my-account"
  echo "and save in ${0} or using the -k flag"
  exit 2
fi
if [ "$CFUSER" = "" ]; then
  echo "Missing username, probably your email-address"
  echo "and save in ${0} or using the -u flag"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then 
  echo "Missing hostname, what host do you want to update?"
  echo "save in ${0} or using the -h flag"
  exit 2
fi

# If the hostname is not a FQDN
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => Hostname is not a FQDN, assuming $CFRECORD_NAME"
fi

# Get current and old WAN ip
WAN_IP=`curl -s ${WANIPSITE}`
WAN_IP_FILE=$HOME/.cf-wan_ip_$CFRECORD_NAME.txt
if [ -f $WAN_IP_FILE ]; then
  OLD_WAN_IP=`cat $WAN_IP_FILE`
else
  echo "No file, need IP（第一次使用请忽略）"
  OLD_WAN_IP=""
fi

# If WAN IP is unchanged an not -f flag, exit here
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "IP似乎没有变化，无论如何都要更新请使用  cf-ddns.sh -f true"
  exit 0
fi

# Get zone_identifier & record_identifier
ID_FILE=$HOME/.cf-id_$CFRECORD_NAME.txt
if [ -f $ID_FILE ] && [ $(wc -l $ID_FILE | cut -d " " -f 1) == 4 ] \
  && [ "$(sed -n '3,1p' "$ID_FILE")" == "$CFZONE_NAME" ] \
  && [ "$(sed -n '4,1p' "$ID_FILE")" == "$CFRECORD_NAME" ]; then
    CFZONE_ID=$(sed -n '1,1p' "$ID_FILE")
    CFRECORD_ID=$(sed -n '2,1p' "$ID_FILE")
else
    echo "正在更新IP中..."
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
    echo "$CFZONE_ID" > $ID_FILE
    echo "$CFRECORD_ID" >> $ID_FILE
    echo "$CFZONE_NAME" >> $ID_FILE
    echo "$CFRECORD_NAME" >> $ID_FILE
fi

# If WAN is changed, update cloudflare
echo "已将域名更新到新的IP： $WAN_IP"

RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")

#TG机器人通知
TOKEN=jiqirentoken #机器人密钥
chat_ID=tongzhirenid   #通知人ID
message_text="
⚠️主人IP变动了
——————————————— 
域名:【$CFRECORD_NAME】
新IP:$WAN_IP
旧IP:$OLD_WAN_IP
——————————————— "   #通知内容
MODE='HTML' 
URL="https://api.telegram.org/bot${TOKEN}/sendMessage"


if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "更新成功！"
  echo $WAN_IP > $WAN_IP_FILE
  curl -s -o /dev/null -X POST $URL -d chat_id=${chat_ID} -d text="${message_text}" 
  exit
else
  echo '更新失败了请看下面报错：'
  echo "Response: $RESPONSE"
  exit 1
fi
