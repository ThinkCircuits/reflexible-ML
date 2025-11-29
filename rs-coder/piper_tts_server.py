#!/usr/bin/env python3
"""
Piper TTS HTTP Server - Optimized Version
Uses Python API with persistent model loading for low latency.
Supports CUDA acceleration on Jetson.
"""

import io
import json
import wave
import argparse
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import os
import socketserver

# Configuration
DEFAULT_PORT = 7860
DEFAULT_VOICE = os.path.expanduser("~/.local/share/piper-voices/en_US-amy-medium.onnx")

# Global voice object (loaded once, reused)
voice = None
voice_config = None
use_cuda = False


class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    """HTTP server that handles each request in a new thread."""
    daemon_threads = True
    allow_reuse_address = True


class TTSHandler(BaseHTTPRequestHandler):
    """HTTP handler for TTS requests."""

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
                "engine": "piper",
                "cuda": use_cuda,
                "model_loaded": voice is not None
            }
            self.wfile.write(json.dumps(info).encode())
            return

        if parsed.path == '/api/voices':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._set_cors_headers()
            self.end_headers()
            voices = self._list_voices()
            self.wfile.write(json.dumps({"voices": voices}).encode())
            return

        # Serve info page
        if parsed.path == '/' or parsed.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self._set_cors_headers()
            self.end_headers()
            self.wfile.write(self._get_index_html().encode())
            return

        self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == '/api/tts' or parsed.path == '/api/predict':
            self._handle_tts()
            return

        self.send_error(404, "Not Found")

    def _handle_tts(self):
        """Handle TTS synthesis request."""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')

            # Parse request
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                # Try form data
                data = parse_qs(body)
                data = {k: v[0] for k, v in data.items()}

            # Extract text - support multiple formats
            text = None
            if 'text' in data:
                text = data['text']
            elif 'data' in data and isinstance(data['data'], list):
                # Gradio format: data[0] is text
                text = data['data'][0]
            elif 'input' in data:
                text = data['input']

            if not text:
                self.send_error(400, "Missing 'text' parameter")
                return

            # Get optional parameters
            speed = float(data.get('speed', 1.0))

            # Synthesize using persistent model
            start_time = time.time()
            audio_data = self._synthesize(text, speed)
            elapsed_ms = (time.time() - start_time) * 1000

            if audio_data:
                self.send_response(200)
                self.send_header('Content-Type', 'audio/wav')
                self.send_header('Content-Length', str(len(audio_data)))
                self.send_header('X-Synthesis-Time-Ms', f'{elapsed_ms:.1f}')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(audio_data)
            else:
                self.send_error(500, "TTS synthesis failed")

        except Exception as e:
            print(f"TTS error: {e}")
            import traceback
            traceback.print_exc()
            self.send_error(500, str(e))

    def _synthesize(self, text, speed):
        """Synthesize using persistent PiperVoice model."""
        global voice

        if voice is None:
            print("Error: Voice model not loaded")
            return None

        try:
            from piper.config import SynthesisConfig

            # Calculate length_scale (inverse of speed)
            length_scale = 1.0 / speed if speed > 0 else 1.0

            # Create synthesis config
            syn_config = SynthesisConfig(length_scale=length_scale)

            # Synthesize - returns generator of AudioChunk (one per sentence)
            audio_bytes_list = []
            for audio_chunk in voice.synthesize(text, syn_config):
                # AudioChunk has audio_int16_bytes property
                audio_bytes_list.append(audio_chunk.audio_int16_bytes)

            if not audio_bytes_list:
                return None

            # Combine all chunks
            raw_audio = b''.join(audio_bytes_list)

            # Convert raw PCM to WAV
            wav_buffer = io.BytesIO()
            with wave.open(wav_buffer, 'wb') as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)  # 16-bit
                wav.setframerate(voice_config.sample_rate)
                wav.writeframes(raw_audio)

            return wav_buffer.getvalue()

        except Exception as e:
            print(f"Synthesis error: {e}")
            import traceback
            traceback.print_exc()
            return None

    def _list_voices(self):
        """List available voice models."""
        voices_dir = os.path.expanduser("~/.local/share/piper-voices")
        voices = []
        if os.path.isdir(voices_dir):
            for f in os.listdir(voices_dir):
                if f.endswith('.onnx'):
                    voices.append({
                        "name": f.replace('.onnx', ''),
                        "path": os.path.join(voices_dir, f)
                    })
        return voices

    def _get_index_html(self):
        cuda_status = "enabled" if use_cuda else "disabled"
        return f"""<!DOCTYPE html>
<html>
<head><title>Piper TTS Server</title></head>
<body style="font-family: sans-serif; max-width: 600px; margin: 50px auto; padding: 20px;">
<h1>Piper TTS Server</h1>
<p>Fast, local neural text-to-speech. CUDA: {cuda_status}</p>
<h2>API Endpoints</h2>
<ul>
<li><code>GET /health</code> - Health check</li>
<li><code>GET /api/voices</code> - List available voices</li>
<li><code>POST /api/tts</code> - Synthesize speech</li>
</ul>
<h2>Example</h2>
<pre>
curl -X POST http://localhost:7860/api/tts \\
  -H "Content-Type: application/json" \\
  -d '{{"text": "Hello world"}}' \\
  --output speech.wav
</pre>
<h2>Test</h2>
<input type="text" id="text" value="Hello, I am Piper TTS running on Jetson." style="width: 100%; padding: 10px;">
<button onclick="speak()" style="padding: 10px 20px; margin-top: 10px;">Speak</button>
<div id="latency" style="margin-top: 10px; color: #666;"></div>
<script>
async function speak() {{
    const text = document.getElementById('text').value;
    const start = performance.now();
    const response = await fetch('/api/tts', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{text: text}})
    }});
    const synthTime = response.headers.get('X-Synthesis-Time-Ms');
    const blob = await response.blob();
    const elapsed = performance.now() - start;
    document.getElementById('latency').textContent =
        `Synthesis: ${{synthTime}}ms | Total: ${{elapsed.toFixed(0)}}ms`;
    const audio = new Audio(URL.createObjectURL(blob));
    audio.play();
}}
</script>
</body>
</html>"""

    def log_message(self, format, *args):
        print(f"[TTS] {args[0]}")

    def address_string(self):
        """Override to skip reverse DNS lookup."""
        return self.client_address[0]


