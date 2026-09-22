# Get the deadsnakes ppa and install python 3.10
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt install -y python3.10 python3.10-venv python3-venv
# Install pipx for global installs in venvs
sudo apt install -y pipx
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"
# Install the latest poetry
pipx install poetry
poetry completions bash >> ~/.bash_completion
