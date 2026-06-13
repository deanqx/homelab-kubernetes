#!/bin/bash
# ref: https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/

docker compose exec s3_object_storage /garage key import \
$GARAGE_DEFAULT_ACCESS_KEY $GARAGE_DEFAULT_SECRET_KEY --yes

docker compose exec s3_object_storage /garage key allow \
$GARAGE_DEFAULT_ACCESS_KEY --create-bucket

# docker compose exec s3_object_storage /garage node id
# 64cc87709556109bd326653a60ae4a3108df1f8952c9b5592004ce0bfba1d6bb@[::1]:3901
# ...
node_id=$(sudo docker compose exec s3_object_storage /garage node id |& head -n 1 | cut -d'@' -f1)

sudo docker compose exec s3_object_storage /garage layout assign $node_id -c 10GB -z zone1

sudo docker compose exec s3_object_storage /garage layout show

echo
echo "After you have verified the layout, apply it like this:"
echo "sudo docker compose exec s3_object_storage /garage layout apply --version 1"
