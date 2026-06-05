import mysql.connector
import os
from dotenv import load_dotenv

load_dotenv()

print("=== DIAGNÓSTICO DE CONEXIÓN ===\n")

config = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'user': os.getenv('DB_USER', 'root'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'pil_andina_db'),
    'port': int(os.getenv('DB_PORT', 3306))
}

print(f"Host: {config['host']}")
print(f"User: {config['user']}")
print(f"Password: {'[VACÍA]' if config['password'] == '' else '[CONTRASEÑA CONFIGURADA]'}")
print(f"Database: {config['database']}")
print(f"Port: {config['port']}")

try:
    conn = mysql.connector.connect(**config)
    print("\n✅ CONEXIÓN EXITOSA a la base de datos")
    
    cursor = conn.cursor()
    cursor.execute("SELECT username, rol FROM usuario_sistema")
    print("\n📋 Usuarios en BD:")
    for row in cursor.fetchall():
        print(f"   - {row[0]}: {row[1]}")
    
    cursor.close()
    conn.close()
    
except mysql.connector.Error as e:
    print(f"\n❌ ERROR DE CONEXIÓN: {e}")