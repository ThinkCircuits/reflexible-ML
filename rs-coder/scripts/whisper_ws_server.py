#!/usr/bin/env python3
"""
Whisper ASR WebSocket Server using faster-whisper
Supports real-time streaming audio transcription via WebSocket
Optimized for NVIDIA Jetson with CUDA acceleration
Supports both ws:// and wss:// (SSL) connections
"""

import asyncio
import json
import time
import tempfile
import os
import io
import wave
import argparse
import struct
import ssl
import subprocess
from pathlib import Path
from typing import Optional

try:
    import websockets
    # Use newer asyncio-native API if available
    try:
        from websockets.asyncio.server import serve
    except ImportError:
        from websockets.server import serve
except ImportError:
    print("websockets not installed. Run: pip install websockets")
    exit(1)

try:
    import numpy as np
except ImportError:
    print("numpy not installed. Run: pip install numpy")
    exit(1)

# Configuration
DEFAULT_PORT = 8766
DEFAULT_MODEL = "large-v3-turbo"
SAMPLE_RATE = 16000
CHANNELS = 1

# Global model (loaded once)
model = None
model_name = None


def load_model(name: str, device: str = "auto"):
    """Load faster-whisper model."""
    global model, model_name

    from faster_whisper import WhisperModel

    print(f"Loading model: {name}")
    print("This may take a moment on first run (downloading model)...")

    start = time.time()

    # Try CUDA first, fall back to CPU if not available
    if device == "auto":
        try:
            model = WhisperModel(name, device="cuda", compute_type="float16")
            device = "cuda"
        except ValueError as e:
            if "CUDA" in str(e):
                print("CUDA not available in CTranslate2, falling back to CPU...")
                print("For GPU acceleration, build ctranslate2 from source with CUDA support")
                model = WhisperModel(name, device="cpu", compute_type="int8")
                device = "cpu"
            else:
                raise
    elif device == "cuda":
        model = WhisperModel(name, device="cuda", compute_type="float16")
    else:
        model = WhisperModel(name, device="cpu", compute_type="int8")

    model_name = name
    elapsed = time.time() - start

    print(f"Model loaded in {elapsed:.2f}s (device: {device})")

    # Warmup
    print("Warming up model...")
    import soundfile as sf

    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        sf.write(f.name, np.zeros(16000, dtype=np.float32), 16000)
        segments, _ = model.transcribe(f.name)
        list(segments)  # Consume generator
        os.unlink(f.name)

    print("Warmup complete")


def transcribe_audio(audio_data: bytes) -> dict:
    """Transcribe audio data and return result."""
    global model

    # Save to temp file (faster-whisper needs a file path)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        f.write(audio_data)
        temp_path = f.name

    try:
        start_time = time.time()

        # Transcribe with VAD filtering for better results
        segments, info = model.transcribe(
            temp_path,
            beam_size=5,
            language="en",
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=300)
        )

        # Collect results
        text_parts = []
        for segment in segments:
            text_parts.append(segment.text)

        full_text = " ".join(text_parts).strip()
        elapsed_ms = (time.time() - start_time) * 1000

        return {
            "type": "transcription",
            "text": full_text,
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
            "transcription_time_ms": elapsed_ms,
            "final": True
        }
    finally:
        os.unlink(temp_path)


def convert_webm_to_wav(webm_data: bytes) -> Optional[bytes]:
    """Convert WebM/Opus audio to WAV format using ffmpeg."""
    import subprocess

    with tempfile.NamedTemporaryFile(suffix='.webm', delete=False) as webm_file:
        webm_file.write(webm_data)
        webm_path = webm_file.name

    wav_path = webm_path.replace('.webm', '.wav')

    try:
        # Use ffmpeg to convert
        result = subprocess.run([
            'ffmpeg', '-y', '-i', webm_path,
            '-ar', str(SAMPLE_RATE),
            '-ac', str(CHANNELS),
            '-f', 'wav',
            wav_path
        ], capture_output=True, timeout=30)

        if result.returncode != 0:
            print(f"ffmpeg error: {result.stderr.decode()}")
            return None

        with open(wav_path, 'rb') as f:
            return f.read()
    except Exception as e:
        print(f"Conversion error: {e}")
        return None
    finally:
        if os.path.exists(webm_path):
            os.unlink(webm_path)
        if os.path.exists(wav_path):
            os.unlink(wav_path)


