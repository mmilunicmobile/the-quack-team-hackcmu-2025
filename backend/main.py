
from unittest import case
from fastapi import FastAPI, WebSocketDisconnect, WebSocket
from fastapi.responses import JSONResponse
import uvicorn
import random
import string
import time

app = FastAPI()

@app.get("/")
async def read_root():
    return JSONResponse(content={"message": "Welcome to the Lock In O'Clock backend!"})

# Endpoint to get a new session code
@app.get("/session-code")
async def get_session_code():
    # 3 letters, 2 digits (random order)
    letters = random.choices(string.ascii_uppercase, k=3)
    digits = random.choices(string.digits, k=2)
    code_list = letters + digits
    random.shuffle(code_list)
    code = ''.join(code_list)
    return JSONResponse(content={"session_code": code})


# In-memory session management
from typing import Dict, List


class UserState:
    def __init__(self, username: str):
        self.username = username
        self.score = 0
        self.profile = ""

class SessionItem:
    def __init__(self):
        self.timer_end_time: int = 0      # seconds
        self.timer_amount: int = 0     # seconds
        self.timer_running: bool = False # is the timer running
        self.websockets: Dict[WebSocket, UserState] = {} # connected websockets for this session

class SessionManager:
    def __init__(self):
        self.active_sessions: Dict[str, SessionItem] = {}

    async def connect(self, session_code: str, websocket: WebSocket):
        await websocket.accept()
        if session_code not in self.active_sessions.keys():
            self.active_sessions[session_code] = SessionItem()
        self.active_sessions[session_code].websockets[websocket] = UserState(username="")  # Initialize UserState

    def disconnect(self, session_code: str, websocket: WebSocket):
        if session_code in self.active_sessions:
            self.active_sessions[session_code].websockets.pop(websocket, None)

            # If there are no more connected websockets, remove the session
            if len(self.active_sessions[session_code].websockets) == 0:
                del self.active_sessions[session_code]

    async def broadcast(self, session_code: str, message: dict):
        if session_code in self.active_sessions:
            for i, ws in enumerate(self.active_sessions[session_code].websockets):
                await ws.send_json({**message, "owner": i == 0, "user_index": i})


session_manager = SessionManager()

# WebSocket endpoint for session
@app.websocket("/ws/{session_code}")
async def websocket_session(websocket: WebSocket, session_code: str):
    await session_manager.connect(session_code, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            # Expecting data like {"type": "score_update", "scores": {...}} or {"type": "time_update", "time_remaining": ...}
            current_session = session_manager.active_sessions[session_code]
            user_state = current_session.websockets[websocket]
            owner = user_state == current_session.websockets.values().__iter__().__next__()
            match data.get("type"):
                case "set_timer":
                    if owner and not current_session.timer_running:
                        current_session.timer_amount = data.get("value", 30 * 60)
                case "start_timer":
                    if owner and not current_session.timer_running:
                        current_session.timer_running = True
                        current_session.timer_end_time = int(time.time()) + current_session.timer_amount
                case "stop_timer":
                    if owner and current_session.timer_running: 
                        current_session.timer_running = False
                        current_session.timer_amount = current_session.timer_end_time - int(time.time())
                case "set_score":
                    user_state.score = data.get("value", 0)
                case "set_username":
                    user_state.username = data.get("value", "")
                case "set_profile":
                    user_state.profile = data.get("value", "")

            # Broadcast updated state to all clients in session
            active_session = session_manager.active_sessions[session_code]
            users_websockets = active_session.websockets.values()
            await session_manager.broadcast(session_code, {
                "scores": [user_state.score for user_state in users_websockets],
                "profiles": [user_state.profile for user_state in users_websockets],
                "usernames": [user_state.username for user_state in users_websockets],
                "time_remaining": active_session.timer_amount,
                "timer_running": active_session.timer_running,
                "timer_end_time": active_session.timer_end_time
            })
    except WebSocketDisconnect:
        session_manager.disconnect(session_code, websocket)

def main():
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

if __name__ == "__main__":
    main()