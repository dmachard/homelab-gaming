import http.server
import socketserver
import json
import subprocess
import logging
import os

PORT = 8081
CREATE_NO_WINDOW = 0x08000000

log_file = os.path.expanduser("~/vm_status_server.log")
logging.basicConfig(filename=log_file, level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logging.info("Starting server on port %d", PORT)

def run_powershell(cmd):
    full_cmd = ["powershell", "-Command", cmd]
    try:
        result = subprocess.check_output(full_cmd, stderr=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW, text=True)
        return result.strip()
    except subprocess.CalledProcessError as e:
        logging.warning(f"PowerShell command failed: {cmd}")
        return ""

from http.server import BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        logging.info(f"Received GET request for path: {self.path}")
        if self.path == '/status':
            gpu_cmd = (
                "Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Radeon*' } | "
                "Select-Object -ExpandProperty InstanceId"
            )
            instance_id = run_powershell(gpu_cmd)
            gpu_status = "ok" if instance_id else "not found"

            lg_cmd = "(Get-Service -Name 'Looking Glass (host)').Status"
            lg_status = run_powershell(lg_cmd)
            looking_glass = "running" if lg_status.lower() == "running" else "not running"

            status = {
                "gpu": gpu_status,
                "looking_glass": looking_glass
            }

            logging.info(f"Sending status response: {status}")

            response = json.dumps(status).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response)
            self.wfile.flush()
        else:
            logging.info(f"Path not found: {self.path}")
            self.send_response(404)
            self.end_headers()

try:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        logging.info(f"Server listening on port {PORT}")
        httpd.serve_forever()
except Exception as e:
    logging.exception("Server error: %s", e)