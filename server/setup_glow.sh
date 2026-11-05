# Install glow (terminal markdown renderer, used by glow.nvim) from Charm's apt repo.
set -euo pipefail
if command -v glow >/dev/null; then
    exit 0
fi
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
sudo apt update
sudo apt install -y glow
