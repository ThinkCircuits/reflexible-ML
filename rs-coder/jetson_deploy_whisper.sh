#!/bin/bash
################################################################################
# Jetson WhisperTRT Deployment Script
# Deploys and runs Whisper ASR with TensorRT optimization on Jetson AGX Thor
# Supports multiple deployment modes: HTTP server, live mic, or container
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Model options: tiny.en, base.en, small.en, small, medium, large-v3-turbo
MODEL="${MODEL:-small.en}"

# Server configuration
PORT="${PORT:-8765}"
HOST="${HOST:-0.0.0.0}"

# Paths
WHISPER_TRT_DIR="${WHISPER_TRT_DIR:-$HOME/whisper_trt}"
VENV_DIR="$SCRIPT_DIR/whisper-venv"
CACHE_DIR="$HOME/.cache/whisper_trt"

# Container (for Jetson AI Lab mode)
WHISPER_CONTAINER="${WHISPER_CONTAINER:-dustynv/whisper:r36.4.0}"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================${NC}"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

################################################################################
# Installation Functions
################################################################################

install_faster_whisper() {
    print_info "Setting up faster-whisper (recommended for Thor)..."

    if [ ! -d "$VENV_DIR" ]; then
        print_info "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi

    source "$VENV_DIR/bin/activate"

    print_info "Installing faster-whisper and dependencies..."
    pip install --upgrade pip
    pip install faster-whisper flask flask-cors soundfile numpy

    print_status "faster-whisper installed"
    deactivate
}

install_whisper_trt() {
    print_info "Setting up whisper_trt from NVIDIA-AI-IOT..."

    if [ ! -d "$WHISPER_TRT_DIR" ]; then
        print_info "Cloning whisper_trt repository..."
        git clone https://github.com/NVIDIA-AI-IOT/whisper_trt.git "$WHISPER_TRT_DIR"
    else
        print_info "Updating whisper_trt repository..."
        cd "$WHISPER_TRT_DIR" && git pull
    fi

    cd "$WHISPER_TRT_DIR"

    if [ ! -d "$WHISPER_TRT_DIR/venv" ]; then
        print_info "Creating virtual environment..."
        python3 -m venv venv
    fi

    source venv/bin/activate

    print_info "Installing dependencies..."
    pip install --upgrade pip
    pip install -e .
    pip install sounddevice flask flask-cors

    print_status "whisper_trt installed"
    deactivate
}

download_model() {
    local model_name="$1"
    print_info "Pre-downloading model: $model_name"

    source "$VENV_DIR/bin/activate"

    python3 << EOF
from faster_whisper import WhisperModel
print("Downloading model $model_name...")
model = WhisperModel("$model_name", device="cuda", compute_type="float16")
print("Model downloaded and ready")
EOF

    deactivate
    print_status "Model $model_name downloaded"
}

################################################################################
# Server Script Generation
################################################################################

