import mysql.connector
from mysql.connector import Error
from flask import current_app
from werkzeug.security import check_password_hash, generate_password_hash
from datetime import datetime
import hashlib
import os
from flask_login import UserMixin


def get_db_connection():
    try:
        return mysql.connector.connect(**current_app.config['DB_CONFIG'])
    except Error as e:
        print(f"Error de conexion: {e}")
        raise


class UsuarioLogin(UserMixin):
    def __init__(self, user_data):
        self.id = user_data['id_usuario']
        self.username = user_data['username']
        self.email = user_data.get('email', '')
        self.rol = user_data['rol']
        self.active = user_data.get('activo', 1) == 1
        self.intentos_fallidos = user_data.get('intentos_fallidos', 0)
        self.bloqueado_hasta = user_data.get('bloqueado_hasta')
    
    @property
    def is_active(self):
        return self.active
    
    @property
    def is_authenticated(self):
        return True
    
    @property
    def is_anonymous(self):
        return False
    
    def get_id(self):
        return str(self.id)


def autenticar_usuario(username, password):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM usuario_sistema WHERE username = %s", (username,))
        user = cursor.fetchone()
        
        if not user:
            return None, "Usuario no encontrado"
        
        if not user['activo']:
            return None, "Usuario desactivado"
        
        if user['bloqueado_hasta'] and user['bloqueado_hasta'] > datetime.now():
            return None, "Cuenta bloqueada"
        
        autenticado = False
        
        try:
            cursor.execute("SELECT SHA2(%s, 256) AS hash_calculado", (password,))
            sha2_hash = cursor.fetchone()
            if sha2_hash and user['password_hash'] == sha2_hash['hash_calculado']:
                autenticado = True
        except:
            pass
        
        if not autenticado and check_password_hash(user['password_hash'], password):
            autenticado = True
        
        if autenticado:
            cursor.execute("""
                UPDATE usuario_sistema 
                SET intentos_fallidos = 0, ultimo_login = NOW() 
                WHERE id_usuario = %s
            """, (user['id_usuario'],))
            conn.commit()
            return UsuarioLogin(user), "OK"
        else:
            new_att = user['intentos_fallidos'] + 1
            if new_att >= 5:
                cursor.execute("""
                    UPDATE usuario_sistema 
                    SET intentos_fallidos = %s, bloqueado_hasta = DATE_ADD(NOW(), INTERVAL 30 MINUTE) 
                    WHERE id_usuario = %s
                """, (new_att, user['id_usuario']))
            else:
                cursor.execute("""
                    UPDATE usuario_sistema 
                    SET intentos_fallidos = %s 
                    WHERE id_usuario = %s
                """, (new_att, user['id_usuario']))
            conn.commit()
            return None, "Contraseña incorrecta"
    finally:
        cursor.close()
        conn.close()


def get_user_by_id(user_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM usuario_sistema WHERE id_usuario = %s", (user_id,))
        user_data = cursor.fetchone()
        if user_data:
            return UsuarioLogin(user_data)
        return None
    finally:
        cursor.close()
        conn.close()


def get_usuarios():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT id_usuario, username, email, rol, activo, ultimo_login, 
                   intentos_fallidos, fecha_creacion 
            FROM usuario_sistema 
            ORDER BY fecha_creacion DESC
        """)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def crear_usuario(username, password, email, rol, id_empleado=None):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        ph = generate_password_hash(password, method='pbkdf2:sha256', salt_length=16)
        cursor.execute("""
            INSERT INTO usuario_sistema (username, password_hash, email, rol, id_empleado_relacionado) 
            VALUES (%s, %s, %s, %s, %s)
        """, (username, ph, email, rol, id_empleado))
        conn.commit()
        return cursor.lastrowid
    except Error as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()


def cambiar_estado_usuario(id_usuario, activo):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE usuario_sistema SET activo = %s WHERE id_usuario = %s", (activo, id_usuario))
        conn.commit()
    finally:
        cursor.close()
        conn.close()


def registrar_log_acceso(username, resultado, ip_origen):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO log_accesos (username, resultado, ip_origen) 
            VALUES (%s, %s, %s)
        """, (username, resultado, ip_origen))
        conn.commit()
    except:
        pass
    finally:
        cursor.close()
        conn.close()


