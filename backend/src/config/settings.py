import os

from dotenv import load_dotenv
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load .env into os.environ FIRST — before pydantic-settings instantiates and
# before Firebase / AWS SDK initialise. override=True means .env wins over
# any stale system-level env vars (e.g. a system ENV=production you may have
# set previously). Safe to call multiple times; subsequent calls are no-ops.
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", "..", ".env"),
            override=True)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # Environment
    ENV: str = "development"

    # AWS / Bedrock
    AWS_REGION: str = "us-east-1"
    BEDROCK_SONIC_MODEL_ID: str = "us.amazon.nova-2-sonic-v1:0"
    BEDROCK_SONIC_VOICE: str = "matthew"

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

    # Chat history — number of prior turns forwarded to Claude for context.
    # 10 messages ≈ 1k tokens per request. Tune via env var CHAT_HISTORY_WINDOW.
    CHAT_HISTORY_WINDOW: int = 10

    # Juno personality
    JUNO_DEFAULT_SYSTEM_PROMPT: str = (
        "You are Juno, a proactive personal assistant that helps with reminders, "
        "scheduling, memory, and nutrition. Be warm, brief, and conversational. "
        "Never use emojis in your responses."
    )

    @field_validator("VOICE_GATEWAY_TEMPERATURE", "VOICE_GATEWAY_TOP_P")
    @classmethod
    def clamp_0_1(cls, v: float) -> float:
        return max(0.0, min(1.0, v))

    @property
    def is_production(self) -> bool:
        return self.ENV == "production"

    @property
    def google_calendar_configured(self) -> bool:
        return bool(self.GOOGLE_CLIENT_ID and self.GOOGLE_CLIENT_SECRET)

    @property
    def gemini_configured(self) -> bool:
        return bool(self.GEMINI_API_KEY)


settings = Settings()