create_server_script() {
    cat > "$SCRIPT_DIR/whisper_server.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Whisper ASR HTTP Server using faster-whisper
Optimized for NVIDIA Jetson with CUDA acceleration
"""

import io
import json
import time
import wave
import argparse
import tempfile
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import socketserver

# Configuration
DEFAULT_PORT = 8765
DEFAULT_MODEL = "small.en"

# Global model (loaded once)
model = None
model_name = None

class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class ASRHandler(BaseHTTPRequestHandler):
    """HTTP handler for ASR requests."""

    def _set_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(200)
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._set_cors_headers()
            self.end_headers()
            info = {
                "status": "ok",
                "engine": "faster-whisper",
                "model": model_name,
                "device": "cuda"
            }
            self.wfile.write(json.dumps(info).encode())
            return

        if parsed.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self._set_cors_headers()
            self.end_headers()
            self.wfile.write(self._get_index_html().encode())
            return

        self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == '/api/transcribe' or parsed.path == '/transcribe':
            self._handle_transcribe()
            return

        self.send_error(404, "Not Found")

    def _handle_transcribe(self):
        """Handle audio transcription request."""
        try:
            content_type = self.headers.get('Content-Type', '')
            content_length = int(self.headers.get('Content-Length', 0))

            if content_length == 0:
                self.send_error(400, "No audio data provided")
                return

            # Read audio data
            audio_data = self.rfile.read(content_length)

            # Save to temp file (faster-whisper needs a file path)
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
                f.write(audio_data)
                temp_path = f.name

            try:
                start_time = time.time()

                # Transcribe
                segments, info = model.transcribe(
                    temp_path,
                    beam_size=5,
                    language="en",
                    vad_filter=True,
                    vad_parameters=dict(min_silence_duration_ms=500)
                )

                # Collect results
                text_parts = []
                for segment in segments:
                    text_parts.append(segment.text)

                full_text = " ".join(text_parts).strip()
                elapsed_ms = (time.time() - start_time) * 1000

                # Send response
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('X-Transcription-Time-Ms', f'{elapsed_ms:.1f}')
                self._set_cors_headers()
                self.end_headers()

                response = {
                    "text": full_text,
                    "language": info.language,
                    "language_probability": info.language_probability,
                    "duration": info.duration,
                    "transcription_time_ms": elapsed_ms
                }
                self.wfile.write(json.dumps(response).encode())

            finally:
                os.unlink(temp_path)

        except Exception as e:
            print(f"Transcription error: {e}")
            import traceback
            traceback.print_exc()
            self.send_error(500, str(e))

    def _get_index_html(self):
        return f"""<!DOCTYPE html>
<html>
<head><title>Whisper ASR Server</title></head>
<body style="font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px;">
<h1>Whisper ASR Server</h1>
<p>Model: <strong>{model_name}</strong> | Device: CUDA</p>

<h2>API Endpoints</h2>
<ul>
<li><code>GET /health</code> - Health check</li>
<li><code>POST /api/transcribe</code> - Transcribe audio (WAV/MP3/FLAC)</li>
</ul>

<h2>Test Recording</h2>
<button id="recordBtn" style="padding: 15px 30px; font-size: 18px; cursor: pointer;">
    🎤 Hold to Record
</button>
<div id="status" style="margin-top: 15px; color: #666;"></div>
<div id="result" style="margin-top: 15px; padding: 15px; background: #f5f5f5; min-height: 50px;"></div>

<script>
let mediaRecorder;
let audioChunks = [];

const btn = document.getElementById('recordBtn');
const status = document.getElementById('status');
const result = document.getElementById('result');

btn.onmousedown = btn.ontouchstart = async (e) => {{
    e.preventDefault();
    try {{
        const stream = await navigator.mediaDevices.getUserMedia({{ audio: true }});
        mediaRecorder = new MediaRecorder(stream, {{ mimeType: 'audio/webm' }});
        audioChunks = [];

        mediaRecorder.ondataavailable = (e) => audioChunks.push(e.data);
        mediaRecorder.start();

        btn.style.background = '#ff4444';
        btn.textContent = '🔴 Recording...';
        status.textContent = 'Recording...';
    }} catch (err) {{
        status.textContent = 'Error: ' + err.message;
    }}
}};

btn.onmouseup = btn.ontouchend = btn.onmouseleave = async () => {{
    if (!mediaRecorder || mediaRecorder.state !== 'recording') return;

    mediaRecorder.stop();
    btn.style.background = '';
    btn.textContent = '🎤 Hold to Record';
    status.textContent = 'Processing...';

    mediaRecorder.onstop = async () => {{
        const audioBlob = new Blob(audioChunks, {{ type: 'audio/webm' }});

        // Convert to WAV for better compatibility
        const formData = new FormData();
        formData.append('audio', audioBlob, 'recording.webm');

        const start = performance.now();
        try {{
            const response = await fetch('/api/transcribe', {{
                method: 'POST',
                body: audioBlob
            }});

            const data = await response.json();
            const elapsed = performance.now() - start;

            result.innerHTML = `<strong>Transcription:</strong> ${{data.text}}<br>
                <small>Time: ${{data.transcription_time_ms?.toFixed(0) || elapsed.toFixed(0)}}ms |
                Language: ${{data.language}} (${{(data.language_probability * 100).toFixed(1)}}%)</small>`;
            status.textContent = 'Done!';
        }} catch (err) {{
            result.textContent = 'Error: ' + err.message;
            status.textContent = 'Failed';
        }}

        // Stop all tracks
        mediaRecorder.stream.getTracks().forEach(t => t.stop());
    }};
}};
</script>
</body>
</html>"""

    def log_message(self, format, *args):
        print(f"[ASR] {args[0]}")

    def address_string(self):
        return self.client_address[0]


def load_model(name):
    """Load faster-whisper model."""
    global model, model_name

    from faster_whisper import WhisperModel

    print(f"Loading model: {name}")
    print("This may take a moment on first run (downloading model)...")

    start = time.time()
    model = WhisperModel(name, device="cuda", compute_type="float16")
    model_name = name
    elapsed = time.time() - start

    print(f"Model loaded in {elapsed:.2f}s")

    # Warmup
    print("Warming up model...")
    import numpy as np
    import soundfile as sf
    import tempfile

    # Create a short silent audio for warmup
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        sf.write(f.name, np.zeros(16000, dtype=np.float32), 16000)
        segments, _ = model.transcribe(f.name)
        list(segments)  # Consume generator
        os.unlink(f.name)

    print("Warmup complete")


def main():
    parser = argparse.ArgumentParser(description='Whisper ASR HTTP Server')
    parser.add_argument('-p', '--port', type=int, default=DEFAULT_PORT,
                        help=f'Port (default: {DEFAULT_PORT})')
    parser.add_argument('-b', '--bind', default='0.0.0.0',
                        help='Bind address (default: 0.0.0.0)')
    parser.add_argument('-m', '--model', default=DEFAULT_MODEL,
                        help=f'Model name (default: {DEFAULT_MODEL})')
    args = parser.parse_args()

    print("=" * 60)
    print("Whisper ASR Server (faster-whisper)")
    print("=" * 60)
    print()

    load_model(args.model)

    print()
    print(f"Listening on: http://{args.bind}:{args.port}")
    print()
    print("Endpoints:")
    print("  GET  /health        - Health check")
    print("  POST /api/transcribe - Transcribe audio")
    print()
    print("Press Ctrl+C to stop")
    print("=" * 60)

    server = ThreadingHTTPServer((args.bind, args.port), ASRHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
PYEOF

    chmod +x "$SCRIPT_DIR/whisper_server.py"
    print_status "Server script created: $SCRIPT_DIR/whisper_server.py"
}

################################################################################
# Run Functions
################################################################################

run_server() {
    print_header "Starting Whisper ASR Server"
    echo ""
    print_info "Model: $MODEL"
    print_info "Port: $PORT"
    echo ""

    if [ ! -d "$VENV_DIR" ]; then
        print_error "Virtual environment not found. Run with --install first."
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/whisper_server.py" ]; then
        create_server_script
    fi

    source "$VENV_DIR/bin/activate"
    python3 "$SCRIPT_DIR/whisper_server.py" --model "$MODEL" --port "$PORT" --bind "$HOST"
}

run_container() {
    print_header "Starting Whisper Container (Jetson AI Lab)"
    echo ""
    print_info "Container: $WHISPER_CONTAINER"
    print_info "This will start Jupyter Lab with Whisper notebooks"
    echo ""

    # Check for jetson-containers
    if [ ! -d "$HOME/jetson-containers" ]; then
        print_info "Cloning jetson-containers..."
        git clone https://github.com/dusty-nv/jetson-containers.git "$HOME/jetson-containers"
    fi

    cd "$HOME/jetson-containers"

    print_info "Starting container..."
    print_info "Access Jupyter at: https://$(hostname -I | awk '{print $1}'):8888"
    print_info "Default password: nvidia"
    echo ""

    ./run.sh "$WHISPER_CONTAINER"
}

################################################################################
# Main
################################################################################

print_header "Jetson Whisper ASR Deployment"
echo ""

# Parse arguments
MODE="server"
DO_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            DO_INSTALL=true
            shift
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --container)
            MODE="container"
            shift
            ;;
        --download)
            MODE="download"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Modes:"
            echo "  (default)      Start HTTP server with faster-whisper"
            echo "  --container    Run Jetson AI Lab Whisper container"
            echo "  --download     Download model only"
            echo ""
            echo "Options:"
            echo "  --install      Install dependencies first"
            echo "  --model NAME   Model to use (default: small.en)"
            echo "  --port PORT    Server port (default: 8765)"
            echo ""
            echo "Available models:"
            echo "  tiny.en, tiny     - Fastest, lowest quality"
            echo "  base.en, base     - Fast, decent quality"
            echo "  small.en, small   - Good balance (recommended)"
            echo "  medium            - Better quality, slower"
            echo "  large-v3-turbo    - Best quality, requires more memory"
            echo "  large-v3          - Highest quality, slowest"
            echo ""
            echo "Examples:"
            echo "  $0 --install              # Install and start server"
            echo "  $0 --model large-v3-turbo # Use large model"
            echo "  $0 --container            # Run Jupyter container"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Install if requested
if [ "$DO_INSTALL" = true ]; then
    install_faster_whisper
    create_server_script
    echo ""
fi

# Execute mode
case $MODE in
    server)
        run_server
        ;;
    container)
        run_container
        ;;
    download)
        if [ ! -d "$VENV_DIR" ]; then
            install_faster_whisper
        fi
        download_model "$MODEL"
        ;;
esac
