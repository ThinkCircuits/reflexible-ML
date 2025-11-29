#!/usr/bin/env python3
"""
HTTPS server for the Qwen2.5-VL Vision Demo.
Serves static files with CORS support.
Uses ThreadingHTTPServer for concurrent connections.
Auto-generates self-signed certificate for camera access.
Includes proxy for vLLM API to avoid mixed content issues.
"""

import http.server
import socketserver
import argparse
import os
import sys
import ssl
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

# Backend URLs
VLLM_BACKEND = "http://localhost:8000"
TTS_BACKEND = "http://localhost:7860"

class CORSHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler with CORS support and API proxy."""

    def end_headers(self):
        # Add CORS headers
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        """Handle preflight CORS requests."""
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        """Handle POST requests - proxy to vLLM or TTS API."""
        if self.path.startswith('/v1/'):
            self.proxy_to_vllm()
        elif self.path.startswith('/tts/'):
            self.proxy_to_tts()
        else:
            self.send_error(404, "Not Found")

    def do_GET(self):
        """Handle GET requests - serve files or proxy API."""
        if self.path.startswith('/v1/') or self.path == '/health':
            self.proxy_to_vllm()
        elif self.path.startswith('/tts/'):
            self.proxy_to_tts()
        else:
            super().do_GET()

    def proxy_to_vllm(self):
        """Proxy request to vLLM backend with streaming support."""
        target_url = f"{VLLM_BACKEND}{self.path}"

        try:
            # Read request body if present
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else None

            # Create request to vLLM
            req = urllib.request.Request(
                target_url,
                data=body,
                method=self.command
            )

            # Copy relevant headers
            if 'Content-Type' in self.headers:
                req.add_header('Content-Type', self.headers['Content-Type'])

            # Make request and stream response
            with urllib.request.urlopen(req, timeout=120) as response:
                self.send_response(response.status)

                # Copy response headers
                for header, value in response.getheaders():
                    if header.lower() not in ('transfer-encoding', 'connection'):
                        self.send_header(header, value)
                self.end_headers()

                # Stream response body
                while True:
                    chunk = response.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()

        except urllib.error.URLError as e:
            self.send_error(502, f"vLLM backend error: {e.reason}")
        except Exception as e:
            self.send_error(500, f"Proxy error: {str(e)}")

    def proxy_to_tts(self):
        """Proxy request to TTS backend (F5-TTS Gradio)."""
        # Strip /tts prefix and forward to TTS backend
        tts_path = self.path[4:]  # Remove '/tts' prefix
        if not tts_path:
            tts_path = '/'
        target_url = f"{TTS_BACKEND}{tts_path}"

        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else None

            req = urllib.request.Request(
                target_url,
                data=body,
                method=self.command
            )

            # Copy headers
            if 'Content-Type' in self.headers:
                req.add_header('Content-Type', self.headers['Content-Type'])

            with urllib.request.urlopen(req, timeout=120) as response:
                self.send_response(response.status)

                for header, value in response.getheaders():
                    if header.lower() not in ('transfer-encoding', 'connection'):
                        self.send_header(header, value)
                self.end_headers()

                # Stream response
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()

        except urllib.error.URLError as e:
            self.send_error(502, f"TTS backend error: {e.reason}")
        except Exception as e:
            self.send_error(500, f"TTS proxy error: {str(e)}")

    def address_string(self):
        """Override to skip reverse DNS lookup (major speedup)."""
        return self.client_address[0]

    def log_message(self, format, *args):
        """Custom log format."""
        print(f"[{self.log_date_time_string()}] {args[0]}")


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """HTTP server that handles each request in a new thread."""
    daemon_threads = True
    allow_reuse_address = True


def generate_self_signed_cert(cert_dir):
    """Generate a self-signed certificate for HTTPS."""
    cert_file = cert_dir / "server.crt"
    key_file = cert_dir / "server.key"

    if cert_file.exists() and key_file.exists():
        print(f"Using existing certificate: {cert_file}")
        return str(cert_file), str(key_file)

    print("Generating self-signed certificate...")
    cert_dir.mkdir(parents=True, exist_ok=True)

    # Generate certificate using openssl (RSA 2048 is faster and sufficient)
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key_file),
        "-out", str(cert_file),
        "-days", "365",
        "-nodes",  # No passphrase
        "-subj", "/CN=localhost/O=VL-Demo/C=US",
        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:192.168.68.71,IP:100.105.34.65"
    ]

    try:
        subprocess.run(cmd, check=True, capture_output=True)
        print(f"Certificate generated: {cert_file}")
        return str(cert_file), str(key_file)
    except subprocess.CalledProcessError as e:
        print(f"Failed to generate certificate: {e.stderr.decode()}")
        sys.exit(1)
    except FileNotFoundError:
        print("openssl not found. Please install openssl.")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description='Vision Demo HTTPS Server')
    parser.add_argument('-p', '--port', type=int, default=8443,
                        help='Port to serve on (default: 8443)')
    parser.add_argument('-b', '--bind', default='0.0.0.0',
                        help='Address to bind to (default: 0.0.0.0)')
    parser.add_argument('--no-ssl', action='store_true',
                        help='Disable HTTPS (use HTTP only)')
    parser.add_argument('--cert', type=str,
                        help='Path to SSL certificate file')
    parser.add_argument('--key', type=str,
                        help='Path to SSL private key file')
    args = parser.parse_args()

    # Change to the directory containing this script
    script_dir = Path(__file__).parent.absolute()
    os.chdir(script_dir)

    handler = CORSHTTPRequestHandler

    # Setup SSL if not disabled
    use_ssl = not args.no_ssl
    cert_file = None
    key_file = None

    if use_ssl:
        if args.cert and args.key:
            cert_file, key_file = args.cert, args.key
        else:
            cert_dir = script_dir / ".ssl"
            cert_file, key_file = generate_self_signed_cert(cert_dir)

    with ThreadingHTTPServer((args.bind, args.port), handler) as httpd:
        if use_ssl:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert_file, key_file)
            httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
            protocol = "https"
        else:
            protocol = "http"
        print(f"=" * 60)
        print(f"Qwen2.5-VL Vision Demo Server")
        print(f"=" * 60)
        print(f"")
        print(f"Protocol: {protocol.upper()}")
        print(f"Serving on: {protocol}://{args.bind}:{args.port}")
        print(f"")
        print(f"Open in browser:")
        print(f"  Local:   {protocol}://localhost:{args.port}")

        # Try to get local IP
        try:
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            print(f"  Network: {protocol}://{local_ip}:{args.port}")
        except:
            pass

        if use_ssl:
            print(f"")
            print(f"NOTE: Using self-signed certificate.")
            print(f"      Your browser will show a security warning.")
            print(f"      Click 'Advanced' -> 'Proceed' to continue.")

        print(f"")
        print(f"Make sure the vLLM server is running:")
        print(f"  ./jetson_deploy_vl.sh")
        print(f"")
        print(f"Press Ctrl+C to stop")
        print(f"=" * 60)

        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")
            sys.exit(0)


if __name__ == '__main__':
    main()
