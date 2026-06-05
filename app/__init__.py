from flask import Flask, redirect, url_for, render_template
from flask_login import LoginManager
from app.config import Config

login_manager = LoginManager()

def create_app():
    app = Flask(__name__, template_folder='templates', static_folder='static')
    app.config.from_object(Config)
    
    from app.models import get_user_by_id
    
    login_manager.init_app(app)
    login_manager.login_view = 'auth.login'
    login_manager.login_message = 'Por favor inicia sesión para acceder a esta página'
    
    @login_manager.user_loader
    def load_user(user_id):
        return get_user_by_id(int(user_id))
    
    from app.routes.auth import auth_bp
    from app.routes.admin import bp as admin_bp
    from app.routes.gerente import gerente_bp
    from app.routes.distribuidor import distribuidor_bp
    from app.routes.dashboard import dashboard_bp
    from app.routes.api import api_bp
    
    app.register_blueprint(auth_bp, url_prefix='/auth')
    app.register_blueprint(admin_bp)
    app.register_blueprint(gerente_bp)
    app.register_blueprint(distribuidor_bp)
    app.register_blueprint(dashboard_bp)
    app.register_blueprint(api_bp)
    
    @app.template_filter('format_money')
    def format_money(value):
        return f"Bs. {float(value or 0):,.2f}" if value else "Bs. 0.00"
    
    @app.template_filter('format_number')
    def format_number(value):
        return f"{int(value or 0):,}" if value else "0"
    
    @app.route('/')
    def index():
        return redirect(url_for('auth.login'))
    
    @app.errorhandler(404)
    def not_found(e):
        return render_template('shared/error.html', error_code=404, error_msg="Pagina no encontrada"), 404
    
    @app.errorhandler(500)
    def internal_error(e):
        return render_template('shared/error.html', error_code=500, error_msg="Error interno del servidor"), 500
    
    return app