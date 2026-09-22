# A script for installing neovim and plugins. Assumes install.sh has already symlinked ~/.config/nvim/init.vim via apply_tier_dotfiles.
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:neovim-ppa/stable
sudo apt install -y neovim curl make
# Install vim-plug
curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
# Install nodejs
mkdir "$HOME/.setup/tmp"
curl -sL install-node.vercel.app/lts >> "$HOME/.setup/tmp/curl_install.sh"
sudo bash "$HOME/.setup/tmp/curl_install.sh" -y
rm -r "$HOME/.setup/tmp"
# Install plugins
nvim --headless -c "PlugInstall --sync" -c qa
