#!/bin/bash

echo "========================================"
echo "🤖 BPJS BOT SERVER - VPS INSTALLER"
echo "========================================"

# Update system
echo "📦 Updating system..."
sudo apt update && sudo apt upgrade -y

# Install Python
echo "🐍 Installing Python..."
sudo apt install -y python3 python3-pip python3-venv

# Install system dependencies for Playwright
echo "🔧 Installing system dependencies..."
sudo apt install -y \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libxshmfence1

# Create project directory
echo "📁 Creating project directory..."
mkdir -p ~/bpjs-bot-server
cd ~/bpjs-bot-server

# Create virtual environment
echo "🌐 Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python packages
echo "📦 Installing Python packages..."
pip install --upgrade pip
pip install playwright requests flask flask-cors beautifulsoup4 lxml

# Install Playwright browser
echo "🌐 Installing browser..."
playwright install chromium

# Create necessary directories
echo "📂 Creating directories..."
mkdir -p logs temp results

# Create configuration file
echo "⚙️ Creating config file..."
cat > config.json << 'EOF'
{
    "server": {
        "host": "0.0.0.0",
        "port": 5000,
        "max_workers": 3
    },
    "captcha": {
        "api_key": "c56fb68f0eac8c8e8ecd9ff8ad6deb58",
        "timeout": 60
    },
    "urls": {
        "oss_login": "https://oss.bpjsketenagakerjaan.go.id/oss?token=ZW1haWw9U05MTlVUUkFDRVVUSUNBTEBHTUFJTC5DT00mbmliPTAyMjA0MDAyNjA4NTY=",
        "oss_input": "https://oss.bpjsketenagakerjaan.go.id/oss/input-tk",
        "lapakasik": "https://lapakasik.bpjsketenagakerjaan.go.id/?source=e419a6aed6c50fefd9182774c25450b333de8d5e29169de6018bd1abb1c8f89b"
    }
}
EOF

# Create startup script
echo "🚀 Creating startup script..."
cat > start.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
python bot_server.py
EOF
chmod +x start.sh

# Create systemd service
echo "⚙️ Creating system service..."
sudo tee /etc/systemd/system/bpjs-bot.service << 'EOF'
[Unit]
Description=BPJS Bot Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/bpjs-bot-server
Environment="PATH=/home/$USER/bpjs-bot-server/venv/bin"
ExecStart=/home/$USER/bpjs-bot-server/venv/bin/python /home/$USER/bpjs-bot-server/bot_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Enable firewall
echo "🔥 Configuring firewall..."
sudo ufw allow 5000/tcp
sudo ufw allow ssh
sudo ufw --force enable

echo "========================================"
echo "✅ INSTALLATION COMPLETE!"
echo "========================================"
echo ""
echo "🚀 To start server:"
echo "   sudo systemctl start bpjs-bot"
echo ""
echo "📊 To check status:"
echo "   sudo systemctl status bpjs-bot"
echo ""
echo "📝 To view logs:"
echo "   journalctl -u bpjs-bot -f"
echo ""
echo "🌐 Server will be available at:"
echo "   http://$(curl -s ifconfig.me):5000"
echo ""
echo "========================================"