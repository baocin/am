#!/usr/bin/env python3
"""Test WebSocket connection to ingestion API."""

import asyncio
import json
import time
import websockets
from datetime import datetime

API_KEY = "test-key-123"
DEVICE_ID = "test-device-001"
BASE_URL = "ws://localhost:8000"


async def test_unified_websocket():
    """Test unified WebSocket connection."""
    url = f"{BASE_URL}/realtime/ws/{DEVICE_ID}"
    headers = {"X-API-Key": API_KEY}
    
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Connecting to {url}")
    
    try:
        async with websockets.connect(url, extra_headers=headers) as websocket:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Connected!")
            
            # Handle messages
            async def receive_messages():
                try:
                    while True:
                        message = await websocket.recv()
                        data = json.loads(message)
                        timestamp = datetime.now().strftime('%H:%M:%S')
                        
                        print(f"[{timestamp}] Received: {data['message_type']}")
                        
                        # Handle health check ping
                        if data['message_type'] == 'health_check_ping':
                            pong = {
                                "id": f"{int(time.time() * 1000)}_health_check_pong",
                                "message_type": "health_check_pong",
                                "timestamp": datetime.now().isoformat(),
                                "payload": {
                                    "ping_id": data['payload']['ping_id'],
                                    "client_time_ms": data['payload']['server_time_ms']
                                },
                                "metadata": {}
                            }
                            await websocket.send(json.dumps(pong))
                            print(f"[{timestamp}] Sent pong: {data['payload']['ping_id']}")
                            
                except websockets.exceptions.ConnectionClosed:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Connection closed")
                except Exception as e:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Error: {e}")
            
            # Send test audio chunk periodically
            async def send_audio_chunks():
                chunk_num = 0
                try:
                    while True:
                        await asyncio.sleep(5)  # Send every 5 seconds
                        
                        audio_msg = {
                            "id": f"{int(time.time() * 1000)}_audio_chunk",
                            "message_type": "audio_chunk",
                            "timestamp": datetime.now().isoformat(),
                            "payload": {
                                "chunk_number": chunk_num,
                                "chunk_data": "dGVzdCBhdWRpbyBkYXRh",  # base64 "test audio data"
                                "sample_rate": 16000,
                                "channels": 1,
                                "duration_ms": 1000
                            },
                            "metadata": {
                                "compression": "none",
                                "format": "pcm"
                            }
                        }
                        
                        await websocket.send(json.dumps(audio_msg))
                        print(f"[{datetime.now().strftime('%H:%M:%S')}] Sent audio chunk {chunk_num}")
                        chunk_num += 1
                        
                except websockets.exceptions.ConnectionClosed:
                    pass
                except Exception as e:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Send error: {e}")
            
            # Run both tasks
            await asyncio.gather(
                receive_messages(),
                send_audio_chunks()
            )
            
    except Exception as e:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Connection error: {e}")


if __name__ == "__main__":
    print("Testing unified WebSocket connection...")
    print("Press Ctrl+C to stop")
    
    try:
        asyncio.run(test_unified_websocket())
    except KeyboardInterrupt:
        print("\nTest stopped")