def load_voice(model_path, cuda=False):
    """Load Piper voice model."""
    global voice, voice_config, use_cuda

    from piper.voice import PiperVoice

    print(f"Loading voice model: {os.path.basename(model_path)}")
    print(f"CUDA: {'enabled' if cuda else 'disabled'}")

    start_time = time.time()
    voice = PiperVoice.load(model_path, use_cuda=cuda)
    voice_config = voice.config
    use_cuda = cuda
    elapsed = time.time() - start_time

    print(f"Model loaded in {elapsed:.2f}s")
    print(f"Sample rate: {voice_config.sample_rate} Hz")

    # Warm up the model with a short synthesis
    print("Warming up model...")
    warm_start = time.time()
    for chunk in voice.synthesize("Hello."):
        pass  # Consume generator
    warm_elapsed = (time.time() - warm_start) * 1000
    print(f"Warmup synthesis: {warm_elapsed:.0f}ms")


def main():
    parser = argparse.ArgumentParser(description='Piper TTS HTTP Server (Optimized)')
    parser.add_argument('-p', '--port', type=int, default=DEFAULT_PORT,
                        help=f'Port (default: {DEFAULT_PORT})')
    parser.add_argument('-b', '--bind', default='0.0.0.0',
                        help='Bind address (default: 0.0.0.0)')
    parser.add_argument('--voice', default=DEFAULT_VOICE,
                        help='Voice model path')
    parser.add_argument('--cuda', action='store_true',
                        help='Use CUDA (GPU) acceleration')
    args = parser.parse_args()

    # Verify voice model
    if not os.path.exists(args.voice):
        print(f"Error: Voice model not found at {args.voice}")
        print("Download from: https://huggingface.co/rhasspy/piper-voices")
        return 1

    print("=" * 60)
    print("Piper TTS Server (Optimized)")
    print("=" * 60)
    print()

    # Load voice model (persistent)
    try:
        load_voice(args.voice, cuda=args.cuda)
    except Exception as e:
        print(f"Failed to load voice model: {e}")
        import traceback
        traceback.print_exc()
        return 1

    print()
    print(f"Listening on: http://{args.bind}:{args.port}")
    print()
    print("Endpoints:")
    print("  GET  /health     - Health check")
    print("  GET  /api/voices - List voices")
    print("  POST /api/tts    - Synthesize speech")
    print()
    print("Press Ctrl+C to stop")
    print("=" * 60)

    server = ThreadingHTTPServer((args.bind, args.port), TTSHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    exit(main() or 0)
