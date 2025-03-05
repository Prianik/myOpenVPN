wget [https://github.com/Prianik/myOpenVPN/archive/refs/heads/main.zip](https://github.com/Prianik/myOpenVPN/archive/refs/heads/main.zip) &&
unzip main.zip &&
cd myOpenVPN-main &&
cd cmd &&
chmod +x *.sh &&
cd install &&
chmod +x *.sh &&
./install-openvpn-AI.sh &&
cd ../.. &&
cp -R cmd /etc/openvpn/ &&
cd /etc/openvpn/cmd/install &&
./first-start-uservpn.sh
