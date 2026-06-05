from flask import Blueprint, jsonify
from flask_login import login_required
from app.models import get_metricas_dashboard, get_stock_por_planta, get_pedidos_por_estado

api_bp = Blueprint('api', __name__, url_prefix='/api')

@api_bp.route('/metricas')
@login_required
def metricas():
    return jsonify(get_metricas_dashboard())

@api_bp.route('/stock-planta')
@login_required
def stock_planta():
    return jsonify(get_stock_por_planta())

@api_bp.route('/pedidos-estado')
@login_required
def pedidos_estado():
    return jsonify(get_pedidos_por_estado())