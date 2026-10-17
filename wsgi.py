"""Production WSGI entry point used by Railway/Gunicorn."""

from app import app, initialize_persistent_users


initialize_persistent_users()

