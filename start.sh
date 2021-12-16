#! /bin/bash
  sudo apt-get update
  sudo apt-get install -y git apache2
  cd /var/www/html
  sudo rm index.html -f
  sudo git init
  sudo git pull https://github.com/DmyMi/2048.git
  ZONE=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google")
  sed -i "s|zone-here|$ZONE|" /var/www/html/index.html
  sudo systemctl restart apache2