import os
from dotenv import load_dotenv
load_dotenv()

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'pil-andina-secret-dev-key-2026'
    DB_CONFIG = {
        'host': os.environ.get('DB_HOST', 'localhost'),
        'port': int(os.environ.get('DB_PORT', 3306)),
        'user': os.environ.get('DB_USER', 'root'),
        'password': os.environ.get('DB_PASSWORD', ''),
        'database': os.environ.get('DB_NAME', 'pil_andina_db'),
        'raise_on_warnings': True,
        'autocommit': False,
        'charset': 'utf8mb4',
        'collation': 'utf8mb4_unicode_ci'
    }
    BACKUP_DIR = os.environ.get('BACKUP_DIR', './backups/')
    BACKUP_RETENTION_DAYS = int(os.environ.get('BACKUP_RETENTION_DAYS', 30))
    LOG_SLOW_QUERIES = os.environ.get('LOG_SLOW_QUERIES', '1') == '1'
    SLOW_QUERY_TIME = float(os.environ.get('SLOW_QUERY_TIME', 2.0))
