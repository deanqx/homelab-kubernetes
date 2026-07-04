#!/bin/bash
# ref: https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/

# Exit on error, uninitialized variable or pipefail
set -euo pipefail

shopt -s expand_aliases
alias garage="docker compose exec garage-s3 /garage"

# docker compose exec s3_object_storage /garage node id
# 64cc87709556109bd326653a60ae4a3108df1f8952c9b5592004ce0bfba1d6bb@[::1]:3901
# ...
node_id=$(garage node id |& head -n 1 | cut -d'@' -f1)

read -p "Enter capacity for S3 (e.g. 100GB): " capacity
read -p "Enter zone (e.g. germany): " zone

garage layout assign $node_id -c $capacity -z $zone
garage layout apply --version 1

echo "Script is incomplete, run following commands yourself"
echo "Execute: cat setup_gerage.sh"
exit

garage bucket create home-assistant
# ...
# Bucket: 5ed137a323e2b862fbb87a52a6386a3055a065edbd6d6ac84c37aaade36e49d8
# ...

echo "-----------------------------"

garage key create

echo "Store the \`Key ID\` and \`Secret Key\` securely."

garage bucket allow [BUCKET_ID] --read --write --owner --key [ACCESS_KEY_ID]
