#!/usr/bin/env python3
"""
🤖 BPJS BOT SERVER - VPS EDITION
Menerima request dari aplikasi Anda dan menjalankan bot
"""

import asyncio
import json
import logging
import os
import sys
import time
import threading
import queue
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
import requests

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask app
app = Flask(__name__)
CORS(app)  # Allow requests from your app

# Task queue
task_queue = queue.Queue()
active_tasks = {}
completed_tasks = {}

# Bot configuration
class Config:
    # 2Captcha API (simpan di config.json atau env)
    CAPTCHA_API_KEY = "c56fb68f0eac8c8e8ecd9ff8ad6deb58"
    
    # URLs
    OSS_LOGIN_URL = "https://oss.bpjsketenagakerjaan.go.id/oss?token=ZW1haWw9U05MTlVUUkFDRVVUSUNBTEBHTUFJTC5DT00mbmliPTAyMjA0MDAyNjA4NTY="
    OSS_INPUT_URL = "https://oss.bpjsketenagakerjaan.go.id/oss/input-tk"
    LAPAKASIK_URL = "https://lapakasik.bpjsketenagakerjaan.go.id/?source=e419a6aed6c50fefd9182774c25450b333de8d5e29169de6018bd1abb1c8f89b"
    
    # Server settings
    MAX_CONCURRENT = 3  # Max bot instances running
    TIMEOUT = 300  # 5 minutes per KPJ
    PORT = 5000

# API Routes
@app.route('/')
def index():
    return jsonify({
        "status": "online",
        "service": "BPJS Bot Server",
        "version": "2.0",
        "timestamp": datetime.now().isoformat()
    })

@app.route('/api/status', methods=['GET'])
def get_status():
    """Check server status"""
    return jsonify({
        "status": "running",
        "active_tasks": len(active_tasks),
        "queued_tasks": task_queue.qsize(),
        "completed_tasks": len(completed_tasks)
    })

@app.route('/api/submit-kpj', methods=['POST'])
def submit_kpj():
    """Submit KPJ list from your app"""
    try:
        data = request.json
        user_id = data.get('user_id', 'default')
        kpj_list = data.get('kpj_list', [])
        
        if not kpj_list:
            return jsonify({"error": "No KPJ provided"}), 400
        
        # Validate KPJ format
        valid_kpj = []
        for kpj in kpj_list:
            kpj_str = str(kpj).strip()
            if kpj_str.isdigit() and len(kpj_str) == 11:
                valid_kpj.append(kpj_str)
        
        if not valid_kpj:
            return jsonify({"error": "No valid KPJ numbers (must be 11 digits)"}), 400
        
        # Create task
        task_id = f"{user_id}_{int(time.time())}"
        task_data = {
            "task_id": task_id,
            "user_id": user_id,
            "kpj_list": valid_kpj,
            "status": "queued",
            "created_at": datetime.now().isoformat(),
            "progress": 0,
            "results": [],
            "total": len(valid_kpj),
            "processed": 0,
            "successful": 0,
            "failed": 0
        }
        
        # Add to task pool
        save_to_kpj_pool(task_id, task_data)
        
        # Add to queue
        task_queue.put(task_data)
        
        logger.info(f"Task {task_id} submitted with {len(valid_kpj)} KPJ")
        
        return jsonify({
            "success": True,
            "task_id": task_id,
            "message": f"Task submitted with {len(valid_kpj)} KPJ",
            "queue_position": task_queue.qsize()
        })
        
    except Exception as e:
        logger.error(f"Error submitting KPJ: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/task-status/<task_id>', methods=['GET'])
def get_task_status(task_id):
    """Get status of a specific task"""
    # Check active tasks
    if task_id in active_tasks:
        return jsonify(active_tasks[task_id])
    
    # Check completed tasks
    if task_id in completed_tasks:
        return jsonify(completed_tasks[task_id])
    
    # Check from pool
    task_data = load_from_kpj_pool(task_id)
    if task_data:
        return jsonify(task_data)
    
    return jsonify({"error": "Task not found"}), 404

@app.route('/api/results/<task_id>', methods=['GET'])
def get_results(task_id):
    """Get results of completed task"""
    if task_id in completed_tasks:
        return jsonify(completed_tasks[task_id])
    
    # Check from pool
    task_data = load_from_kpj_pool(task_id)
    if task_data and task_data.get("status") == "completed":
        return jsonify(task_data)
    
    return jsonify({"error": "Results not available or task not completed"}), 404

@app.route('/api/stop-task/<task_id>', methods=['POST'])
def stop_task(task_id):
    """Stop a running task"""
    # This would need to communicate with the bot worker
    return jsonify({"message": "Stop functionality to be implemented"})

def save_to_kpj_pool(task_id, data):
    """Save task data to JSON pool"""
    try:
        pool_file = "kpj_pool.json"
        if os.path.exists(pool_file):
            with open(pool_file, 'r') as f:
                pool = json.load(f)
        else:
            pool = {}
        
        pool[task_id] = data
        
        with open(pool_file, 'w') as f:
            json.dump(pool, f, indent=2)
            
    except Exception as e:
        logger.error(f"Error saving to pool: {e}")

def load_from_kpj_pool(task_id):
    """Load task data from JSON pool"""
    try:
        pool_file = "kpj_pool.json"
        if os.path.exists(pool_file):
            with open(pool_file, 'r') as f:
                pool = json.load(f)
                return pool.get(task_id)
    except Exception as e:
        logger.error(f"Error loading from pool: {e}")
    return None

def bot_worker():
    """Worker thread that processes tasks from queue"""
    logger.info("🤖 Bot worker started")
    
    while True:
        try:
            # Get task from queue
            task = task_queue.get()
            task_id = task["task_id"]
            
            logger.info(f"Processing task {task_id}")
            
            # Mark as active
            active_tasks[task_id] = task
            active_tasks[task_id]["status"] = "processing"
            active_tasks[task_id]["started_at"] = datetime.now().isoformat()
            
            # Run the bot
            from bot_worker import run_bot_for_task
            results = run_bot_for_task(task)
            
            # Mark as completed
            task["status"] = "completed"
            task["completed_at"] = datetime.now().isoformat()
            task["results"] = results
            task["progress"] = 100
            
            # Move to completed
            completed_tasks[task_id] = task
            del active_tasks[task_id]
            
            # Update pool
            save_to_kpj_pool(task_id, task)
            
            logger.info(f"Task {task_id} completed")
            
            # Mark task as done
            task_queue.task_done()
            
        except Exception as e:
            logger.error(f"Error in bot worker: {e}")

def start_workers(num_workers=Config.MAX_CONCURRENT):
    """Start worker threads"""
    for i in range(num_workers):
        worker = threading.Thread(target=bot_worker, daemon=True)
        worker.start()
        logger.info(f"Started bot worker {i+1}")

if __name__ == "__main__":
    # Start worker threads
    start_workers()
    
    # Run Flask server
    logger.info(f"🚀 Starting BPJS Bot Server on port {Config.PORT}")
    app.run(host='0.0.0.0', port=Config.PORT, debug=False)