#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mError: Please run this script as root (sudo ./autoserver.sh)\e[0m"
  exit 1
fi

# Detect the real user running the sudo command
REAL_USER=${SUDO_USER:-root}
if [ "$REAL_USER" == "root" ]; then
  echo -e "\e[31mError: Do not run directly as root. Log in as your normal user and run with sudo.\e[0m"
  exit 1
fi

echo -e "\e[36m=======================================================\e[0m"
echo -e "\e[36m      Automated Arch Linux Home Server Setup           \e[0m"
echo -e "\e[36m=======================================================\e[0m"
echo ""

# 1. Update system and install packages
echo -e "\e[33m[*] Step 1: Updating system & Installing packages...\e[0m"
pacman -Syu --noconfirm
pacman -S --noconfirm samba minidlna syncthing yt-dlp ffmpeg btop ncdu ufw wget curl git bash-completion mopidy python-pip

# 2. Create Server Directory Structure
echo -e "\e[33m[*] Step 2: Creating storage directories in /srv/home_server...\e[0m"
SERVER_DIR="/srv/home_server"
mkdir -p $SERVER_DIR/{shared,backups,downloads}
mkdir -p $SERVER_DIR/media/{movies,series,music}

# Set permissions so anyone on the local network can read/write (Ideal for home use)
chown -R nobody:nobody $SERVER_DIR
chmod -R 777 $SERVER_DIR

# 3. Configure Samba (Network File Sharing)
echo -e "\e[33m[*] Step 3: Configuring Samba...\e[0m"
cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server string = Arch Home Server
   security = user
   map to guest = bad user
   dns proxy = no
   log file = /var/log/samba/%m.log
   max log size = 50

[PublicShare]
   path = $SERVER_DIR/shared
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no
   force create mode = 0666
   force directory mode = 0777

[Media]
   path = $SERVER_DIR/media
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no

[Backups]
   path = $SERVER_DIR/backups
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no
EOF

systemctl enable smb nmb
systemctl restart smb nmb

# 4. Configure MiniDLNA (Media Server)
echo -e "\e[33m[*] Step 4: Configuring MiniDLNA...\e[0m"
cat <<EOF > /etc/minidlna.conf
port=8200
media_dir=V,$SERVER_DIR/media/movies
media_dir=V,$SERVER_DIR/media/series
media_dir=A,$SERVER_DIR/media/music
friendly_name=Arch_Media_Server
inotify=yes
album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/albumart.jpg/AlbumArt.jpg/folder.jpg/Folder.jpg
EOF

systemctl enable minidlna
systemctl restart minidlna

# 5. Configure Syncthing (Backup System)
echo -e "\e[33m[*] Step 5: Enabling Syncthing for user: $REAL_USER...\e[0m"
systemctl enable syncthing@$REAL_USER.service
systemctl start syncthing@$REAL_USER.service

# 6. Configure UFW (Firewall)
echo -e "\e[33m[*] Step 6: Configuring and Enabling Firewall (UFW)...\e[0m"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh           # Port 22
ufw allow samba         # Ports 137, 138, 139, 445
ufw allow 8200/tcp      # MiniDLNA
ufw allow 8384/tcp      # Syncthing GUI
ufw allow 22000/tcp     # Syncthing Transfer
ufw allow 21027/udp     # Syncthing Discovery
ufw --force enable

# 7. Create a helper script for downloading media
echo -e "\e[33m[*] Step 7: Creating yt-dlp helper script...\e[0m"
cat <<'EOF' > /usr/local/bin/download-media
#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: download-media <URL>"
  exit 1
fi
echo "Downloading to /srv/home_server/downloads..."
yt-dlp -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best' -o "/srv/home_server/downloads/%(title)s.%(ext)s" "$1"
EOF
chmod +x /usr/local/bin/download-media

echo -e "\e[32m=======================================================\e[0m"
echo -e "\e[32m      Server Configuration Completed Successfully!     \e[0m"
echo -e "\e[32m=======================================================\e[0m"
echo ""
echo "Your server directories are located at: $SERVER_DIR"
echo "From any computer on the network, access files via: \\\\<Server_IP>\\"
echo "Syncthing GUI for backups is at: http://<Server_IP>:8384"
echo "To download media directly to the server, type: download-media <YouTube/Facebook_URL>"
echo ""