def pcm_to_wav(pcm_data: bytes, sample_rate: int = SAMPLE_RATE, channels: int = CHANNELS) -> bytes:
    """Convert raw PCM data to WAV format."""
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)  # 16-bit
        wav.setframerate(sample_rate)
        wav.writeframes(pcm_data)
    return buffer.getvalue()


async def handle_websocket(websocket):
    """Handle WebSocket connection for audio streaming."""
    print(f"[WS] New connection from {websocket.remote_address}")

    audio_chunks = []
    audio_format = None
    sample_rate = SAMPLE_RATE
    is_recording = False

    try:
        async for message in websocket:
            # Handle text messages (commands)
            if isinstance(message, str):
                try:
                    data = json.loads(message)
                    cmd = data.get('type', data.get('command', ''))

                    if cmd == 'start':
                        # Start recording session
                        audio_chunks = []
                        audio_format = data.get('format', 'webm')
                        sample_rate = data.get('sampleRate', SAMPLE_RATE)
                        is_recording = True
                        print(f"[WS] Recording started (format={audio_format}, rate={sample_rate})")
                        await websocket.send(json.dumps({
                            "type": "status",
                            "status": "recording",
                            "message": "Recording started"
                        }))

                    elif cmd == 'stop':
                        # Stop recording and transcribe
                        is_recording = False
                        print(f"[WS] Recording stopped, {len(audio_chunks)} chunks received")

                        if not audio_chunks:
                            await websocket.send(json.dumps({
                                "type": "error",
                                "message": "No audio data received"
                            }))
                            continue

                        # Combine audio chunks
                        combined_audio = b''.join(audio_chunks)
                        print(f"[WS] Total audio size: {len(combined_audio)} bytes")

                        # Convert format if needed
                        if audio_format in ('webm', 'opus', 'ogg'):
                            print("[WS] Converting WebM/Opus to WAV...")
                            wav_data = convert_webm_to_wav(combined_audio)
                            if wav_data is None:
                                await websocket.send(json.dumps({
                                    "type": "error",
                                    "message": "Failed to convert audio format"
                                }))
                                continue
                        elif audio_format == 'pcm':
                            wav_data = pcm_to_wav(combined_audio, sample_rate)
                        else:
                            # Assume WAV
                            wav_data = combined_audio

                        # Transcribe
                        await websocket.send(json.dumps({
                            "type": "status",
                            "status": "transcribing",
                            "message": "Transcribing audio..."
                        }))

                        try:
                            result = transcribe_audio(wav_data)
                            print(f"[WS] Transcription: '{result['text']}' ({result['transcription_time_ms']:.0f}ms)")
                            await websocket.send(json.dumps(result))
                        except Exception as e:
                            print(f"[WS] Transcription error: {e}")
                            await websocket.send(json.dumps({
                                "type": "error",
                                "message": f"Transcription failed: {str(e)}"
                            }))

                        audio_chunks = []

                    elif cmd == 'ping':
                        await websocket.send(json.dumps({
                            "type": "pong",
                            "model": model_name,
                            "timestamp": time.time()
                        }))

                    elif cmd == 'info':
                        await websocket.send(json.dumps({
                            "type": "info",
                            "model": model_name,
                            "engine": "faster-whisper",
                            "device": "cuda",
                            "sample_rate": SAMPLE_RATE
                        }))

                except json.JSONDecodeError:
                    print(f"[WS] Invalid JSON: {message[:100]}")

            # Handle binary messages (audio data)
            elif isinstance(message, bytes):
                if is_recording:
                    audio_chunks.append(message)
                    # Send periodic acknowledgment
                    if len(audio_chunks) % 10 == 0:
                        await websocket.send(json.dumps({
                            "type": "status",
                            "status": "receiving",
                            "chunks": len(audio_chunks),
                            "bytes": sum(len(c) for c in audio_chunks)
                        }))

    except websockets.exceptions.ConnectionClosed as e:
        print(f"[WS] Connection closed: {e}")
    except Exception as e:
        print(f"[WS] Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print(f"[WS] Connection ended")


def generate_self_signed_cert(cert_dir: Path):
    """Generate a self-signed certificate for WSS."""
    cert_file = cert_dir / "server.crt"
    key_file = cert_dir / "server.key"

    if cert_file.exists() and key_file.exists():
        print(f"Using existing certificate: {cert_file}")
        return str(cert_file), str(key_file)

    print("Generating self-signed certificate...")
    cert_dir.mkdir(parents=True, exist_ok=True)

    # Generate certificate using openssl
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key_file),
        "-out", str(cert_file),
        "-days", "365",
        "-nodes",
        "-subj", "/CN=localhost/O=Whisper-WS/C=US",
        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"
    ]

    try:
        subprocess.run(cmd, check=True, capture_output=True)
        print(f"Certificate generated: {cert_file}")
        return str(cert_file), str(key_file)
    except subprocess.CalledProcessError as e:
        print(f"Failed to generate certificate: {e.stderr.decode()}")
        return None, None
    except FileNotFoundError:
        print("openssl not found - SSL disabled")
        return None, None


