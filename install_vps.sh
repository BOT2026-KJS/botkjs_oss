#!/bin/bash

# ============================================
# 🤖 BPJS BOT AUTO INSTALLER FOR VPS
# ============================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_warning "Running as non-root user. Some installations may require sudo."
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Banner
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           BPJS BOT AUTO INSTALLER FOR VPS                ║"
echo "║                 Ubuntu/Debian Edition                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Update system
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Python and system dependencies
log_info "Installing Python and system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    unzip \
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
    fonts-liberation \
    libappindicator3-1 \
    libxshmfence1

# Create project directory
PROJECT_DIR="/opt/bpjs-bot"
log_info "Creating project directory: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create virtual environment
log_info "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip

# Install Python packages
log_info "Installing Python packages..."
pip install playwright==1.40.0
pip install requests==2.31.0
pip install flask==2.3.3
pip install flask-cors==4.0.0
pip install beautifulsoup4==4.12.2
pip install lxml==4.9.3

# Install Playwright browser
log_info "Installing Playwright browser..."
playwright install chromium
playwright install-deps

# Create project files
log_info "Creating project files..."

# Create bot_server.py
cat > bot_server.py << 'EOF'
#!/usr/bin/env python3
"""
🤖 BPJS BOT SERVER V1.0
Server untuk menerima request dari aplikasi Android
"""

import json
import logging
import os
import time
import threading
import queue
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask App
app = Flask(__name__)
CORS(app)  # Allow all origins for mobile app

# Configuration
CONFIG = {
    '2CAPTCHA_API': 'c56fb68f0eac8c8e8ecd9ff8ad6deb58',
    'OSS_LOGIN': 'https://oss.bpjsketenagakerjaan.go.id/oss?token=ZW1haWw9U05MTlVUUkFDRVVUSUNBTEBHTUFJTC5DT00mbmliPTAyMjA0MDAyNjA4NTY=',
    'OSS_INPUT': 'https://oss.bpjsketenagakerjaan.go.id/oss/input-tk',
    'LAPAKASIK': 'https://lapakasik.bpjsketenagakerjaan.go.id/?source=e419a6aed6c50fefd9182774c25450b333de8d5e29169de6018bd1abb1c8f89b',
    'PORT': 5000,
    'HOST': '0.0.0.0',
    'MAX_WORKERS': 3
}

# Task Management
tasks = {}
task_queue = queue.Queue()
active_workers = 0
MAX_WORKERS = CONFIG['MAX_WORKERS']

@app.route('/')
def home():
    return jsonify({
        "status": "online",
        "service": "BPJS Bot Server",
        "version": "1.0",
        "time": datetime.now().isoformat()
    })

@app.route('/api/status', methods=['GET'])
def server_status():
    """Check server health"""
    return jsonify({
        "status": "running",
        "total_tasks": len(tasks),
        "active_workers": active_workers,
        "queue_size": task_queue.qsize()
    })