def get_logs_acceso(limit=100):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT * FROM log_accesos 
            ORDER BY fecha_hora DESC 
            LIMIT %s
        """, (limit,))
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_auditoria_cambios(limit=100):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT * FROM auditoria_cambios 
            ORDER BY fecha_hora DESC 
            LIMIT %s
        """, (limit,))
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_metricas_dashboard():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        metricas = {}
        
        cursor.execute("SELECT COUNT(*) AS t FROM producto WHERE activo = 1")
        metricas['total_productos'] = cursor.fetchone()['t']
        
        cursor.execute("SELECT COUNT(*) AS t FROM lote_produccion WHERE control_calidad = 'Aprobado'")
        metricas['total_lotes'] = cursor.fetchone()['t']
        
        cursor.execute("SELECT COUNT(*) AS t FROM distribuidor WHERE activo = 1")
        metricas['total_distribuidores'] = cursor.fetchone()['t']
        
        cursor.execute("SELECT COUNT(*) AS t FROM pedido WHERE estado = 'Pendiente'")
        metricas['pedidos_pendientes'] = cursor.fetchone()['t']
        
        cursor.execute("SELECT COALESCE(SUM(cantidad_actual), 0) AS t FROM inventario_bodega")
        metricas['stock_total'] = cursor.fetchone()['t']
        
        cursor.execute("""
            SELECT COUNT(DISTINCT l.id_lote) AS t 
            FROM lote_produccion l 
            JOIN inventario_bodega ib ON l.id_lote = ib.id_lote 
            WHERE l.fecha_vencimiento BETWEEN CURDATE() AND CURDATE() + INTERVAL 30 DAY 
              AND l.control_calidad = 'Aprobado' 
              AND ib.cantidad_actual > 0
        """)
        metricas['proximos_vencer'] = cursor.fetchone()['t']
        
        cursor.execute("""
            SELECT COALESCE(SUM(monto_total), 0) AS t 
            FROM pedido 
            WHERE estado = 'Entregado' 
              AND MONTH(fecha_pedido) = MONTH(CURDATE()) 
              AND YEAR(fecha_pedido) = YEAR(CURDATE())
        """)
        metricas['ventas_mes'] = cursor.fetchone()['t']
        
        return metricas
    finally:
        cursor.close()
        conn.close()


