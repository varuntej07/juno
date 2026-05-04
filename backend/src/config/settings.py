import os

from dotenv import load_dotenv
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load .env into os.environ FIRST before pydantic-settings instantiates.
# Safe to call multiple times; subsequent calls are no-ops.
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", "..", ".env"), override=True)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # Environment
    ENV: str = "development"

    # LiveKit
    LIVEKIT_URL: str = ""
    LIVEKIT_API_KEY: str = ""
    LIVEKIT_API_SECRET: str = ""

    # Deepgram STT
    DEEPGRAM_API_KEY: str = ""

    # Cartesia TTS
    CARTESIA_API_KEY: str = ""

    # Voice agent timeouts
    VOICE_TOOL_TIMEOUT_S: float = 5.0      # per-tool Firestore call budget
    VOICE_CONNECT_TIMEOUT_S: float = 10.0  # LiveKit room.connect() budget

    # Voice gateway
    VOICE_GATEWAY_PORT: int = 8000
    VOICE_GATEWAY_HOST: str = "0.0.0.0"
    VOICE_GATEWAY_SAMPLE_RATE_HZ: int = 16000
    VOICE_GATEWAY_INPUT_MAX_TOKENS: int = 1024
    VOICE_GATEWAY_TEMPERATURE: float = 0.7
    VOICE_GATEWAY_TOP_P: float = 0.9

    # Anthropic
    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_MODEL: str = "claude-sonnet-4-6"
    ANTHROPIC_MAX_TOKENS: int = 1024

    # Google Calendar (optional)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = ""
    GOOGLE_CALENDAR_WEBHOOK_URL: str = ""
    GOOGLE_CALENDAR_WATCH_TTL_SECONDS: int = 604800
    GOOGLE_CALENDAR_CHANNEL_RENEWAL_LEAD_SECONDS: int = 21600
    CALENDAR_SYNC_STALE_MINUTES: int = 5

    # Gemini API (nutrition VLM)
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.5-flash"
    NUTRITION_SCAN_CONFIDENCE_THRESHOLD: float = 0.85

    # Model tiers
    #   TIER_FAST -> background tasks, notification copy gen, simple classification
    #   TIER_BALANCED -> tool-calling tasks that need reasoning but not top-tier quality
    #   TIER_SMART -> main chat, complex multi-turn reasoning (most expensive)
    # Provider is inferred from the model ID prefix by ModelProvider.
    TIER_FAST: str = "gemini-2.5-flash"
    TIER_BALANCED: str = "claude-haiku-4-5-20251001"
    TIER_SMART: str = "claude-sonnet-4-6"

    # Cloud Scheduler / Cloud Tasks -> service account for internal endpoints
    SCHEDULER_SA_EMAIL: str = "juno-scheduler@juno-2ea45.iam.gserviceaccount.com"

    # Cloud Tasks -> engagement notification queue
    CLOUD_TASKS_PROJECT: str = "juno-2ea45"
    CLOUD_TASKS_LOCATION: str = "us-central1"
    CLOUD_TASKS_QUEUE: str = "juno-engagement"
    # The URL Cloud Tasks will POST to. Must match the deployed Cloud Run URL.
    BACKEND_INTERNAL_URL: str = "https://juno-backend-620715294422.us-central1.run.app"

    # Chat history — number of prior turns forwarded to Claude for context.
    # 10 messages ≈ 1k tokens per request. Tune via env var CHAT_HISTORY_WINDOW.
    CHAT_HISTORY_WINDOW: int = 10

    # LangSmith tracing
    LANGSMITH_TRACING: str = "false"
    LANGSMITH_API_KEY: str = ""
    LANGSMITH_PROJECT: str = "Buddy"
    LANGSMITH_ENDPOINT: str = "https://api.smith.langchain.com"

    # Juno personality — text chat
    JUNO_DEFAULT_SYSTEM_PROMPT: str = (
        "You are a friendly buddy, a proactive personal assistant that helps with reminders, "
        "scheduling, memory, and nutrition. Be warm, brief, and conversational. "
        "Never use emojis in your responses. "
        "Never use em dashes (—), en dashes (–), or double hyphens (--) anywhere in your responses. "
        "If a thought needs connecting, rewrite the sentence so it flows naturally without them. "
        "Before every tool call, write one short sentence (under 12 words) describing exactly what you are about to do. "
        "Do not use filler phrases like 'Let me' or 'I will'. Be specific to the request."
    )

    # Voice persona — casual, punchy, friend-mode
    VOICE_PROMPT: str = (
        "You're the user's best friend 'Buddy', living in their phone. "
        "Talk like you're texting a close mate, casual, punchy, zero corporate fluff. "
        "Swear freely when it fits the vibe. Never say 'certainly', 'of course', or 'I'd be happy to'. "
        "Be direct, get shit done, and make it fun. Keep responses short, this is a voice call, not an essay."
    )

    @field_validator("VOICE_GATEWAY_TEMPERATURE", "VOICE_GATEWAY_TOP_P")
    @classmethod
    def clamp_0_1(cls, v: float) -> float:
        return max(0.0, min(1.0, v))

    @property
    def is_production(self) -> bool:
        return self.ENV == "production"

    @property
    def livekit_configured(self) -> bool:
        return bool(self.LIVEKIT_URL and self.LIVEKIT_API_KEY and self.LIVEKIT_API_SECRET)

    @property
    def google_calendar_configured(self) -> bool:
        return bool(self.GOOGLE_CLIENT_ID and self.GOOGLE_CLIENT_SECRET)

    @property
    def gemini_configured(self) -> bool:
        return bool(self.GEMINI_API_KEY)


settings = Settings()
