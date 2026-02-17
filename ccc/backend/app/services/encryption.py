"""
Encryption service for sensitive credentials.
Uses Fernet symmetric encryption with key from ENV.
"""

from typing import Optional
from cryptography.fernet import Fernet
from app.config import get_settings

_fernet: Optional[Fernet] = None


def _get_fernet() -> Fernet:
    """Get or initialize the Fernet cipher with encryption key from ENV."""
    global _fernet
    if _fernet is None:
        settings = get_settings()
        key = settings.encryption_key
        if not key:
            raise ValueError(
                "ENCRYPTION_KEY not set in environment. "
                "Generate one with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
            )
        _fernet = Fernet(key.encode())
    return _fernet


def encrypt(plaintext: str) -> str:
    """
    Encrypt plaintext and return base64-encoded ciphertext.
    Returns empty string if plaintext is empty.
    """
    if not plaintext:
        return ""
    return _get_fernet().encrypt(plaintext.encode()).decode()


def decrypt(ciphertext: str) -> str:
    """
    Decrypt base64-encoded ciphertext and return plaintext.
    Returns empty string if ciphertext is empty.
    """
    if not ciphertext:
        return ""
    return _get_fernet().decrypt(ciphertext.encode()).decode()