def get_stock_por_planta():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT pl.nombre AS planta, SUM(ib.cantidad_actual) AS stock 
            FROM planta pl 
            JOIN bodega b ON pl.id_planta = b.id_planta 
            JOIN inventario_bodega ib ON b.id_bodega = ib.id_bodega 
            GROUP BY pl.id_planta, pl.nombre
        """)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_pedidos_por_estado():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT estado, COUNT(*) AS cantidad FROM pedido GROUP BY estado")
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_productos(activo=None, tipo=None, busqueda=None):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        query = "SELECT * FROM producto WHERE 1=1"
        params = []
        
        if activo is not None:
            query += " AND activo = %s"
            params.append(activo)
        
        if tipo:
            query += " AND tipo = %s"
            params.append(tipo)
        
        if busqueda:
            query += " AND (nombre_comercial LIKE %s OR codigo_unico LIKE %s)"
            params.extend([f"%{busqueda}%", f"%{busqueda}%"])
        
        query += " ORDER BY nombre_comercial"
        cursor.execute(query, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_producto_by_id(id_producto):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM producto WHERE id_producto = %s", (id_producto,))
        return cursor.fetchone()
    finally:
        cursor.close()
        conn.close()


def crear_producto(codigo, nombre, tipo, presentacion, graduacion, precio, stock_min, stock_max):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO producto (codigo_unico, nombre_comercial, tipo, presentacion, 
                                  graduacion_alcoholica, precio_actual, stock_minimo, stock_maximo) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (codigo, nombre, tipo, presentacion, graduacion, precio, stock_min, stock_max))
        conn.commit()
        return cursor.lastrowid
    except Error as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()


def actualizar_producto(id_producto, **kwargs):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        campos = [f"{k} = %s" for k in kwargs]
        valores = list(kwargs.values()) + [id_producto]
        cursor.execute(f"UPDATE producto SET {', '.join(campos)} WHERE id_producto = %s", valores)
        conn.commit()
    finally:
        cursor.close()
        conn.close()


def get_lotes(producto_id=None, planta_id=None, calidad=None, proximos_vencer=False):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT l.*, p.nombre_comercial, p.presentacion, pl.nombre AS planta_nombre
            FROM lote_produccion l 
            JOIN producto p ON l.id_producto = p.id_producto
            JOIN planta pl ON l.id_planta = pl.id_planta 
            WHERE 1=1
        """
        params = []
        
        if producto_id:
            query += " AND l.id_producto = %s"
            params.append(producto_id)
        
        if planta_id:
            query += " AND l.id_planta = %s"
            params.append(planta_id)
        
        if calidad:
            query += " AND l.control_calidad = %s"
            params.append(calidad)
        
        if proximos_vencer:
            query += " AND l.fecha_vencimiento BETWEEN CURDATE() AND CURDATE() + INTERVAL 30 DAY"
        
        query += " ORDER BY l.fecha_produccion DESC"
        cursor.execute(query, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_lote_by_id(id_lote):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT l.*, p.nombre_comercial, p.presentacion, pl.nombre AS planta_nombre
            FROM lote_produccion l 
            JOIN producto p ON l.id_producto = p.id_producto
            JOIN planta pl ON l.id_planta = pl.id_planta 
            WHERE l.id_lote = %s
        """, (id_lote,))
        return cursor.fetchone()
    finally:
        cursor.close()
        conn.close()


def get_distribuidores(activo=None, ciudad=None, busqueda=None):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        query = "SELECT * FROM distribuidor WHERE 1=1"
        params = []
        
        if activo is not None:
            query += " AND activo = %s"
            params.append(activo)
        
        if ciudad:
            query += " AND ciudad = %s"
            params.append(ciudad)
        
        if busqueda:
            query += " AND (razon_social LIKE %s OR nit LIKE %s OR contacto_nombre LIKE %s)"
            params.extend([f"%{busqueda}%", f"%{busqueda}%", f"%{busqueda}%"])
        
        query += " ORDER BY razon_social"
        cursor.execute(query, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_distribuidor_by_id(id_distribuidor):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM distribuidor WHERE id_distribuidor = %s", (id_distribuidor,))
        return cursor.fetchone()
    finally:
        cursor.close()
        conn.close()


def crear_distribuidor(nit, razon_social, direccion, ciudad, zona, contacto, telefono, correo):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO distribuidor (nit, razon_social, direccion, ciudad, zona, 
                                      contacto_nombre, telefono, correo) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (nit, razon_social, direccion, ciudad, zona, contacto, telefono, correo))
        conn.commit()
        return cursor.lastrowid
    except Error as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()


def get_pedidos(estado=None, distribuidor_id=None, fecha_desde=None, fecha_hasta=None):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT p.*, d.razon_social AS distribuidor_nombre, d.ciudad
            FROM pedido p 
            JOIN distribuidor d ON p.id_distribuidor = d.id_distribuidor 
            WHERE 1=1
        """
        params = []
        
        if estado:
            query += " AND p.estado = %s"
            params.append(estado)
        
        if distribuidor_id:
            query += " AND p.id_distribuidor = %s"
            params.append(distribuidor_id)
        
        if fecha_desde:
            query += " AND p.fecha_pedido >= %s"
            params.append(fecha_desde)
        
        if fecha_hasta:
            query += " AND p.fecha_pedido <= %s"
            params.append(fecha_hasta)
        
        query += " ORDER BY p.fecha_pedido DESC"
        cursor.execute(query, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_pedido_by_id(id_pedido):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT p.*, d.razon_social AS distribuidor_nombre, d.nit, d.direccion, d.telefono
            FROM pedido p 
            JOIN distribuidor d ON p.id_distribuidor = d.id_distribuidor 
            WHERE p.id_pedido = %s
        """, (id_pedido,))
        pedido = cursor.fetchone()
        
        if pedido:
            cursor.execute("""
                SELECT dp.*, pr.nombre_comercial, pr.presentacion, pr.codigo_unico
                FROM detalle_pedido dp 
                JOIN producto pr ON dp.id_producto = pr.id_producto 
                WHERE dp.id_pedido = %s
            """, (id_pedido,))
            pedido['detalles'] = cursor.fetchall()
        
        return pedido
    finally:
        cursor.close()
        conn.close()


def crear_pedido(id_distribuidor, fecha_entrega, productos, observaciones=None):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO pedido (id_distribuidor, fecha_pedido, fecha_entrega_requerida, estado, observaciones)
            VALUES (%s, CURDATE(), %s, 'Pendiente', %s)
        """, (id_distribuidor, fecha_entrega, observaciones))
        
        id_pedido = cursor.lastrowid
        monto_total = 0
        
        for prod in productos:
            cursor.execute("""
                INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario) 
                VALUES (%s, %s, %s, %s)
            """, (id_pedido, prod['id_producto'], prod['cantidad'], prod['precio_unitario']))
            monto_total += prod['cantidad'] * prod['precio_unitario']
        
        cursor.execute("UPDATE pedido SET monto_total = %s WHERE id_pedido = %s", (monto_total, id_pedido))
        conn.commit()
        return id_pedido
    except Error as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()


def cambiar_estado_pedido(id_pedido, nuevo_estado):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE pedido SET estado = %s WHERE id_pedido = %s", (nuevo_estado, id_pedido))
        conn.commit()
    finally:
        cursor.close()
        conn.close()


def get_inventario_bodegas(bodega_id=None, producto_id=None):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT ib.*, l.numero_lote, p.nombre_comercial, p.presentacion,
                   b.nombre_bodega, pl.nombre AS planta_nombre 
            FROM inventario_bodega ib
            JOIN lote_produccion l ON ib.id_lote = l.id_lote 
            JOIN producto p ON l.id_producto = p.id_producto
            JOIN bodega b ON ib.id_bodega = b.id_bodega 
            JOIN planta pl ON b.id_planta = pl.id_planta
            WHERE ib.cantidad_actual > 0
        """
        params = []
        
        if bodega_id:
            query += " AND ib.id_bodega = %s"
            params.append(bodega_id)
        
        if producto_id:
            query += " AND l.id_producto = %s"
            params.append(producto_id)
        
        query += " ORDER BY pl.nombre, b.nombre_bodega, p.nombre_comercial"
        cursor.execute(query, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_bodegas():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT b.*, p.nombre AS planta_nombre 
            FROM bodega b 
            JOIN planta p ON b.id_planta = p.id_planta 
            ORDER BY p.nombre, b.nombre_bodega
        """)
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_plantas():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM planta WHERE activo = 1 ORDER BY nombre")
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_vista_stock_consolidado():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM vista_stock_consolidado ORDER BY estado_stock DESC, nombre_comercial")
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_vista_proximos_vencer():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM vista_proximos_vencer ORDER BY dias_restantes ASC")
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_vista_rotacion_inventario():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM vista_rotacion_inventario ORDER BY salidas_30dias DESC")
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def get_conexiones_activas():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, INFO 
            FROM information_schema.PROCESSLIST 
            WHERE USER != 'system user' AND COMMAND != 'Sleep' 
            ORDER BY TIME DESC
        """)
        return cursor.fetchall()
    except:
        return []
    finally:
        cursor.close()
        conn.close()


def get_estadisticas_tablas():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH,
                   ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb 
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = %s 
            ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
        """, (current_app.config['DB_CONFIG']['database'],))
        return cursor.fetchall()
    except:
        return []
    finally:
        cursor.close()
        conn.close()


