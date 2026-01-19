#!/usr/bin/env python3
"""
🤖 BPJS BOT SERVER V1.0
Server untuk menerima request dari aplikasi Android
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
        "queue_size": task_queue.qsize(),
        "uptime": time.time() - start_time
    })

@app.route('/api/submit', methods=['POST'])
def submit_kpj():
    """Submit KPJ list from Android app"""
    try:
        data = request.json
        
        # Validate input
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
            # Remove non-digits
            kpj_clean = ''.join(filter(str.isdigit, kpj_str))
            if len(kpj_clean) == 11:
                valid_kpj.append(kpj_clean)
            else:
                logger.warning(f"Invalid KPJ format: {kpj_str}")
        
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
            "created_at": datetime.now().isoformat(),
            "started_at": None,
            "completed_at": None,
            "error": None
        }
        
        # Store task
        tasks[task_id] = task
        
        # Add to queue
        task_queue.put(task_id)
        
        logger.info(f"Task {task_id} created with {len(valid_kpj)} KPJ")
        
        # Start worker if available
        start_workers()
        
        return jsonify({
            "success": True,
            "task_id": task_id,
            "message": f"Task created with {len(valid_kpj)} KPJ",
            "queue_position": task_queue.qsize()
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
            # Get task from queue
            task_id = task_queue.get(timeout=5)
            
            if task_id not in tasks:
                continue
            
            task = tasks[task_id]
            
            # Check if cancelled
            if task.get('status') == 'cancelled':
                task_queue.task_done()
                continue
            
            # Update task status
            task['status'] = 'processing'
            task['started_at'] = datetime.now().isoformat()
            active_workers += 1
            
            logger.info(f"Worker started processing task {task_id}")
            
            try:
                # Import and run bot
                from bot_engine import BPJSBotEngine
                
                bot = BPJSBotEngine(task_id, task['kpj_list'])
                results = bot.run()
                
                # Update task with results
                task['status'] = 'completed'
                task['completed_at'] = datetime.now().isoformat()
                task['results'] = results
                
                # Calculate stats
                success_count = sum(1 for r in results if r.get('success'))
                task['processed'] = len(results)
                task['success'] = success_count
                task['failed'] = len(results) - success_count
                task['progress'] = 100
                
                logger.info(f"Task {task_id} completed: {success_count}/{len(results)} successful")
                
            except Exception as e:
                logger.error(f"Task {task_id} failed: {e}")
                task['status'] = 'failed'
                task['error'] = str(e)
            
            finally:
                active_workers -= 1
                task_queue.task_done()
                
        except queue.Empty:
            # Queue is empty, wait for new tasks
            time.sleep(1)
        except Exception as e:
            logger.error(f"Worker error: {e}")
            time.sleep(5)

def start_workers():
    """Start worker threads if needed"""
    global active_workers
    
    # Count running workers
    current_workers = threading.active_count() - 2  # Subtract main and Flask threads
    
    # Start new workers if needed
    for i in range(current_workers, MAX_WORKERS):
        worker = threading.Thread(target=bot_worker, daemon=True)
        worker.start()
        logger.info(f"Started worker thread {i+1}")

# Start time for uptime calculation
start_time = time.time()

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