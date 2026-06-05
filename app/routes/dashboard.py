from flask import Blueprint, render_template
from flask_login import login_required
from app.models import get_metricas_dashboard, get_stock_por_planta, get_pedidos_por_estado

dashboard_bp = Blueprint('dashboard', __name__, url_prefix='/dashboard')

@dashboard_bp.route('/')
@login_required
def index():
    metricas = get_metricas_dashboard()
    stock_plantas = get_stock_por_planta()
    pedidos_estado = get_pedidos_por_estado()
    return render_template('dashboard/index.html', metricas=metricas, 
                          stock_plantas=stock_plantas, pedidos_estado=pedidos_estado)