def get_consultas_lentas():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SHOW VARIABLES LIKE 'slow_query_log'")
        slow = cursor.fetchone()
        
        if slow and slow['Value'] == 'ON':
            cursor.execute("""
                SELECT DIGEST_TEXT AS query, COUNT_STAR AS exec_count,
                       AVG_TIMER_WAIT / 1000000000 AS avg_time_ms, 
                       MAX_TIMER_WAIT / 1000000000 AS max_time_ms
                FROM performance_schema.events_statements_summary_by_digest
                WHERE AVG_TIMER_WAIT / 1000000000 > %s 
                ORDER BY AVG_TIMER_WAIT DESC 
                LIMIT 20
            """, (current_app.config.get('SLOW_QUERY_TIME', 2) * 1000,))
            return cursor.fetchall()
        return []
    except:
        return []
    finally:
        cursor.close()
        conn.close()


def get_backups_existentes():
    backup_dir = current_app.config.get('BACKUP_DIR', './backups/')
    
    if not os.path.exists(backup_dir):
        return []
    
    backups = []
    for f in os.listdir(backup_dir):
        if f.endswith('.sql'):
            fp = os.path.join(backup_dir, f)
            st = os.stat(fp)
            backups.append({
                'nombre': f, 
                'tamano_mb': round(st.st_size / 1024 / 1024, 2),
                'fecha_creacion': datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
            })
    
    return sorted(backups, key=lambda x: x['fecha_creacion'], reverse=True)