async def main(host: str, port: int, model_name_arg: str, device: str = "auto",
               ssl_cert: str = None, ssl_key: str = None, no_ssl: bool = False):
    """Main entry point."""
    print("=" * 60)
    print("Whisper ASR WebSocket Server (faster-whisper)")
    print("=" * 60)
    print()

    # Load model
    load_model(model_name_arg, device)

    # Setup SSL context if not disabled
    ssl_context = None
    protocol = "ws"

    if not no_ssl:
        if ssl_cert and ssl_key:
            cert_file, key_file = ssl_cert, ssl_key
        else:
            # Look for existing certs in vl-demo/.ssl or generate new ones
            script_dir = Path(__file__).parent.absolute()
            vl_demo_ssl = script_dir.parent / "vl-demo" / ".ssl"
            local_ssl = script_dir.parent / ".ssl"

            if (vl_demo_ssl / "server.crt").exists():
                cert_file = str(vl_demo_ssl / "server.crt")
                key_file = str(vl_demo_ssl / "server.key")
                print(f"Using existing cert from vl-demo: {cert_file}")
            elif (local_ssl / "server.crt").exists():
                cert_file = str(local_ssl / "server.crt")
                key_file = str(local_ssl / "server.key")
            else:
                cert_file, key_file = generate_self_signed_cert(local_ssl)

        if cert_file and key_file and os.path.exists(cert_file):
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_context.load_cert_chain(cert_file, key_file)
            protocol = "wss"
            print(f"SSL enabled using: {cert_file}")
        else:
            print("SSL certificate not available, using plain WebSocket")

    print()
    print(f"WebSocket server listening on: {protocol}://{host}:{port}")
    print()
    print("Protocol:")
    print("  1. Connect via WebSocket")
    print('  2. Send: {"type": "start", "format": "webm"}')
    print("  3. Send binary audio chunks")
    print('  4. Send: {"type": "stop"}')
    print("  5. Receive transcription result")
    print()
    print("Commands:")
    print('  {"type": "ping"} - Health check')
    print('  {"type": "info"} - Server info')
    print()
    print("Press Ctrl+C to stop")
    print("=" * 60)

    async with serve(handle_websocket, host, port, ssl=ssl_context):
        await asyncio.Future()  # Run forever


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Whisper ASR WebSocket Server')
    parser.add_argument('-p', '--port', type=int, default=DEFAULT_PORT,
                        help=f'Port (default: {DEFAULT_PORT})')
    parser.add_argument('-b', '--bind', default='0.0.0.0',
                        help='Bind address (default: 0.0.0.0)')
    parser.add_argument('-m', '--model', default=DEFAULT_MODEL,
                        help=f'Model name (default: {DEFAULT_MODEL})')
    parser.add_argument('-d', '--device', default='auto',
                        choices=['auto', 'cuda', 'cpu'],
                        help='Device to use (default: auto, tries cuda then cpu)')
    parser.add_argument('--ssl-cert', type=str, default=None,
                        help='Path to SSL certificate file')
    parser.add_argument('--ssl-key', type=str, default=None,
                        help='Path to SSL private key file')
    parser.add_argument('--no-ssl', action='store_true',
                        help='Disable SSL (use plain ws:// instead of wss://)')
    args = parser.parse_args()

    try:
        asyncio.run(main(args.bind, args.port, args.model, args.device,
                         args.ssl_cert, args.ssl_key, args.no_ssl))
    except KeyboardInterrupt:
        print("\nShutting down...")
