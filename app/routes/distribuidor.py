from flask import Blueprint, render_template, request, flash, redirect, url_for
from flask_login import login_required
from app.routes.auth import requiere_rol
from app.models import get_pedidos, get_pedido_by_id, crear_pedido, get_productos

distribuidor_bp = Blueprint('distribuidor', __name__, url_prefix='/distribuidor')

@distribuidor_bp.route('/dashboard')
@login_required
@requiere_rol('Distribuidor')
def dashboard():
    pedidos = get_pedidos(distribuidor_id=1)
    return render_template('distribuidor/dashboard.html', pedidos=pedidos)

@distribuidor_bp.route('/pedidos')
@login_required
@requiere_rol('Distribuidor')
def pedidos():
    pedidos = get_pedidos(distribuidor_id=1)
    return render_template('distribuidor/pedidos.html', pedidos=pedidos)

@distribuidor_bp.route('/pedidos/<int:id_pedido>')
@login_required
@requiere_rol('Distribuidor')
def ver_pedido(id_pedido):
    pedido = get_pedido_by_id(id_pedido)
    return render_template('distribuidor/ver_pedido.html', pedido=pedido)

@distribuidor_bp.route('/pedidos/nuevo', methods=['GET', 'POST'])
@login_required
@requiere_rol('Distribuidor')
def nuevo_pedido():
    productos = get_productos(activo=1)
    if request.method == 'POST':
        productos_sel = []
        for key in request.form:
            if key.startswith('cantidad_'):
                id_prod = int(key.replace('cantidad_', ''))
                cant = int(request.form.get(key, 0))
                if cant > 0:
                    for p in productos:
                        if p['id_producto'] == id_prod:
                            productos_sel.append({'id_producto': id_prod, 'cantidad': cant, 'precio_unitario': p['precio_actual']})
                            break
        if productos_sel:
            try:
                id_pedido = crear_pedido(1, request.form['fecha_entrega'], productos_sel, request.form.get('observaciones'))
                flash(f'Pedido #{id_pedido} creado exitosamente.', 'success')
                return redirect(url_for('distribuidor.pedidos'))
            except Exception as e:
                flash(f'Error: {str(e)}', 'danger')
        else:
            flash('Seleccione al menos un producto.', 'warning')
    return render_template('distribuidor/nuevo_pedido.html', productos=productos)