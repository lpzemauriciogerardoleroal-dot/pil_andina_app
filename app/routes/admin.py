from flask import Blueprint, render_template, request, send_file, flash, redirect, url_for, session, Response
import subprocess, os
from datetime import datetime
from flask_login import login_required
from app.routes.auth import requiere_rol
from app.models import (get_usuarios, crear_usuario, cambiar_estado_usuario, get_logs_acceso,
    get_auditoria_cambios, get_conexiones_activas, get_estadisticas_tablas, get_consultas_lentas,
    get_backups_existentes, get_productos, get_distribuidores, get_pedidos, get_vista_stock_consolidado,
    get_vista_proximos_vencer, get_vista_rotacion_inventario)
from app.config import Config

bp = Blueprint('admin', __name__, url_prefix='/admin')

@bp.route('/dashboard')
@login_required
@requiere_rol('Administrador')
def dashboard():
    return render_template('admin/dashboard.html')

@bp.route('/usuarios')
@login_required
@requiere_rol('Administrador')
def usuarios():
    return render_template('admin/usuarios.html', usuarios=get_usuarios())

@bp.route('/usuarios/crear', methods=['POST'])
@login_required
@requiere_rol('Administrador')
def crear_usuario_route():
    try:
        crear_usuario(request.form['username'], request.form['password'], 
                     request.form['email'], request.form['rol'])
        flash('Usuario creado exitosamente.', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'danger')
    return redirect(url_for('admin.usuarios'))

@bp.route('/usuarios/toggle/<int:id_usuario>')
@login_required
@requiere_rol('Administrador')
def toggle_usuario(id_usuario):
    cambiar_estado_usuario(id_usuario, request.args.get('activo', type=int))
    flash('Estado actualizado.', 'success')
    return redirect(url_for('admin.usuarios'))

@bp.route('/auditoria')
@login_required
@requiere_rol('Administrador')
def auditoria():
    return render_template('admin/auditoria.html', logs=get_logs_acceso(100), cambios=get_auditoria_cambios(100))

@bp.route('/monitoreo')
@login_required
@requiere_rol('Administrador')
def monitoreo():
    return render_template('admin/monitoreo.html', conexiones=get_conexiones_activas(), 
                          estadisticas=get_estadisticas_tablas(), lentas=get_consultas_lentas())

@bp.route('/reportes/stock')
@login_required
@requiere_rol('Administrador')
def reporte_stock():
    return render_template('admin/reporte_stock.html', datos=get_vista_stock_consolidado())

@bp.route('/reportes/vencer')
@login_required
@requiere_rol('Administrador')
def reporte_vencer():
    return render_template('admin/reporte_vencer.html', datos=get_vista_proximos_vencer())

@bp.route('/reportes/rotacion')
@login_required
@requiere_rol('Administrador')
def reporte_rotacion():
    return render_template('admin/reporte_rotacion.html', datos=get_vista_rotacion_inventario())

@bp.route('/backups')
@login_required
@requiere_rol('Administrador')
def backups():
    return render_template('admin/backups.html', backups=get_backups_existentes())

@bp.route('/backups/crear', methods=['POST'])
@login_required
@requiere_rol('Administrador')
def crear_backup():
    try:
        fecha = datetime.now().strftime('%Y%m%d_%H%M%S')
        archivo = f"backup_pil_andina_{fecha}.sql"
        backup_dir = Config.BACKUP_DIR; os.makedirs(backup_dir, exist_ok=True)
        ruta = os.path.join(backup_dir, archivo)
        db = Config.DB_CONFIG
        cmd = ['mysqldump', '-h', db['host'], '-u', db['user'], f"--password={db['password']}",
               '--single-transaction', '--routines', '--triggers', db['database']]
        with open(ruta, 'w', encoding='utf-8') as f:
            res = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            flash(f'Backup generado: {archivo}', 'success')
            return send_file(ruta, as_attachment=True, download_name=archivo)
        else:
            flash(f'Error: {res.stderr}', 'danger')
    except Exception as e:
        flash(f'Error: {str(e)}', 'danger')
    return redirect(url_for('admin.backups'))

@bp.route('/backups/descargar/<nombre>')
@login_required
@requiere_rol('Administrador')
def descargar_backup(nombre):
    ruta = os.path.join(Config.BACKUP_DIR, nombre)
    if os.path.exists(ruta):
        return send_file(ruta, as_attachment=True, download_name=nombre)
    flash('Archivo no encontrado.', 'danger')
    return redirect(url_for('admin.backups'))

@bp.route('/exportar/<tipo>')
@login_required
@requiere_rol('Administrador')
def exportar(tipo):
    import csv, io
    from openpyxl import Workbook

    if tipo == 'productos':
        datos = get_productos()
        headers = ['ID', 'Codigo', 'Nombre', 'Tipo', 'Presentacion', 'Graduacion', 'Precio', 'Stock Min', 'Stock Max', 'Activo']
        rows = [[d['id_producto'], d['codigo_unico'], d['nombre_comercial'], d['tipo'], d['presentacion'],
                d['graduacion_alcoholica'], d['precio_actual'], d['stock_minimo'], d['stock_maximo'], d['activo']] for d in datos]
    elif tipo == 'distribuidores':
        datos = get_distribuidores()
        headers = ['ID', 'NIT', 'Razon Social', 'Ciudad', 'Zona', 'Contacto', 'Telefono', 'Correo']
        rows = [[d['id_distribuidor'], d['nit'], d['razon_social'], d['ciudad'], d['zona'], 
                d['contacto_nombre'], d['telefono'], d['correo']] for d in datos]
    elif tipo == 'pedidos':
        datos = get_pedidos()
        headers = ['ID', 'Distribuidor', 'Fecha Pedido', 'Fecha Entrega', 'Estado', 'Monto Total']
        rows = [[d['id_pedido'], d['distribuidor_nombre'], d['fecha_pedido'], d['fecha_entrega_requerida'],
                d['estado'], d['monto_total']] for d in datos]
    else:
        flash('Tipo no valido', 'danger'); return redirect(url_for('admin.dashboard'))

    fmt = request.args.get('formato', 'csv')
    if fmt == 'csv':
        output = io.StringIO(); writer = csv.writer(output)
        writer.writerow(headers); writer.writerows(rows)
        return Response(output.getvalue(), mimetype='text/csv', 
                       headers={'Content-Disposition': f'attachment; filename={tipo}.csv'})
    else:
        wb = Workbook(); ws = wb.active; ws.append(headers)
        for r in rows: ws.append(r)
        output = io.BytesIO(); wb.save(output); output.seek(0)
        return Response(output, mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                       headers={'Content-Disposition': f'attachment; filename={tipo}.xlsx'})
