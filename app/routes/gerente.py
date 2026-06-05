from flask import Blueprint, render_template, request
from flask_login import login_required
from app.routes.auth import requiere_rol
from app.models import (get_vista_stock_consolidado, get_vista_proximos_vencer, 
    get_vista_rotacion_inventario, get_pedidos, get_productos, get_inventario_bodegas,
    get_bodegas, get_plantas, get_lotes, get_distribuidores)

gerente_bp = Blueprint('gerente', __name__, url_prefix='/gerente')

@gerente_bp.route('/dashboard')
@login_required
@requiere_rol('Gerente')
def dashboard():
    return render_template('gerente/dashboard.html')

@gerente_bp.route('/productos')
@login_required
@requiere_rol('Gerente')
def productos():
    productos = get_productos(busqueda=request.args.get('q'), tipo=request.args.get('tipo'))
    return render_template('gerente/productos.html', productos=productos)

@gerente_bp.route('/inventario')
@login_required
@requiere_rol('Gerente')
def inventario():
    bodegas = get_bodegas()
    inventario = get_inventario_bodegas(bodega_id=request.args.get('bodega', type=int))
    return render_template('gerente/inventario.html', inventario=inventario, bodegas=bodegas)

@gerente_bp.route('/lotes')
@login_required
@requiere_rol('Gerente')
def lotes():
    lotes = get_lotes(producto_id=request.args.get('producto', type=int),
                      planta_id=request.args.get('planta', type=int),
                      proximos_vencer=request.args.get('vencer') == '1')
    productos = get_productos()
    plantas = get_plantas()
    return render_template('gerente/lotes.html', lotes=lotes, productos=productos, plantas=plantas)

@gerente_bp.route('/pedidos')
@login_required
@requiere_rol('Gerente')
def pedidos():
    pedidos = get_pedidos(estado=request.args.get('estado'), 
                         fecha_desde=request.args.get('desde'),
                         fecha_hasta=request.args.get('hasta'))
    return render_template('gerente/pedidos.html', pedidos=pedidos)

@gerente_bp.route('/reportes/stock')
@login_required
@requiere_rol('Gerente')
def reporte_stock():
    return render_template('gerente/reporte_stock.html', datos=get_vista_stock_consolidado())

@gerente_bp.route('/reportes/vencer')
@login_required
@requiere_rol('Gerente')
def reporte_vencer():
    return render_template('gerente/reporte_vencer.html', datos=get_vista_proximos_vencer())

@gerente_bp.route('/reportes/rotacion')
@login_required
@requiere_rol('Gerente')
def reporte_rotacion():
    return render_template('gerente/reporte_rotacion.html', datos=get_vista_rotacion_inventario())