#  Pil Andina - Sistema de Gestion de Inventario y Distribucion

**Base de Datos 2  Hito 3 y 4  Proyecto Grupal**

Sistema integral de gestion de inventario y distribucion para Cerveceria Boliviana (Pil Andina), desarrollado con Flask + MySQL.

##  Requisitos

- Python 3.10+
- MySQL 8.0+ / MariaDB 10.4+
- pip

##  Instalacion Rapida

1. **Clonar o descomprimir el proyecto:**
   ```bash
   cd pil_andina_app
   ```

2. **Crear entorno virtual:**
   ```bash
   python -m venv venv
   # Windows: venv\Scripts\activate
   # Linux/Mac: source venv/bin/activate
   ```

3. **Instalar dependencias:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Configurar base de datos:**
   ```bash
   # Crear archivo .env basado en .env.example
   cp .env.example .env
   # Editar .env con tus credenciales MySQL
   ```

5. **Importar base de datos:**
   ```bash
   mysql -u root -p < database/pil_andina_db.sql
   ```

6. **Ejecutar la aplicacion:**
   ```bash
   python run.py
   ```

7. **Acceder:**
   - URL: http://localhost:5000
   - Usuarios demo:
Administrador	admin_pil	AdminPil2026!

Gerente	gerente_lp	GerenteLP2026!

Distribuidor	dist_la_paz	Dist123!

## 🏗️ Estructura del Proyecto

```
pil_andina_app/
├── app/
│   ├── __init__.py          # Factory de Flask
│   ├── config.py            # Configuracion
│   ├── models.py            # DAO / Acceso a datos
│   ├── routes/
│   │   ├── auth.py          # Login/logout
│   │   ├── admin.py         # Panel admin (usuarios, auditoria, backups, monitoreo)
│   │   ├── gerente.py       # Panel gerente (productos, inventario, lotes, pedidos, reportes)
│   │   ├── distribuidor.py  # Panel distribuidor (pedidos, nuevo pedido)
│   │   ├── dashboard.py     # Dashboard general
│   │   └── api.py           # API REST para AJAX
│   ├── templates/           # Jinja2 HTML
│   └── static/css/          # Estilos
├── database/
│   └── pil_andina_db.sql    # Script SQL completo
├── requirements.txt
├── .env.example
└── run.py
```

##  Roles y Permisos

| Rol | Permisos |
|-----|----------|
| **Administrador** | Gestion de usuarios, auditoria, monitoreo de BD, backups, exportacion CSV/Excel |
| **Gerente** | Catalogo de productos, inventario por bodega, lotes, pedidos, reportes (stock, vencimiento, rotacion) |
| **Distribuidor** | Ver sus pedidos, crear nuevos pedidos |

##  Seguridad
- Contrasenas con hash PBKDF2-SHA256
- Proteccion contra SQL Injection (placeholders)
- Logs de acceso y auditoria de cambios
- Bloqueo por intentos fallidos (5 intentos = 30 min)
- Control de sesiones por rol

##  Reportes Incluidos

- Stock consolidado por planta (vista `vista_stock_consolidado`)
- Productos proximos a vencer 30 dias (vista `vista_proximos_vencer`)
- Rotacion de inventario ultimos 30 dias (vista `vista_rotacion_inventario`)
- Exportacion a CSV y Excel

##  Backups

El panel de administracion permite generar backups completos usando `mysqldump` con descarga directa.

##  Monitoreo

- Conexiones activas a MySQL
- Estadisticas de tablas (tamano, filas)
- Consultas lentas (performance_schema)

---
**Desarrollado para:** Base de Datos 2 - Hito 3 y 4
**Empresa:** Pil Andina (Cerveceria Boliviana)