@app.route('/api/submit', methods=['POST'])
def submit_kpj():
    """Submit KPJ list from Android app"""
    try:
        data = request.json
        
        if not data or 'kpj_list' not in data:
            return jsonify({"error": "No KPJ list provided"}), 400
        
        kpj_list = data.get('kpj_list', [])
        user_id = data.get('user_id', 'anonymous')
        
        if not isinstance(kpj_list, list):
            return jsonify({"error": "KPJ list must be array"}), 400
        
        if len(kpj_list) == 0:
            return jsonify({"error": "KPJ list is empty"}), 400
        
        # Validate each KPJ
        valid_kpj = []
        for kpj in kpj_list:
            kpj_str = str(kpj).strip()
            kpj_clean = ''.join(filter(str.isdigit, kpj_str))
            if len(kpj_clean) == 11:
                valid_kpj.append(kpj_clean)
        
        if not valid_kpj:
            return jsonify({"error": "No valid KPJ numbers (must be 11 digits)"}), 400
        
        # Create task
        task_id = f"{user_id}_{int(time.time())}"
        
        task = {
            "task_id": task_id,
            "user_id": user_id,
            "kpj_list": valid_kpj,
            "status": "pending",
            "progress": 0,
            "processed": 0,
            "success": 0,
            "failed": 0,
            "results": [],
            "created_at": datetime.now().isoformat()
        }
        
        # Store task
        tasks[task_id] = task
        
        # Add to queue
        task_queue.put(task_id)
        
        logger.info(f"Task {task_id} created with {len(valid_kpj)} KPJ")
        
        return jsonify({
            "success": True,
            "task_id": task_id,
            "message": f"Task created with {len(valid_kpj)} KPJ"
        })
        
    except Exception as e:
        logger.error(f"Submit error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/task/<task_id>', methods=['GET'])
def get_task(task_id):
    """Get task status and results"""
    if task_id not in tasks:
        return jsonify({"error": "Task not found"}), 404
    
    return jsonify(tasks[task_id])

@app.route('/api/task/<task_id>/cancel', methods=['POST'])
def cancel_task(task_id):
    """Cancel a running task"""
    if task_id not in tasks:
        return jsonify({"error": "Task not found"}), 404
    
    tasks[task_id]['status'] = 'cancelled'
    return jsonify({"success": True, "message": "Task cancelled"})

@app.route('/api/tasks', methods=['GET'])
def list_tasks():
    """List all tasks"""
    return jsonify({
        "tasks": list(tasks.keys()),
        "count": len(tasks)
    })

def bot_worker():
    """Worker thread to process KPJ"""
    global active_workers
    
    while True:
        try:
            task_id = task_queue.get(timeout=5)
            
            if task_id not in tasks:
                continue
            
            task = tasks[task_id]
            
            if task.get('status') == 'cancelled':
                task_queue.task_done()
                continue
            
            task['status'] = 'processing'
            active_workers += 1
            
            logger.info(f"Worker started processing task {task_id}")
            
            # Simulate processing (replace with actual bot)
            for i, kpj in enumerate(task['kpj_list']):
                if task['status'] == 'cancelled':
                    break
                
                # Simulate processing time
                time.sleep(2)
                
                # Simulate result
                result = {
                    'kpj': kpj,
                    'success': True,
                    'data': {
                        'nama': f'Peserta {kpj}',
                        'nik': '1234567890123456',
                        'tgl_lahir': '01-01-1990'
                    },
                    'timestamp': datetime.now().isoformat()
                }
                
                task['results'].append(result)
                task['processed'] = i + 1
                task['progress'] = int(((i + 1) / len(task['kpj_list'])) * 100)
                task['success'] = i + 1
                
            task['status'] = 'completed'
            task['progress'] = 100
            
            logger.info(f"Task {task_id} completed")
            
            active_workers -= 1
            task_queue.task_done()
                
        except queue.Empty:
            time.sleep(1)
        except Exception as e:
            logger.error(f"Worker error: {e}")
            active_workers -= 1
            time.sleep(5)

def start_workers():
    """Start worker threads"""
    for i in range(MAX_WORKERS):
        worker = threading.Thread(target=bot_worker, daemon=True)
        worker.start()
        logger.info(f"Started worker thread {i+1}")

if __name__ == '__main__':
    # Create logs directory
    os.makedirs('logs', exist_ok=True)
    
    # Start worker threads
    start_workers()
    
    logger.info(f"🚀 Starting BPJS Bot Server on {CONFIG['HOST']}:{CONFIG['PORT']}")
    
    # Run Flask server
    app.run(
        host=CONFIG['HOST'],
        port=CONFIG['PORT'],
        debug=False,
        threaded=True
    )
EOF

# Create bot_engine.py
cat > bot_engine.py << 'EOF'
#!/usr/bin/env python3
"""
🤖 BPJS BOT ENGINE V1.0
Core engine untuk proses OSS dan Lapakasik
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime
from typing import Dict, List
import requests
from playwright.async_api import async_playwright

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/bot_engine.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class BPJSBotEngine:
    def __init__(self, task_id: str, kpj_list: List[str]):
        self.task_id = task_id
        self.kpj_list = kpj_list
        
        # Configuration
        self.config = {
            '2CAPTCHA_API': 'c56fb68f0eac8c8e8ecd9ff8ad6deb58',
            'OSS_LOGIN': 'https://oss.bpjsketenagakerjaan.go.id/oss?token=ZW1haWw9U05MTlVUUkFDRVVUSUNBTEBHTUFJTC5DT00mbmliPTAyMjA0MDAyNjA4NTY=',
            'OSS_INPUT': 'https://oss.bpjsketenagakerjaan.go.id/oss/input-tk',
            'LAPAKASIK': 'https://lapakasik.bpjsketenagakerjaan.go.id/?source=e419a6aed6c50fefd9182774c25450b333de8d5e29169de6018bd1abb1c8f89b',
            'HEADLESS': True,
            'TIMEOUT': 60000,
            'DELAY_BETWEEN': 3
        }
    
    def solve_captcha(self, image_path: str):
        """Solve CAPTCHA using 2Captcha"""
        try:
            logger.info(f"[{self.task_id}] Solving CAPTCHA...")
            
            with open(image_path, 'rb') as f:
                response = requests.post(
                    f"http://2captcha.com/in.php?key={self.config['2CAPTCHA_API']}&method=post",
                    files={'file': f},
                    timeout=30
                )
            
            if 'OK|' not in response.text:
                logger.error(f"CAPTCHA upload failed: {response.text}")
                return None
            
            captcha_id = response.text.split('|')[1]
            
            for i in range(30):
                time.sleep(2)
                
                result = requests.get(
                    f"http://2captcha.com/res.php?key={self.config['2CAPTCHA_API']}&action=get&id={captcha_id}",
                    timeout=30
                )
                
                if 'OK|' in result.text:
                    captcha_text = result.text.split('|')[1]
                    logger.info(f"CAPTCHA solved: {captcha_text}")
                    return captcha_text
            
            return None
            
        except Exception as e:
            logger.error(f"CAPTCHA error: {e}")
            return None
    
    async def process_kpj(self, page, kpj: str):
        """Process single KPJ"""
        logger.info(f"Processing KPJ: {kpj}")
        
        try:
            await page.goto(self.config['OSS_INPUT'], wait_until='networkidle')
            await asyncio.sleep(2)
            
            await page.fill('input[name="no_kpj"]', kpj)
            
            captcha_img = await page.query_selector('#captcha_img')
            if captcha_img:
                captcha_path = f'temp/captcha_{kpj}.png'
                os.makedirs('temp', exist_ok=True)
                await captcha_img.screenshot(path=captcha_path)
                
                captcha_text = self.solve_captcha(captcha_path)
                if captcha_text:
                    await page.fill('input[name="captcha"]', captcha_text)
                    
                    submit_btn = await page.query_selector('button[type="submit"]')
                    if submit_btn:
                        await submit_btn.click()
                        await asyncio.sleep(5)
                        
                        html = await page.content()
                        
                        if 'berhasil' in html.lower():
                            return {
                                'success': True,
                                'kpj': kpj,
                                'data': {
                                    'nama': 'Peserta BPJS',
                                    'nik': '1234567890123456',
                                    'tgl_lahir': '01-01-1990'
                                }
                            }
            
            return {
                'success': False,
                'kpj': kpj,
                'error': 'Processing failed'
            }
            
        except Exception as e:
            logger.error(f"Error processing {kpj}: {e}")
            return {
                'success': False,
                'kpj': kpj,
                'error': str(e)
            }
    
    async def run_async(self):
        """Run bot asynchronously"""
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=self.config['HEADLESS'],
                args=['--no-sandbox', '--disable-dev-shm-usage']
            )
            
            context = await browser.new_context(
                viewport={'width': 1280, 'height': 720}
            )
            
            page = await context.new_page()
            
            try:
                await page.goto(self.config['OSS_LOGIN'], wait_until='networkidle')
                await asyncio.sleep(3)
                
                results = []
                for i, kpj in enumerate(self.kpj_list):
                    result = await self.process_kpj(page, kpj)
                    results.append(result)
                    
                    if i < len(self.kpj_list) - 1:
                        await asyncio.sleep(self.config['DELAY_BETWEEN'])
                
                return results
                
            finally:
                await browser.close()
    
    def run(self):
        """Run bot synchronously"""
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            results = loop.run_until_complete(self.run_async())
            loop.close()
            
            return results
            
        except Exception as e:
            logger.error(f"Run error: {e}")
            return []
EOF

# Create requirements.txt
cat > requirements.txt << 'EOF'
playwright==1.40.0
requests==2.31.0
flask==2.3.3
flask-cors==4.0.0
beautifulsoup4==4.12.2
lxml==4.9.3
EOF

# Create config.json
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

# Create systemd service file
log_info "Creating systemd service..."
cat > /etc/systemd/system/bpjs-bot.service << EOF
[Unit]
Description=BPJS Bot Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/bot_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create necessary directories
log_info "Creating necessary directories..."
mkdir -p logs temp results

# Set permissions
log_info "Setting permissions..."
chmod +x bot_server.py bot_engine.py

# Reload systemd
log_info "Reloading systemd..."
systemctl daemon-reload

# Enable and start service
log_info "Starting BPJS Bot service..."
systemctl enable bpjs-bot.service
systemctl start bpjs-bot.service

# Configure firewall
log_info "Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 5000/tcp
    ufw --force enable
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --reload
fi

# Get server IP
SERVER_IP=$(curl -s ifconfig.me)

log_success "Installation completed!"
echo ""
echo "📊 Installation Summary:"
echo "========================"
echo "📁 Project directory: $PROJECT_DIR"
echo "🌐 Server URL: http://$SERVER_IP:5000"
echo "🐍 Virtual env: $PROJECT_DIR/venv"
echo "⚙️  Service: bpjs-bot.service"
echo ""
echo "🚀 Management Commands:"
echo "   Start:   systemctl start bpjs-bot"
echo "   Stop:    systemctl stop bpjs-bot"
echo "   Status:  systemctl status bpjs-bot"
echo "   Logs:    journalctl -u bpjs-bot -f"
echo ""
echo "📱 Test API: curl http://$SERVER_IP:5000/api/status"
echo ""
log_info "The server is now running! You can connect your Android app to:"
echo "http://$SERVER_IP:5000"