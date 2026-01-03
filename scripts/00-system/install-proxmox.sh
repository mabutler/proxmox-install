# install proxmox

# remove proxmox subscription nag
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/tools/pve/post-pve-install.sh)"

# install required packages for basic user requirements
apt install git sudo zsh tmux vim snapraid mergerfs

# install tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Setup primary user 
useradd -m -s /bin/zsh mbutler
usermod -aG sudo mbutler

# apply dotfiles
git clone --bare git@github.com:mabutler/dotfiles.git $HOME/.dotfiles
git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout master

