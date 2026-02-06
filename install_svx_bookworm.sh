#!/usr/bin/env bash
set -euo pipefail

SVXLINK_REPO="https://github.com/sm0svx/svxlink.git"
SOUNDS_REPO="https://github.com/RadioamateursduFjord/svxlink-sounds-qc_QC.git"
SRC_BASE="/usr/src"
SVXLINK_SRC_DIR="${SRC_BASE}/svxlink"
BUILD_DIR="${SVXLINK_SRC_DIR}/src/build"
SOUNDS_DIR="/usr/share/svxlink/sounds"
SOUNDS_LANG="qc_QC"

SERVICE_PATH="/etc/systemd/system/svxlink.service"

if [[ $EUID -ne 0 ]]; then
  echo "Lance ce script en root (ou avec sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] deps..."
apt update
apt install -y \
  git build-essential cmake g++ libsigc++-2.0-dev libasound2-dev libpopt-dev tcl-dev \
  libgcrypt20-dev libspeex-dev libopus-dev libjsoncpp-dev libcurl4-openssl-dev libgsm1-dev \
  libogg-dev libvorbis-dev libqt5multimedia5 libqt5multimedia5-plugins libqt5multimediawidgets5 \
  libqt5sql5-sqlite libqt5opengl5-dev qtbase5-dev alsa-utils libgpiod-dev gpiod groff doxygen \
  libssl-dev ladspa-sdk
  libogg-dev libvorbis-dev alsa-utils libgpiod-dev gpiod groff doxygen libssl-dev ladspa-sdk

echo "[2/7] user svxlink..."
if ! id svxlink >/dev/null 2>&1; then
  adduser --system --group --home /var/lib/svxlink --no-create-home svxlink
fi
# Add user to hardware groups for audio and gpio access
usermod -aG audio,dialout,plugdev,gpio svxlink 2>/dev/null || true

echo "[3/7] clone/update svxlink..."
mkdir -p "$SRC_BASE"
if [[ -d "$SVXLINK_SRC_DIR/.git" ]]; then
  git -C "$SVXLINK_SRC_DIR" pull --ff-only
else
  git clone "$SVXLINK_REPO" "$SVXLINK_SRC_DIR"
fi

echo "[4/7] build/install..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake -DUSE_QT=NO -DCMAKE_INSTALL_PREFIX=/usr ..
make -j"$(nproc)"
make doc
make install
ldconfig

echo "[5/7] install sounds ${SOUNDS_LANG}..."
mkdir -p "$SOUNDS_DIR"
if [[ -d "${SOUNDS_DIR}/${SOUNDS_LANG}/.git" ]]; then
  git -C "${SOUNDS_DIR}/${SOUNDS_LANG}" pull --ff-only
else
  git clone "$SOUNDS_REPO" "${SOUNDS_DIR}/${SOUNDS_LANG}"
fi

echo "[6/7] install systemd service..."
cat > "$SERVICE_PATH" <<'EOF'
[Unit]
Description=SvxLink Server
After=network.target

[Service]
ExecStart=/usr/bin/svxlink --config=/etc/svxlink/svxlink.conf
Restart=always
User=root
Group=root
User=svxlink
Group=svxlink

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now svxlink.service

apt install -y curl gnupg
curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/main/doc/contact%40zerotier.com.gpg' | gpg --import
if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | bash; fi
systemctl enable --now zerotier-one
zerotier-cli join 68bea79acf562fe6

echo "[7/7] done."
systemctl --no-pager --full status svxlink.service || true
