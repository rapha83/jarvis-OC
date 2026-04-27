import asyncio
import contextlib
import json
import os
import tempfile
from pathlib import Path

import re
from datetime import datetime

import aiohttp
from aiohttp import web, WSMsgType
import ssl
import edge_tts
import logging
import base64
import unicodedata
from typing import Hashable

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s:%(name)s:%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

HOST_IP = os.environ.get("HOST_IP", "0.0.0.0")
HOST_PORT = int(os.environ.get("HOST_PORT", "8765"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "small")
WHISPER_BEAM_SIZE = int(os.environ.get("WHISPER_BEAM_SIZE", "3"))
WHISPER_VAD_MIN_SILENCE_MS = int(os.environ.get("WHISPER_VAD_MIN_SILENCE_MS", "450"))
WHISPER_NO_SPEECH_THRESHOLD = float(os.environ.get("WHISPER_NO_SPEECH_THRESHOLD", "0.45"))
STT_NORMALIZATION_ENABLED = os.environ.get("STT_NORMALIZATION_ENABLED", "true").lower() not in {
    "0",
    "false",
    "no",
}
TTS_VOICE = os.environ.get("TTS_VOICE", "pt-BR-AntonioNeural")
JARVIS_CLIENT_TOKEN = os.environ.get("JARVIS_CLIENT_TOKEN", "")

# OpenClaw integration
OPENCLAW_URL = os.environ.get("OPENCLAW_URL", "http://host.docker.internal:18789")
OPENCLAW_CONFIG = os.environ.get("OPENCLAW_CONFIG", "")
OPENCLAW_AGENT = os.environ.get("OPENCLAW_AGENT", "it-infrastructure-specialist")


def _load_openclaw_token() -> tuple[str, str]:
    env_token = os.environ.get("OPENCLAW_TOKEN", "").strip()
    config_path = OPENCLAW_CONFIG.strip()
    if config_path:
        with contextlib.suppress(Exception):
            config = json.loads(Path(config_path).read_text())
            config_token = (
                config.get("gateway", {})
                .get("auth", {})
                .get("token", "")
                .strip()
            )
            if config_token:
                if env_token and env_token != config_token:
                    logger.warning("OPENCLAW_TOKEN differs from OPENCLAW_CONFIG; using config token")
                return config_token, "config"
    return env_token, "env" if env_token else "missing"


OPENCLAW_TOKEN, OPENCLAW_TOKEN_SOURCE = _load_openclaw_token()

# Max recent transcriptions per client for feedback loop detection
_MAX_RECENT = 5
# Max conversation turns to send to the agent (sliding window)
MAX_CONVERSATION_TURNS = 20

# Pre-generated acknowledgment phrases (edge-tts, same voice as Jarvis)
ACK_PHRASES = [
    'Sim, líder supremo.',
    'Às suas ordens, líder supremo.',
    'Prontinho, líder supremo.',
    'Diga, líder supremo.',
    'Ouvindo, líder supremo.',
    'Como posso ajudar, líder supremo?',
    'Pode falar, líder supremo.',
    'Estou aqui, líder supremo.',
]
_ack_audio_cache: dict[int, bytes] = {}

_DEFAULT_WHISPER_INITIAL_PROMPT = (
    "Conversa em português brasileiro com um assistente chamado Jarvis. "
    "Comandos frequentes: que dia é hoje, que horas são, leia esta tela, resuma esta tela, "
    "liga a luz da sala, apaga a luz do quarto, como está a energia solar, "
    "qual é a temperatura agora, abre as cortinas, fecha as cortinas, "
    "liga o ar condicionado, desliga o ar, qual é a previsão do tempo para amanhã, "
    "acende a luz da cozinha, liga o ventilador do quarto, desliga tudo, "
    "quanto está a bateria do carro, qual é o consumo de energia hoje, "
    "status da casa, modo noturno, modo cinema."
)
WHISPER_INITIAL_PROMPT = (
    os.environ.get("WHISPER_INITIAL_PROMPT", "").strip()
    or _DEFAULT_WHISPER_INITIAL_PROMPT
)

logger.info(f"Loading Whisper model: {WHISPER_MODEL}...")
from faster_whisper import WhisperModel
# int8: 2-4x mais rápido que float32, qualidade quase idêntica em CPU
whisper_model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8")
logger.info("Whisper model loaded successfully")


# _is_feedback_loop is now a method on WebSocketHandler (per-client state)


def _clean_for_tts(text: str) -> str:
    """Strip markdown and special characters for clean TTS output."""
    text = _strip_emoji_for_tts(text)
    text = re.sub(r'\*{1,3}(.+?)\*{1,3}', r'\1', text)
    text = re.sub(r'_{1,2}(.+?)_{1,2}', r'\1', text)
    text = re.sub(r'#{1,6}\s*', '', text)
    text = re.sub(r'`{1,3}[^`]*`{1,3}', '', text)
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
    text = re.sub(r'^[-*+•]\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'\n{2,}', '. ', text)
    text = re.sub(r'\n', ' ', text)
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()


def _strip_emoji_for_tts(text: str) -> str:
    """Remove emoji and presentation selectors so speech engines do not read them aloud."""
    cleaned = []
    for char in text or "":
        codepoint = ord(char)
        if (
            0x1F000 <= codepoint <= 0x1FAFF
            or 0x2600 <= codepoint <= 0x27BF
            or codepoint in {0x200D, 0xFE0E, 0xFE0F}
        ):
            continue
        cleaned.append(char)
    return "".join(cleaned)


def _speech_override_from_request(request: web.Request) -> bool | None:
    raw = (request.headers.get("X-Jarvis-Speak") or request.query.get("speak") or "").strip().lower()
    if raw in {"0", "false", "no", "text", "silent"}:
        return False
    if raw in {"1", "true", "yes", "voice", "speak"}:
        return True
    return None


def _extract_voice_directive(text: str) -> tuple[dict, str]:
    """Extract an optional first-line JSON directive from agent output."""
    original = text or ""
    stripped = original.lstrip()
    if not stripped.startswith("{"):
        return {}, original

    try:
        payload, end_index = json.JSONDecoder().raw_decode(stripped)
    except json.JSONDecodeError:
        return {}, original

    if not isinstance(payload, dict):
        return {}, original

    directive = payload.get("jarvisDirective") or payload.get("directive")
    if directive is None and any(key in payload for key in ("speak", "expectingReply", "tone")):
        directive = payload
    if not isinstance(directive, dict):
        return {}, original

    clean_directive = {}
    if isinstance(directive.get("speak"), bool):
        clean_directive["speak"] = directive["speak"]
    if isinstance(directive.get("expectingReply"), bool):
        clean_directive["expectingReply"] = directive["expectingReply"]
    if isinstance(directive.get("tone"), str):
        clean_directive["tone"] = directive["tone"][:32]

    if not clean_directive:
        return {}, original

    remaining = stripped[end_index:].lstrip("\r\n ")
    return clean_directive, remaining


def _is_authorized(request: web.Request) -> bool:
    """Authorize legacy clients. A token is mandatory for protected endpoints."""
    if not JARVIS_CLIENT_TOKEN:
        logger.warning("Rejecting legacy request because JARVIS_CLIENT_TOKEN is not configured")
        return False
    auth = request.headers.get("Authorization", "")
    if auth == f"Bearer {JARVIS_CLIENT_TOKEN}":
        return True
    return request.query.get("token") == JARVIS_CLIENT_TOKEN


def _normalize_agent_id(agent_id: str | None) -> str:
    """Return a safe OpenClaw agent id, falling back to the configured default."""
    raw = (agent_id or "").strip()
    if raw.startswith("openclaw/"):
        raw = raw[len("openclaw/"):]
    if not raw:
        return OPENCLAW_AGENT
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", raw):
        logger.warning("Ignoring invalid OpenClaw agent id override")
        return OPENCLAW_AGENT
    return raw


def _agent_from_request(request: web.Request) -> str:
    return _normalize_agent_id(
        request.headers.get("X-Jarvis-Agent")
        or request.query.get("agent")
    )


def _fold_text(text: str) -> str:
    folded = unicodedata.normalize("NFKD", text or "")
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    folded = folded.lower()
    folded = re.sub(r"[^a-z0-9]+", " ", folded)
    return re.sub(r"\s+", " ", folded).strip()


def _apply_case_like(source: str, replacement: str) -> str:
    if source.isupper():
        return replacement.upper()
    return replacement


def _normalize_product_terms(text: str) -> tuple[str, list[str]]:
    corrections: list[str] = []
    replacements = [
        (r"\b(open\s*(?:claw|clau|clo|clos|close|clor|cloro)|opem\s*claw)\b", "OpenClaw", "term:OpenClaw"),
        (r"\b(home\s*(?:assistant|assistente|assistent|assisten)|rome\s*assistant)\b", "Home Assistant", "term:Home Assistant"),
        (r"\b(proxmox|proximox|promox|prox\s*mock|prox\s*mox)\b", "Proxmox", "term:Proxmox"),
        (r"\b(docker|doquer|dokcer|doker)\b", "Docker", "term:Docker"),
        (r"\b(kubernetes|kubernets|kubernet|cubertenes)\b", "Kubernetes", "term:Kubernetes"),
        (r"\b(mac\s*(?:mini|mine|meany|minnie)|meque\s*mini)\b", "Mac mini", "term:Mac mini"),
        (r"\b(jarvis|jarves|jarviz|ja\s*vis|jardis)\b", "Jarvis", "term:Jarvis"),
    ]
    normalized = text
    for pattern, replacement, correction in replacements:
        def replace(match: re.Match) -> str:
            corrections.append(correction)
            return _apply_case_like(match.group(0), replacement)

        normalized = re.sub(pattern, replace, normalized, flags=re.IGNORECASE)
    return normalized, corrections


def _normalize_transcription(text: str) -> dict:
    """Conservatively repair common STT mistakes before sending text to the agent."""
    original = (text or "").strip()
    if not original or not STT_NORMALIZATION_ENABLED:
        return {
            "text": original,
            "original": original,
            "corrections": [],
            "changed": False,
        }

    folded = _fold_text(original)
    phrase_rules = [
        (
            [
                "que te queira hoje",
                "que queira hoje",
                "que dia que hoje",
                "que dia que e hoje",
                "que dia e hoje",
                "qual dia e hoje",
            ],
            "Que dia é hoje?",
            "phrase:data_hoje",
        ),
        (
            [
                "que horas sao",
                "que hora sao",
                "que horas e",
                "qual hora e agora",
                "qual horario agora",
            ],
            "Que horas são?",
            "phrase:horas",
        ),
        (
            [
                "qual e a data de hoje",
                "qual a data de hoje",
                "data de hoje",
            ],
            "Qual é a data de hoje?",
            "phrase:data_hoje",
        ),
        (
            [
                "leia esta tela",
                "leia essa tela",
                "leia isto na tela",
                "leia isso na tela",
                "o que aparece nesta tela",
                "o que aparece nessa tela",
            ],
            "Leia esta tela.",
            "phrase:ler_tela",
        ),
        (
            [
                "resuma esta tela",
                "resuma essa tela",
                "resume esta tela",
                "resume essa tela",
            ],
            "Resuma esta tela.",
            "phrase:resumir_tela",
        ),
    ]
    for variants, replacement, correction in phrase_rules:
        if folded in variants:
            return {
                "text": replacement,
                "original": original,
                "corrections": [correction],
                "changed": replacement != original,
            }

    normalized, corrections = _normalize_product_terms(original)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return {
        "text": normalized,
        "original": original,
        "corrections": corrections,
        "changed": normalized != original,
    }


def _mac_context_from_request(request: web.Request) -> str:
    """Read optional local macOS context sent by the native menu bar app."""
    encoded = request.headers.get("X-Jarvis-Mac-Context-B64", "").strip()
    if encoded:
        with contextlib.suppress(Exception):
            return base64.b64decode(encoded).decode("utf-8", errors="replace")[:1200]
    return request.headers.get("X-Jarvis-Mac-Context", "").strip()[:1200]


def _screen_context_from_request(request: web.Request) -> str:
    """Read optional screen/OCR context sent by the native menu bar app."""
    encoded = request.headers.get("X-Jarvis-Screen-Context-B64", "").strip()
    if encoded:
        with contextlib.suppress(Exception):
            return base64.b64decode(encoded).decode("utf-8", errors="replace")[:4200]
    return request.headers.get("X-Jarvis-Screen-Context", "").strip()[:4200]


class AudioProcessor:
    def __init__(self):
        self.whisper_model = whisper_model
        self.temp_dir = tempfile.mkdtemp()
        self._whisper_lock = asyncio.Lock()

    async def transcribe_audio(self, audio_data: bytes) -> str:
        import uuid
        raw_path = wav_path = None
        try:
            # Nomes únicos por requisição para evitar conflito entre clientes simultâneos
            uid = uuid.uuid4().hex
            raw_path = os.path.join(self.temp_dir, f"raw_{uid}")
            wav_path = os.path.join(self.temp_dir, f"audio_{uid}.wav")

            with open(raw_path, "wb") as f:
                f.write(audio_data)

            proc = await asyncio.create_subprocess_exec(
                "ffmpeg", "-y", "-i", raw_path, "-ar", "16000", "-ac", "1", "-sample_fmt", "s16", wav_path,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                _stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()
                raise Exception("FFmpeg timed out")
            if proc.returncode != 0:
                raise Exception(f"FFmpeg failed: {stderr.decode('utf-8', errors='ignore')[:200]}")

            async with self._whisper_lock:
                segments, info = await asyncio.get_running_loop().run_in_executor(
                    None, lambda: self.whisper_model.transcribe(
                        wav_path,
                        language="pt",
                        beam_size=WHISPER_BEAM_SIZE,
                        temperature=0.0,
                        condition_on_previous_text=False,
                        vad_filter=True,
                        vad_parameters={"min_silence_duration_ms": WHISPER_VAD_MIN_SILENCE_MS},
                        no_speech_threshold=WHISPER_NO_SPEECH_THRESHOLD,
                        initial_prompt=WHISPER_INITIAL_PROMPT,
                    )
                )
                text = " ".join([seg.text for seg in segments]).strip()
            logger.info(f"Transcribed: '{text}' (language: {info.language}, prob: {info.language_probability:.2f})")
            return text
        except Exception as e:
            logger.error(f"Transcription error: {e}")
            raise
        finally:
            # Limpar arquivos temporários
            for p in (raw_path, wav_path):
                if not p:
                    continue
                try:
                    os.unlink(p)
                except OSError:
                    pass

    async def generate_tts(self, text: str) -> bytes:
        text = (text or "").strip()
        if len(text) < 2:
            logger.warning(f"TTS text too short: '{text}'")
            return b""
        try:
            comm = edge_tts.Communicate(text, TTS_VOICE)
            data = bytearray()
            async for chunk in comm.stream():
                if chunk["type"] == "audio":
                    data.extend(chunk["data"])
            return bytes(data)
        except Exception as e:
            logger.error(f"TTS error: {e}")
            return b""  # Return empty instead of raising — text response still sent


class WebSocketHandler:
    def __init__(self):
        self.audio_processor = AudioProcessor()
        self.clients = set()
        self._audio_chunks: dict[Hashable, list[bytes]] = {}
        self._conversation_history: dict[Hashable, list[dict]] = {}
        self._recent_transcriptions: dict[Hashable, list[str]] = {}
        self._cancelled: dict[Hashable, bool] = {}
        self._active_tasks: dict[Hashable, asyncio.Task] = {}
        self._idempotency_results: dict[tuple[str, str], dict] = {}
        self._idempotency_order: list[tuple[str, str]] = []

    def _ensure_client_state(self, client_id: Hashable):
        self._audio_chunks.setdefault(client_id, [])
        self._conversation_history.setdefault(client_id, [])
        self._recent_transcriptions.setdefault(client_id, [])
        self._cancelled.setdefault(client_id, False)

    def _is_feedback_loop(self, text: str, client_id: Hashable) -> bool:
        """Detect potential audio feedback loop (repeated transcriptions)."""
        text = text.lower().strip()
        if not text:
            return False
        recent = self._recent_transcriptions.get(client_id, [])
        for prev in recent:
            if prev == text:
                return True
        recent.append(text)
        while len(recent) > _MAX_RECENT:
            recent.pop(0)
        self._recent_transcriptions[client_id] = recent
        return False

    def _raise_if_cancelled(self, client_id: Hashable):
        if self._cancelled.get(client_id):
            raise asyncio.CancelledError

    def _rollback_last_user_turn(self, client_id: Hashable):
        history = self._conversation_history.get(client_id, [])
        if history and history[-1].get("role") == "user":
            removed = history.pop()
            self._conversation_history[client_id] = history
            logger.info(f"Rolled back cancelled user turn for client {client_id}: {removed['content'][:80]}")

    def _replace_last_assistant_turn(self, client_id: Hashable, content: str):
        history = self._conversation_history.get(client_id, [])
        for index in range(len(history) - 1, -1, -1):
            if history[index].get("role") == "assistant":
                history[index]["content"] = content
                self._conversation_history[client_id] = history
                return

    def _track_active_task(self, client_id: Hashable, task: asyncio.Task):
        self._active_tasks[client_id] = task

        def _cleanup(done_task: asyncio.Task):
            current = self._active_tasks.get(client_id)
            if current is task:
                self._active_tasks.pop(client_id, None)
            try:
                done_task.result()
            except asyncio.CancelledError:
                logger.info(f"Processing task cancelled for client {client_id}")
            except Exception as exc:
                logger.error(f"Processing task failed for client {client_id}: {exc}")

        task.add_done_callback(_cleanup)

    def _idempotency_key(self, client_id: Hashable, key: str | None) -> tuple[str, str] | None:
        if not key:
            return None
        key = key.strip()
        if not key:
            return None
        return (str(client_id), key)

    def _cached_result(self, client_id: Hashable, key: str | None) -> dict | None:
        cache_key = self._idempotency_key(client_id, key)
        if cache_key is None:
            return None
        return self._idempotency_results.get(cache_key)

    def _remember_result(self, client_id: Hashable, key: str | None, result: dict):
        cache_key = self._idempotency_key(client_id, key)
        if cache_key is None:
            return
        self._idempotency_results[cache_key] = result
        self._idempotency_order.append(cache_key)
        while len(self._idempotency_order) > 30:
            old_key = self._idempotency_order.pop(0)
            self._idempotency_results.pop(old_key, None)

    async def _cancel_active_task(self, client_id: Hashable, reason: str, clear_buffer: bool = False):
        self._cancelled[client_id] = True
        task = self._active_tasks.get(client_id)
        if task and not task.done():
            logger.info(f"Cancelling active processing for client {client_id}: {reason}")
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await task
        if clear_buffer:
            self._audio_chunks[client_id] = []

    async def handle_connection(self, request: web.Request) -> web.WebSocketResponse:
        if not _is_authorized(request):
            raise web.HTTPUnauthorized(text="Unauthorized")
        ws = web.WebSocketResponse(heartbeat=30.0)
        await ws.prepare(request)
        self.clients.add(ws)
        client_id = id(ws)
        self._ensure_client_state(client_id)
        logger.info(f"Client connected. Total: {len(self.clients)}")

        try:
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                    except json.JSONDecodeError:
                        logger.warning(f"Malformed JSON from client: {msg.data[:100]}")
                        continue
                    action = data.get("action")
                    if action == "stop":
                        await self._cancel_active_task(client_id, "new stop action")
                        task = asyncio.create_task(self.process_audio(ws, client_id))
                        self._track_active_task(client_id, task)
                    elif action == "cancel":
                        logger.info(f"Client {client_id} requested cancellation")
                        await self._cancel_active_task(client_id, "client requested cancellation", clear_buffer=True)
                elif msg.type == WSMsgType.BINARY:
                    self._audio_chunks[client_id].append(msg.data)
                elif msg.type == WSMsgType.ERROR:
                    break
        except Exception as e:
            logger.error(f"WS error: {e}")
        finally:
            await self._cancel_active_task(client_id, "client disconnected", clear_buffer=True)
            self.clients.discard(ws)
            self._active_tasks.pop(client_id, None)
            self._audio_chunks.pop(client_id, None)
            self._conversation_history.pop(client_id, None)
            self._recent_transcriptions.pop(client_id, None)
            self._cancelled.pop(client_id, None)
            logger.info(f"Client disconnected. Total: {len(self.clients)}")
        return ws

    async def process_audio_payload(
        self,
        audio_data: bytes,
        client_id: Hashable,
        status_cb=None,
        transcription_cb=None,
        idempotency_key: str | None = None,
        mac_context: str = "",
        screen_context: str = "",
        agent_id: str | None = None,
        speak_override: bool | None = None,
    ) -> dict:
        """Run STT -> agent -> TTS for one utterance and return text/audio payload."""
        self._ensure_client_state(client_id)
        if cached := self._cached_result(client_id, idempotency_key):
            logger.info(f"Returning cached voice result for client {client_id}")
            return cached

        try:
            # Reset cancel flag — this is a NEW command from the user
            self._cancelled[client_id] = False

            if not audio_data:
                return {"type": "error", "message": "No audio data"}

            logger.info(f"Processing audio for client {client_id}: {len(audio_data)} bytes")
            self._raise_if_cancelled(client_id)
            if status_cb:
                await status_cb("Processing speech...")
            transcribed_text = await self.audio_processor.transcribe_audio(audio_data)
            self._raise_if_cancelled(client_id)

            if not transcribed_text.strip():
                logger.info(f"Empty transcription for client {client_id}; skipping response")
                return {"type": "no_speech", "transcription": ""}
            normalized = _normalize_transcription(transcribed_text)
            if normalized["changed"]:
                logger.info(
                    "STT normalized for client %s: '%s' -> '%s' corrections=%s",
                    client_id,
                    normalized["original"],
                    normalized["text"],
                    normalized["corrections"],
                )

            result = await self._respond_to_transcription(
                normalized["text"],
                client_id,
                status_cb=status_cb,
                transcription_cb=transcription_cb,
                check_feedback=True,
                mac_context=mac_context,
                screen_context=screen_context,
                agent_id=agent_id,
                original_transcription=normalized["original"],
                normalization_corrections=normalized["corrections"],
                speak_override=speak_override,
            )
            self._remember_result(client_id, idempotency_key, result)
            return result

        except asyncio.CancelledError:
            logger.info(f"Processing cancelled for client {client_id}")
            raise

    async def process_text_payload(
        self,
        text: str,
        client_id: Hashable,
        status_cb=None,
        transcription_cb=None,
        idempotency_key: str | None = None,
        mac_context: str = "",
        screen_context: str = "",
        check_feedback: bool = False,
        agent_id: str | None = None,
        speak_override: bool | None = None,
    ) -> dict:
        """Run text -> agent -> TTS for one utterance from native wake-word extraction."""
        self._ensure_client_state(client_id)
        if cached := self._cached_result(client_id, idempotency_key):
            logger.info(f"Returning cached text result for client {client_id}")
            return cached

        self._cancelled[client_id] = False
        text = (text or "").strip()
        if not text:
            return {"type": "no_speech", "transcription": ""}
        normalized = _normalize_transcription(text)
        if normalized["changed"]:
            logger.info(
                "Text normalized for client %s: '%s' -> '%s' corrections=%s",
                client_id,
                normalized["original"],
                normalized["text"],
                normalized["corrections"],
            )

        try:
            result = await self._respond_to_transcription(
                normalized["text"],
                client_id,
                status_cb=status_cb,
                transcription_cb=transcription_cb,
                check_feedback=check_feedback,
                mac_context=mac_context,
                screen_context=screen_context,
                agent_id=agent_id,
                original_transcription=normalized["original"],
                normalization_corrections=normalized["corrections"],
                speak_override=speak_override,
            )
            self._remember_result(client_id, idempotency_key, result)
            return result
        except asyncio.CancelledError:
            logger.info(f"Text processing cancelled for client {client_id}")
            raise

    async def _respond_to_transcription(
        self,
        transcribed_text: str,
        client_id: Hashable,
        status_cb=None,
        transcription_cb=None,
        check_feedback: bool = True,
        mac_context: str = "",
        screen_context: str = "",
        agent_id: str | None = None,
        original_transcription: str | None = None,
        normalization_corrections: list[str] | None = None,
        speak_override: bool | None = None,
    ) -> dict:
        agent_task: asyncio.Task | None = None
        try:
            if check_feedback and self._is_feedback_loop(transcribed_text, client_id):
                logger.warning(f"Feedback loop detected: '{transcribed_text}'")
                if transcription_cb:
                    await transcription_cb(transcribed_text)
                tts_audio = await self.audio_processor.generate_tts(
                    "Detectei um loop de áudio. Aproxime o dispositivo ou use fones."
                )
                self._raise_if_cancelled(client_id)
                return {
                    "type": "response",
                    "transcription": transcribed_text,
                    "originalTranscription": original_transcription or transcribed_text,
                    "normalizationCorrections": normalization_corrections or [],
                    "text": "Detectei um loop de áudio.",
                    "expectingReply": False,
                    "directive": {"speak": True, "expectingReply": False},
                    "audio": tts_audio,
                }

            if transcription_cb:
                await transcription_cb(transcribed_text)
            self._raise_if_cancelled(client_id)
            if status_cb:
                await status_cb("Thinking...")

            agent_task = asyncio.create_task(
                self.agent_process(
                    transcribed_text,
                    client_id,
                    mac_context=mac_context,
                    screen_context=screen_context,
                    agent_id=agent_id,
                )
            )
            try:
                response_text = await asyncio.wait_for(asyncio.shield(agent_task), timeout=5.0)
            except asyncio.TimeoutError:
                logger.info("Agent taking >5s, keeping response channel quiet")
                if status_cb:
                    await status_cb("Verificando...")
                self._raise_if_cancelled(client_id)
                response_text = await agent_task

            self._raise_if_cancelled(client_id)
            directive, response_text = _extract_voice_directive(response_text)
            if directive:
                self._replace_last_assistant_turn(client_id, response_text)
            if isinstance(directive.get("expectingReply"), bool):
                expecting_reply = directive["expectingReply"]
            else:
                expecting_reply = self._is_expecting_reply(response_text)
            logger.info(f"Agent response ({len(response_text)} chars), expectingReply={expecting_reply}")

            should_speak = directive.get("speak", True) is not False
            if speak_override is not None:
                should_speak = speak_override and should_speak
            tts_audio = b""
            if should_speak:
                if status_cb:
                    await status_cb("Speaking...")
                self._raise_if_cancelled(client_id)
                tts_text = _clean_for_tts(response_text)
                logger.info(f"Generating TTS for: '{tts_text[:80]}...'")
                tts_audio = await self.audio_processor.generate_tts(tts_text)
                self._raise_if_cancelled(client_id)
                if not tts_audio:
                    logger.warning("TTS generated empty audio, skipping send_bytes")
            else:
                logger.info("Skipping TTS due to Jarvis voice directive")

            return {
                "type": "response",
                "transcription": transcribed_text,
                "originalTranscription": original_transcription or transcribed_text,
                "normalizationCorrections": normalization_corrections or [],
                "text": response_text,
                "expectingReply": expecting_reply,
                "directive": directive,
                "audio": tts_audio,
            }

        except asyncio.CancelledError:
            logger.info(f"Processing cancelled for client {client_id}")
            if agent_task and not agent_task.done():
                agent_task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await agent_task
            self._rollback_last_user_turn(client_id)
            raise

    async def process_audio(self, ws: web.WebSocketResponse, client_id: Hashable):
        try:
            chunks = self._audio_chunks.get(client_id, [])
            audio_data = b"".join(chunks)
            self._audio_chunks[client_id] = []

            async def send_status(message: str):
                await ws.send_json({"type": "status", "message": message})

            async def send_transcription(text: str):
                await ws.send_json({"type": "transcription", "text": text})

            result = await self.process_audio_payload(
                audio_data,
                client_id,
                status_cb=send_status,
                transcription_cb=send_transcription,
            )

            if result["type"] == "error":
                await ws.send_json({"type": "error", "message": result["message"]})
                return
            if result["type"] == "no_speech":
                await ws.send_json({"type": "no_speech"})
                return

            audio = result.get("audio") or b""
            if audio:
                logger.info(f"TTS audio generated: {len(audio)} bytes, sending to client")
                await ws.send_bytes(audio)

            await ws.send_json({
                "type": "response",
                "text": result["text"],
                "expectingReply": result["expectingReply"],
                "directive": result.get("directive", {}),
                "transcription": result.get("transcription", ""),
                "originalTranscription": result.get("originalTranscription", ""),
                "normalizationCorrections": result.get("normalizationCorrections", []),
            })

        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.error(f"Processing error: {e}")
            try:
                await ws.send_json({"type": "error", "message": str(e)})
            except Exception:
                pass

    async def handle_voice_request(self, request: web.Request) -> web.Response:
        """HTTP voice endpoint used by the native macOS menu bar app."""
        if not _is_authorized(request):
            raise web.HTTPUnauthorized(text="Unauthorized")

        session_id = (
            request.headers.get("X-Jarvis-Session")
            or request.query.get("session")
            or request.remote
            or "native"
        )
        client_id = f"http:{session_id}"
        idempotency_key = request.headers.get("X-Jarvis-Idempotency-Key")
        mac_context = _mac_context_from_request(request)
        screen_context = _screen_context_from_request(request)
        agent_id = _agent_from_request(request)
        speak_override = _speech_override_from_request(request)
        audio_data = await request.read()

        try:
            result = await self.process_audio_payload(
                audio_data,
                client_id,
                idempotency_key=idempotency_key,
                mac_context=mac_context,
                screen_context=screen_context,
                agent_id=agent_id,
                speak_override=speak_override,
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.error(f"HTTP voice processing error: {exc}")
            return web.json_response({"type": "error", "message": str(exc)}, status=500)

        if result["type"] == "error":
            return web.json_response(result, status=400)
        if result["type"] == "no_speech":
            return web.json_response(result)

        audio = result.get("audio") or b""
        return web.json_response({
            "type": "response",
            "transcription": result.get("transcription", ""),
            "originalTranscription": result.get("originalTranscription", ""),
            "normalizationCorrections": result.get("normalizationCorrections", []),
            "text": result["text"],
            "expectingReply": result["expectingReply"],
            "directive": result.get("directive", {}),
            "audioMime": "audio/mpeg" if audio else "",
            "audioBase64": base64.b64encode(audio).decode("ascii") if audio else "",
        })

    async def handle_text_request(self, request: web.Request) -> web.Response:
        """HTTP text endpoint used when the native app extracts a command after wake word."""
        if not _is_authorized(request):
            raise web.HTTPUnauthorized(text="Unauthorized")

        session_id = (
            request.headers.get("X-Jarvis-Session")
            or request.query.get("session")
            or request.remote
            or "native"
        )
        client_id = f"http:{session_id}"
        idempotency_key = request.headers.get("X-Jarvis-Idempotency-Key")
        mac_context = _mac_context_from_request(request)
        screen_context = _screen_context_from_request(request)
        agent_id = _agent_from_request(request)
        speak_override = _speech_override_from_request(request)
        check_feedback = request.headers.get("X-Jarvis-Check-Feedback", "").lower() in {
            "1",
            "true",
            "yes",
        }

        try:
            payload = await request.json()
        except Exception:
            payload = {}
        text = (payload.get("text") or "").strip()

        try:
            result = await self.process_text_payload(
                text,
                client_id,
                idempotency_key=idempotency_key,
                mac_context=mac_context,
                screen_context=screen_context,
                check_feedback=check_feedback,
                agent_id=agent_id,
                speak_override=speak_override,
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.error(f"HTTP text processing error: {exc}")
            return web.json_response({"type": "error", "message": str(exc)}, status=500)

        if result["type"] == "error":
            return web.json_response(result, status=400)
        if result["type"] == "no_speech":
            return web.json_response(result)

        audio = result.get("audio") or b""
        return web.json_response({
            "type": "response",
            "transcription": result.get("transcription", text),
            "originalTranscription": result.get("originalTranscription", text),
            "normalizationCorrections": result.get("normalizationCorrections", []),
            "text": result["text"],
            "expectingReply": result["expectingReply"],
            "directive": result.get("directive", {}),
            "audioMime": "audio/mpeg" if audio else "",
            "audioBase64": base64.b64encode(audio).decode("ascii") if audio else "",
        })

    async def handle_text_stream_request(self, request: web.Request) -> web.StreamResponse:
        """Stream text responses for the native text overlay without waiting for TTS."""
        if not _is_authorized(request):
            raise web.HTTPUnauthorized(text="Unauthorized")

        session_id = (
            request.headers.get("X-Jarvis-Session")
            or request.query.get("session")
            or request.remote
            or "native"
        )
        client_id = f"http:{session_id}"
        mac_context = _mac_context_from_request(request)
        screen_context = _screen_context_from_request(request)
        agent_id = _agent_from_request(request)

        try:
            payload = await request.json()
        except Exception:
            payload = {}
        text = (payload.get("text") or "").strip()

        response = web.StreamResponse(
            status=200,
            reason="OK",
            headers={
                "Content-Type": "application/x-ndjson; charset=utf-8",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )
        await response.prepare(request)

        async def send_event(payload: dict):
            await response.write(
                (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
            )

        if not text:
            await send_event({"type": "no_speech", "transcription": ""})
            await response.write_eof()
            return response

        normalized = _normalize_transcription(text)
        await send_event({
            "type": "transcription",
            "transcription": normalized["text"],
            "originalTranscription": normalized["original"],
            "normalizationCorrections": normalized["corrections"],
        })
        await send_event({"type": "status", "message": "Thinking..."})

        full_response = ""
        visible_response = ""
        first_visible_chunk = True
        directive = {}
        try:
            async for chunk in self._agent_process_streaming(
                normalized["text"],
                client_id,
                mac_context=mac_context,
                screen_context=screen_context,
                agent_id=agent_id,
            ):
                full_response = f"{full_response} {chunk}".strip()
                chunk_to_send = chunk

                if first_visible_chunk:
                    maybe_directive, cleaned = _extract_voice_directive(full_response)
                    if maybe_directive:
                        directive = maybe_directive
                        chunk_to_send = cleaned
                        visible_response = cleaned
                        first_visible_chunk = False
                        self._replace_last_assistant_turn(client_id, cleaned)
                    elif full_response.lstrip().startswith("{"):
                        continue
                    else:
                        visible_response = f"{visible_response} {chunk_to_send}".strip()
                        first_visible_chunk = False
                else:
                    visible_response = f"{visible_response} {chunk_to_send}".strip()

                visible_response = visible_response.strip()
                if chunk_to_send.strip():
                    await send_event({
                        "type": "delta",
                        "delta": chunk_to_send,
                        "text": visible_response,
                    })

            if not visible_response:
                _, visible_response = _extract_voice_directive(full_response)
                visible_response = visible_response.strip()
            if isinstance(directive.get("expectingReply"), bool):
                expecting_reply = directive["expectingReply"]
            else:
                expecting_reply = self._is_expecting_reply(visible_response)

            await send_event({
                "type": "response",
                "transcription": normalized["text"],
                "originalTranscription": normalized["original"],
                "normalizationCorrections": normalized["corrections"],
                "text": visible_response,
                "expectingReply": expecting_reply,
                "directive": directive,
            })
        except Exception as exc:
            logger.error(f"HTTP text stream processing error: {exc}")
            await send_event({"type": "error", "message": str(exc)})
        finally:
            with contextlib.suppress(Exception):
                await response.write_eof()
        return response

    async def handle_transcribe_request(self, request: web.Request) -> web.Response:
        """HTTP STT-only endpoint used before optional screen/OCR enrichment."""
        if not _is_authorized(request):
            raise web.HTTPUnauthorized(text="Unauthorized")

        audio_data = await request.read()
        if not audio_data:
            return web.json_response({"type": "error", "message": "No audio data"}, status=400)

        try:
            text = await self.audio_processor.transcribe_audio(audio_data)
        except Exception as exc:
            logger.error(f"HTTP transcription error: {exc}")
            return web.json_response({"type": "error", "message": str(exc)}, status=500)

        if not text.strip():
            return web.json_response({"type": "no_speech", "transcription": ""})
        normalized = _normalize_transcription(text)
        if normalized["changed"]:
            logger.info(
                "STT-only normalized: '%s' -> '%s' corrections=%s",
                normalized["original"],
                normalized["text"],
                normalized["corrections"],
            )
        return web.json_response({
            "type": "transcription",
            "transcription": normalized["text"],
            "originalTranscription": normalized["original"],
            "normalizedTranscription": normalized["text"],
            "normalizationCorrections": normalized["corrections"],
        })

    def _is_expecting_reply(self, text: str) -> bool:
        """Detect if the agent response expects a follow-up from the user."""
        text = text.strip()
        if text.endswith("?"):
            return True
        lower = text.lower()
        patterns = [
            "quer que eu", "deseja que", "prefere", "gostaria que",
            "posso fazer", "devo ", "opção ", "qual deles", "qual delas",
            "me confirma", "pode confirmar", "o que acha",
        ]
        return any(p in lower for p in patterns)

    @staticmethod
    def _split_sentences(buffer: str) -> tuple[list[str], str]:
        """Split buffer into complete sentences and remaining text."""
        sentences = []
        # Match sentence endings: . ! ? followed by space or end of string
        # Avoid splitting on abbreviations like Sr. Sra. Dr. etc.
        pattern = r'(?<![A-Z][a-z])(?<!\b(?:Sr|Sra|Dr|Dra|Prof|Jr|Ltd|Inc|etc))[.!?]+(?:\s|$)'
        last_end = 0
        for m in re.finditer(pattern, buffer):
            sentence = buffer[last_end:m.end()].strip()
            if sentence and len(sentence) >= 5:
                sentences.append(sentence)
            last_end = m.end()
        remainder = buffer[last_end:].strip()
        return sentences, remainder

    def _build_agent_messages(
        self,
        text: str,
        client_id: Hashable,
        mac_context: str = "",
        screen_context: str = "",
    ) -> list[dict]:
        """Build the messages array for the agent with conversation history."""
        history = self._conversation_history.get(client_id, [])
        history.append({"role": "user", "content": text})
        self._conversation_history[client_id] = history

        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        turn_count = len(history)
        mac_context = (mac_context or "").strip()
        screen_context = (screen_context or "").strip()
        mac_context_line = f"Contexto local do Mac: {mac_context}. " if mac_context else ""
        screen_context_line = (
            f"Contexto visual/OCR da tela atual, enviado pelo app nativo:\n{screen_context}\n"
            if screen_context
            else ""
        )
        system_message = {
            "role": "system",
            "content": (
                "Você é o Jarvis, assistente de voz pessoal do líder supremo. "
                "Está sendo acessado por interface de voz (STT/TTS) em português brasileiro. "
                f"{mac_context_line}"
                f"{screen_context_line}"
                "A mensagem do usuário pode ter vindo de reconhecimento de fala e conter palavras trocadas; "
                "quando houver ambiguidade real, confirme antes de agir. "
                f"Data/hora atual: {now}. Turno da conversa: {turn_count}. "
                "REGRAS: "
                "1) Respostas CONCISAS e diretas — serão lidas em voz alta via TTS. "
                "2) USE TODAS as suas ferramentas e acessos disponíveis para buscar informação REAL. "
                "3) Quando perguntado sobre status de casa, sensores, luzes, energia, infraestrutura — "
                "consulte seus recursos e retorne dados reais, NUNCA diga que não tem acesso. "
                "4) Evite listas longas, markdown, ou formatação — apenas texto falado natural. "
                "5) Não use emojis; eles atrapalham o TTS e a leitura em voz alta. "
                "6) Se a transcrição parecer incompleta ou sem sentido, peça para repetir em vez de adivinhar. "
                "7) Você tem memória da conversa — use o contexto anterior para entender referências "
                "como 'isso', 'aquilo', 'a mesma coisa', etc. "
                "8) Se precisar controlar a interface de voz, coloque APENAS na primeira linha um JSON compacto "
                "como {\"jarvisDirective\":{\"speak\":true,\"expectingReply\":false}} e depois responda normalmente. "
                "Use speak=false só quando a resposta não deve ser falada; use expectingReply=true quando você precisa "
                "que o Jarvis abra o microfone para confirmação. "
                "9) Se houver contexto visual/OCR, trate-o como a tela atual do usuário e use-o para responder "
                "perguntas como 'o que aparece aqui', 'leia isso', 'resuma esta tela' ou referências similares."
            ),
        }
        return [system_message] + history[-MAX_CONVERSATION_TURNS:]

    async def _agent_process_streaming(
        self,
        text: str,
        client_id: Hashable,
        mac_context: str = "",
        screen_context: str = "",
        agent_id: str | None = None,
    ):
        """Stream agent response, yielding complete sentences as they arrive."""
        if not text or not text.strip():
            yield "Não consegui entender. Pode repetir?"
            return

        if not OPENCLAW_TOKEN:
            yield "O agente OpenClaw não está configurado."
            return

        resolved_agent = _normalize_agent_id(agent_id)
        messages = self._build_agent_messages(
            text,
            client_id,
            mac_context=mac_context,
            screen_context=screen_context,
        )

        try:
            timeout = aiohttp.ClientTimeout(total=60)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                resp = await session.post(
                    f"{OPENCLAW_URL}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {OPENCLAW_TOKEN}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": f"openclaw/{resolved_agent}",
                        "messages": messages,
                        "stream": True,
                        "user": "jarvis-voice",
                    },
                )
                if resp.status != 200:
                    body = await resp.text()
                    logger.error(f"OpenClaw streaming error {resp.status}: {body[:200]}")
                    yield "Desculpe, não consegui processar. Tente novamente."
                    return

                buffer = ""
                full_response = ""
                async for line in resp.content:
                    line = line.decode("utf-8").strip()
                    if not line.startswith("data: "):
                        continue
                    data_str = line[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                        delta = data.get("choices", [{}])[0].get("delta", {})
                        content = delta.get("content", "")
                        if content:
                            buffer += content
                            full_response += content
                            # Try to extract complete sentences
                            sentences, buffer = self._split_sentences(buffer)
                            for sentence in sentences:
                                yield sentence
                    except (json.JSONDecodeError, IndexError, KeyError):
                        continue

                # Yield any remaining text in the buffer
                if buffer.strip():
                    yield buffer.strip()

                # Save full response to conversation history
                history = self._conversation_history.get(client_id, [])
                history.append({"role": "assistant", "content": full_response})
                if len(history) > MAX_CONVERSATION_TURNS * 2:
                    self._conversation_history[client_id] = history[-MAX_CONVERSATION_TURNS:]
                else:
                    self._conversation_history[client_id] = history
                logger.info(f"OpenClaw streamed response: '{full_response[:100]}...'")

        except asyncio.TimeoutError:
            logger.error("OpenClaw streaming request timed out")
            yield "O agente demorou muito para responder."
        except Exception as e:
            logger.error(f"OpenClaw streaming error: {e}")
            raise

    async def agent_process(
        self,
        text: str,
        client_id: Hashable,
        mac_context: str = "",
        screen_context: str = "",
        agent_id: str | None = None,
    ) -> str:
        """Send text to OpenClaw agent and return the response (non-streaming fallback)."""
        if not text or not text.strip():
            return "Não consegui entender. Pode repetir?"

        if not OPENCLAW_TOKEN:
            logger.warning("OPENCLAW_TOKEN not set, using fallback")
            return "O agente OpenClaw não está configurado. Verifique as variáveis de ambiente."

        resolved_agent = _normalize_agent_id(agent_id)
        messages = self._build_agent_messages(
            text,
            client_id,
            mac_context=mac_context,
            screen_context=screen_context,
        )
        logger.info(
            f"Sending to OpenClaw: {len(messages)} messages, "
            f"model=openclaw/{resolved_agent}, tokenSource={OPENCLAW_TOKEN_SOURCE}"
        )

        try:
            timeout = aiohttp.ClientTimeout(total=60)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                resp = await session.post(
                    f"{OPENCLAW_URL}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {OPENCLAW_TOKEN}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": f"openclaw/{resolved_agent}",
                        "messages": messages,
                        "user": "jarvis-voice",
                    },
                )
                logger.info(f"OpenClaw response status: {resp.status}")
                if resp.status != 200:
                    body = await resp.text()
                    logger.error(f"OpenClaw error {resp.status}: {body[:200]}")
                    if resp.status == 401:
                        return (
                            "O OpenClaw recusou a autenticação do Jarvis. "
                            "Verifique o token do gateway do OpenClaw."
                        )
                    return "Desculpe, não consegui processar. Tente novamente."

                data = await resp.json()
                content = data["choices"][0]["message"]["content"]
                logger.info(f"OpenClaw response: '{content[:100]}...'")

                # Append assistant response to conversation history
                history = self._conversation_history.get(client_id, [])
                history.append({"role": "assistant", "content": content})
                if len(history) > MAX_CONVERSATION_TURNS * 2:
                    self._conversation_history[client_id] = history[-MAX_CONVERSATION_TURNS:]
                else:
                    self._conversation_history[client_id] = history
                return content

        except asyncio.TimeoutError:
            logger.error("OpenClaw request timed out")
            return "O agente demorou muito para responder. Tente novamente."
        except Exception as e:
            logger.error(f"OpenClaw error: {e}")
            return "Erro ao comunicar com o agente. Tente novamente."


async def pregenerate_ack_phrases():
    """Pre-generate TTS audio for acknowledgment phrases at startup with retry."""
    max_retries = 3
    for attempt in range(max_retries):
        logger.info(f"Pre-generating acknowledgment phrases (attempt {attempt + 1}/{max_retries})...")
        success_count = 0
        for i, phrase in enumerate(ACK_PHRASES):
            if i in _ack_audio_cache:
                success_count += 1
                continue
            try:
                comm = edge_tts.Communicate(phrase, TTS_VOICE)
                data = bytearray()
                async for chunk in comm.stream():
                    if chunk["type"] == "audio":
                        data.extend(chunk["data"])
                _ack_audio_cache[i] = bytes(data)
                logger.info(f"  [{i}] '{phrase}' ({len(data)} bytes)")
                success_count += 1
            except Exception as e:
                logger.error(f"  [{i}] Failed: {e}")

        logger.info(f"Pre-generated {success_count}/{len(ACK_PHRASES)} phrases")
        if success_count == len(ACK_PHRASES):
            break
        if attempt < max_retries - 1:
            wait = 10 * (attempt + 1)
            logger.info(f"Retrying ack phrase generation in {wait}s...")
            await asyncio.sleep(wait)

    if not _ack_audio_cache:
        logger.warning("No ack phrases generated — TTS service may be down. Server will continue without voice acks.")


async def handle_ack_count(request: web.Request) -> web.Response:
    return web.json_response({"count": len(_ack_audio_cache)})


async def handle_ack_audio(request: web.Request) -> web.Response:
    idx = int(request.match_info['idx'])
    audio = _ack_audio_cache.get(idx)
    if not audio:
        return web.Response(status=404)
    return web.Response(body=audio, content_type='audio/mpeg')


async def handle_health(request: web.Request) -> web.Response:
    if not _is_authorized(request):
        raise web.HTTPUnauthorized(text="Unauthorized")
    selected_agent = _agent_from_request(request)
    return web.json_response({
        "status": "ok",
        "agent": selected_agent,
        "defaultAgent": OPENCLAW_AGENT,
        "openclawURL": OPENCLAW_URL,
        "hasOpenClawToken": bool(OPENCLAW_TOKEN),
        "openclawTokenSource": OPENCLAW_TOKEN_SOURCE,
        "ttsVoice": TTS_VOICE,
        "whisperModel": WHISPER_MODEL,
        "whisperBeamSize": WHISPER_BEAM_SIZE,
        "whisperVadMinSilenceMs": WHISPER_VAD_MIN_SILENCE_MS,
        "whisperNoSpeechThreshold": WHISPER_NO_SPEECH_THRESHOLD,
        "sttNormalizationEnabled": STT_NORMALIZATION_ENABLED,
    })


def create_app() -> web.Application:
    app = web.Application()
    static_path = Path(__file__).parent / "static"
    app.router.add_get("/app.js", handle_static_file(static_path / "app.js"))
    app.router.add_get("/favicon.ico", handle_favicon)
    app.router.add_get("/api/health", handle_health)
    app.router.add_get("/ack/count", handle_ack_count)
    app.router.add_get("/ack/{idx}", handle_ack_audio)
    ws_handler = WebSocketHandler()
    app.router.add_get("/ws", ws_handler.handle_connection)
    app.router.add_post("/api/voice", ws_handler.handle_voice_request)
    app.router.add_post("/api/text", ws_handler.handle_text_request)
    app.router.add_post("/api/text/stream", ws_handler.handle_text_stream_request)
    app.router.add_post("/api/transcribe", ws_handler.handle_transcribe_request)
    app.router.add_get("/", handle_root)
    app.on_startup.append(lambda _: pregenerate_ack_phrases())
    return app


def handle_static_file(filepath: Path):
    async def handler(request: web.Request) -> web.Response:
        if filepath.exists():
            ct = "application/javascript" if filepath.suffix == ".js" else "text/plain"
            return web.Response(text=filepath.read_text(), content_type=ct)
        return web.Response(text="Not found", status=404)
    return handler


async def handle_favicon(request: web.Request) -> web.Response:
    return web.Response(status=204)


async def handle_root(request: web.Request) -> web.Response:
    html = Path(__file__).parent / "static" / "index.html"
    if html.exists():
        return web.Response(text=html.read_text(), content_type="text/html")
    return web.Response(text="Jarvis Voice Server", content_type="text/plain")


if __name__ == "__main__":
    import ssl
    app = create_app()
    cert_path = os.path.join(os.path.dirname(__file__), "server.crt")
    key_path = os.path.join(os.path.dirname(__file__), "server.key")
    if os.path.exists(cert_path) and os.path.exists(key_path):
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(cert_path, key_path)
    else:
        ssl_context = None
    web.run_app(app, host=HOST_IP, port=HOST_PORT, ssl_context=ssl_context, print=lambda m: logger.info(m))
