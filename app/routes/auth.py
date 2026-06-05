from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from functools import wraps
from app.models import autenticar_usuario, registrar_log_acceso

auth_bp = Blueprint('auth', __name__)


def requiere_rol(*roles):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not current_user.is_authenticated:
                flash('Debes iniciar sesion', 'warning')
                return redirect(url_for('auth.login'))
            if current_user.rol not in roles:
                flash('No tienes permiso para acceder a esta pagina', 'danger')
                return redirect(url_for('auth.login'))
            return f(*args, **kwargs)
        return decorated_function
    return decorator


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        print(f"Intento de login - Usuario: {username}")
        
        usuario, mensaje = autenticar_usuario(username, password)
        
        if usuario:
            login_user(usuario)
            registrar_log_acceso(username, 'EXITO', request.remote_addr)
            flash(f'Bienvenido {usuario.username}', 'success')
            print(f"Login exitoso - Rol: {usuario.rol}")
            
            if usuario.rol == 'Administrador':
                return redirect(url_for('admin.dashboard'))
            elif usuario.rol == 'Gerente':
                return redirect(url_for('gerente.dashboard'))
            else:
                return redirect(url_for('distribuidor.dashboard'))
        else:
            registrar_log_acceso(username, 'FALLO', request.remote_addr)
            flash(mensaje or 'Usuario o contraseña incorrectos', 'danger')
            print(f"Login fallido para: {username}")
    
    return render_template('auth/login.html')


@auth_bp.route('/logout')
@login_required
def logout():
    logout_user()
    flash('Sesion cerrada correctamente', 'success')
    return redirect(url_for('auth.login'))