-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 06-06-2026 a las 00:26:16
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `pil_andina_db`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_despachar_pedido` (IN `p_id_pedido` INT, IN `p_usuario` VARCHAR(50))   BEGIN
    DECLARE v_suficiente BOOLEAN DEFAULT TRUE;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_stock_disponible INT;
    DECLARE done INT DEFAULT FALSE;
    
    DECLARE cur_detalle CURSOR FOR 
        SELECT id_producto, cantidad FROM detalle_pedido WHERE id_pedido = p_id_pedido;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Verificar stock disponible (usando lotes FIFO)
    OPEN cur_detalle;
    read_loop: LOOP
        FETCH cur_detalle INTO v_id_producto, v_cantidad;
        IF done THEN LEAVE read_loop; END IF;
        
        SELECT COALESCE(SUM(ib.cantidad_actual), 0) INTO v_stock_disponible
        FROM lote_produccion l
        JOIN inventario_bodega ib ON l.id_lote = ib.id_lote
        WHERE l.id_producto = v_id_producto 
          AND l.control_calidad = 'Aprobado'
          AND l.fecha_vencimiento > CURDATE()
          AND ib.cantidad_actual > 0;
        
        IF v_stock_disponible < v_cantidad THEN
            SET v_suficiente = FALSE;
            LEAVE read_loop;
        END IF;
    END LOOP;
    CLOSE cur_detalle;
    
    IF NOT v_suficiente THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente para despachar el pedido';
    END IF;
    
    -- Actualizar estado del pedido
    UPDATE pedido SET estado = 'Despachado' WHERE id_pedido = p_id_pedido;
    
    -- Descontar stock usando lotes más antiguos (FIFO)
    -- Lógica simplificada: descontar de lotes ordenados por fecha de producción
    UPDATE inventario_bodega ib
    JOIN (
        SELECT l.id_lote, dp.cantidad AS cantidad_necesaria
        FROM detalle_pedido dp
        JOIN lote_produccion l ON dp.id_producto = l.id_producto
        WHERE dp.id_pedido = p_id_pedido AND l.control_calidad = 'Aprobado' AND l.fecha_vencimiento > CURDATE()
        ORDER BY l.fecha_produccion ASC
    ) AS lotes_fifo ON ib.id_lote = lotes_fifo.id_lote
    SET ib.cantidad_actual = GREATEST(0, ib.cantidad_actual - lotes_fifo.cantidad_necesaria);
    
    COMMIT;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_produccion` (IN `p_numero_lote` VARCHAR(30), IN `p_id_producto` INT, IN `p_id_planta` INT, IN `p_fecha_produccion` DATE, IN `p_fecha_vencimiento` DATE, IN `p_cantidad` INT, IN `p_tecnico` VARCHAR(100), IN `p_usuario` VARCHAR(50))   BEGIN
    DECLARE v_id_lote INT;
    DECLARE v_id_bodega INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Obtener bodega predeterminada de producto terminado para esa planta
    SELECT id_bodega INTO v_id_bodega FROM bodega 
    WHERE id_planta = p_id_planta AND nombre_bodega LIKE '%Producto Terminado%' 
    LIMIT 1;
    
    IF v_id_bodega IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe bodega de producto terminado para esta planta';
    END IF;
    
    -- Insertar lote
    INSERT INTO lote_produccion(numero_lote, id_producto, id_planta, fecha_produccion, 
                                fecha_vencimiento, cantidad_producida, tecnico_responsable, control_calidad)
    VALUES(p_numero_lote, p_id_producto, p_id_planta, p_fecha_produccion, 
           p_fecha_vencimiento, p_cantidad, p_tecnico, 'Aprobado');
    
    SET v_id_lote = LAST_INSERT_ID();
    
    -- Insertar o actualizar inventario
    INSERT INTO inventario_bodega(id_lote, id_bodega, cantidad_actual)
    VALUES(v_id_lote, v_id_bodega, p_cantidad)
    ON DUPLICATE KEY UPDATE cantidad_actual = cantidad_actual + p_cantidad;
    
    -- Registrar movimiento
    INSERT INTO movimiento_inventario(id_lote, id_bodega, tipo_movimiento, cantidad, usuario_responsable, observacion)
    VALUES(v_id_lote, v_id_bodega, 'ENTRADA', p_cantidad, p_usuario, CONCAT('Producción lote: ', p_numero_lote));
    
    COMMIT;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_cambios`
--

CREATE TABLE `auditoria_cambios` (
  `id_audit` int(11) NOT NULL,
  `tabla_afectada` varchar(50) NOT NULL,
  `accion` varchar(20) NOT NULL COMMENT 'INSERT, UPDATE, DELETE',
  `registro_id` int(11) NOT NULL,
  `datos_previos` text DEFAULT NULL,
  `datos_nuevos` text DEFAULT NULL,
  `usuario` varchar(50) NOT NULL,
  `ip_origen` varchar(45) DEFAULT NULL,
  `fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `bodega`
--

CREATE TABLE `bodega` (
  `id_bodega` int(11) NOT NULL,
  `id_planta` int(11) NOT NULL,
  `nombre_bodega` varchar(100) NOT NULL COMMENT 'Producto Terminado, Insumos, Refrigerado',
  `capacidad_maxima` int(11) NOT NULL CHECK (`capacidad_maxima` > 0),
  `temperatura_almacenamiento` decimal(5,2) DEFAULT NULL COMMENT 'Temperatura en grados Celsius',
  `ubicacion_fisica` varchar(200) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `bodega`
--

INSERT INTO `bodega` (`id_bodega`, `id_planta`, `nombre_bodega`, `capacidad_maxima`, `temperatura_almacenamiento`, `ubicacion_fisica`) VALUES
(1, 1, 'Producto Terminado Norte', 8000, 12.50, 'Módulo A'),
(2, 1, 'Cámara Refrigerada', 3000, 4.00, 'Módulo B'),
(3, 2, 'Producto Terminado Central', 10000, 13.00, 'Almacén 1'),
(4, 2, 'Insumos', 5000, 18.00, 'Almacén 2'),
(5, 3, 'Producto Terminado Sur', 7500, 12.00, 'Nave Principal'),
(6, 3, 'Refrigerado Expansión', 4000, 5.00, 'Nave Secundaria');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_pedido`
--

CREATE TABLE `detalle_pedido` (
  `id_detalle` int(11) NOT NULL,
  `id_pedido` int(11) NOT NULL,
  `id_producto` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL CHECK (`cantidad` > 0),
  `precio_unitario` decimal(12,2) NOT NULL CHECK (`precio_unitario` >= 0),
  `subtotal` decimal(14,2) GENERATED ALWAYS AS (`cantidad` * `precio_unitario`) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `detalle_pedido`
--

INSERT INTO `detalle_pedido` (`id_detalle`, `id_pedido`, `id_producto`, `cantidad`, `precio_unitario`) VALUES
(1, 1, 1, 500, 12.00),
(2, 1, 2, 300, 18.00),
(3, 2, 3, 400, 10.50),
(4, 3, 4, 200, 21.50),
(5, 3, 5, 150, 27.00),
(6, 4, 4, 10, 22.00),
(7, 4, 8, 78, 10.50);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `distribuidor`
--

CREATE TABLE `distribuidor` (
  `id_distribuidor` int(11) NOT NULL,
  `nit` varchar(20) NOT NULL,
  `razon_social` varchar(150) NOT NULL,
  `direccion` varchar(200) NOT NULL,
  `ciudad` varchar(50) NOT NULL,
  `zona` varchar(100) DEFAULT NULL,
  `contacto_nombre` varchar(100) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `correo` varchar(100) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1,
  `fecha_registro` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `distribuidor`
--

INSERT INTO `distribuidor` (`id_distribuidor`, `nit`, `razon_social`, `direccion`, `ciudad`, `zona`, `contacto_nombre`, `telefono`, `correo`, `activo`, `fecha_registro`) VALUES
(1, '1023456012', 'DISTRIBUCIONES LA PAZ SRL', 'Av. Mariscal Santa Cruz 123', 'La Paz', 'Centro', 'Jorge Quispe', '77123456', 'jorge@distlapaz.com', 1, '2026-06-05 19:09:53'),
(2, '2034567893', 'CERVEZAS DEL VALLE', 'Calle España 456', 'Cochabamba', 'Queru Queru', 'María Torrico', '78234567', 'maria@vallesbeer.com', 1, '2026-06-05 19:09:53'),
(3, '3045678901', 'ESTE DISTRIBUCIONES', 'Av. San Martín 789', 'Santa Cruz', 'Equipetrol', 'Roberto Landívar', '79876543', 'roberto@estedist.com', 1, '2026-06-05 19:09:53'),
(4, '4056789012', 'SUR ANDINO', 'Calle Potosí 321', 'La Paz', 'Sopocachi', 'Lucía Mamani', '71567890', 'lucia@sandino.com', 1, '2026-06-05 19:09:53');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `factura`
--

CREATE TABLE `factura` (
  `id_factura` int(11) NOT NULL,
  `id_pedido` int(11) NOT NULL,
  `numero_factura` varchar(30) NOT NULL,
  `fecha_emision` date NOT NULL,
  `monto_total` decimal(14,2) NOT NULL CHECK (`monto_total` >= 0),
  `estado_pago` enum('Pagado','Pendiente','Parcial','Vencido') DEFAULT 'Pendiente',
  `fecha_pago` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `factura`
--

INSERT INTO `factura` (`id_factura`, `id_pedido`, `numero_factura`, `fecha_emision`, `monto_total`, `estado_pago`, `fecha_pago`) VALUES
(1, 3, 'FAC-001-2025', '2025-06-04', 8350.00, 'Pagado', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inventario_bodega`
--

CREATE TABLE `inventario_bodega` (
  `id_inventario` int(11) NOT NULL,
  `id_lote` int(11) NOT NULL,
  `id_bodega` int(11) NOT NULL,
  `cantidad_actual` int(11) NOT NULL DEFAULT 0 CHECK (`cantidad_actual` >= 0),
  `ultima_actualizacion` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `inventario_bodega`
--

INSERT INTO `inventario_bodega` (`id_inventario`, `id_lote`, `id_bodega`, `cantidad_actual`, `ultima_actualizacion`) VALUES
(1, 1, 1, 3800, '2026-06-05 19:09:53'),
(2, 2, 3, 3500, '2026-06-05 19:09:53'),
(3, 3, 5, 2900, '2026-06-05 19:09:53'),
(4, 4, 2, 2100, '2026-06-05 19:09:53'),
(5, 5, 4, 2500, '2026-06-05 19:09:53'),
(6, 6, 6, 4000, '2026-06-05 19:09:53'),
(7, 7, 1, 1800, '2026-06-05 19:09:53'),
(8, 8, 3, 1500, '2026-06-05 19:09:53');

--
-- Disparadores `inventario_bodega`
--
DELIMITER $$
CREATE TRIGGER `trg_check_stock_minimo` AFTER UPDATE ON `inventario_bodega` FOR EACH ROW BEGIN
    DECLARE stock_total INT;
    DECLARE stock_min INT;
    
    -- Calcular stock total del producto
    SELECT SUM(ib.cantidad_actual), p.stock_minimo INTO stock_total, stock_min
    FROM inventario_bodega ib
    JOIN lote_produccion l ON ib.id_lote = l.id_lote
    JOIN producto p ON l.id_producto = p.id_producto
    WHERE l.id_producto = (SELECT id_producto FROM lote_produccion WHERE id_lote = NEW.id_lote)
    GROUP BY p.id_producto;
    
    IF stock_total < stock_min THEN
        -- Insertar alerta como movimiento especial (se puede expandir)
        INSERT INTO movimiento_inventario(id_lote, id_bodega, tipo_movimiento, cantidad, observacion)
        VALUES(NEW.id_lote, NEW.id_bodega, 'AJUSTE', 0, 
               CONCAT('ALERTA: Stock por debajo del mínimo (', stock_total, '/', stock_min, ')'));
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `log_accesos`
--

CREATE TABLE `log_accesos` (
  `id_log` int(11) NOT NULL,
  `username` varchar(50) DEFAULT NULL,
  `resultado` enum('EXITO','FALLO') NOT NULL,
  `ip_origen` varchar(45) DEFAULT NULL,
  `fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `log_accesos`
--

INSERT INTO `log_accesos` (`id_log`, `username`, `resultado`, `ip_origen`, `fecha_hora`) VALUES
(1, 'admin_pil', 'FALLO', '127.0.0.1', '2026-06-05 20:44:17'),
(2, 'admin_pil', 'FALLO', '127.0.0.1', '2026-06-05 20:44:36'),
(3, 'admin_pil', 'FALLO', '127.0.0.1', '2026-06-05 20:44:55'),
(4, 'admin_pil', 'FALLO', '127.0.0.1', '2026-06-05 20:55:40'),
(5, 'admin_pil', 'FALLO', '127.0.0.1', '2026-06-05 20:56:05'),
(6, 'admin_pil', 'EXITO', '127.0.0.1', '2026-06-05 21:43:22'),
(7, 'gerente_lp', 'EXITO', '127.0.0.1', '2026-06-05 21:44:34'),
(8, 'dist_la_paz', 'EXITO', '127.0.0.1', '2026-06-05 21:46:40');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `lote_produccion`
--

CREATE TABLE `lote_produccion` (
  `id_lote` int(11) NOT NULL,
  `numero_lote` varchar(30) NOT NULL COMMENT 'Formato: LOTE-YYYYMMDD-XXX',
  `id_producto` int(11) NOT NULL,
  `id_planta` int(11) NOT NULL,
  `fecha_produccion` date NOT NULL,
  `fecha_vencimiento` date NOT NULL,
  `cantidad_producida` int(11) NOT NULL CHECK (`cantidad_producida` > 0),
  `control_calidad` enum('Aprobado','Rechazado','Pendiente') DEFAULT 'Pendiente',
  `tecnico_responsable` varchar(100) DEFAULT NULL,
  `observaciones` text DEFAULT NULL,
  `fecha_registro` timestamp NOT NULL DEFAULT current_timestamp()
) ;

--
-- Volcado de datos para la tabla `lote_produccion`
--

INSERT INTO `lote_produccion` (`id_lote`, `numero_lote`, `id_producto`, `id_planta`, `fecha_produccion`, `fecha_vencimiento`, `cantidad_producida`, `control_calidad`, `tecnico_responsable`, `observaciones`, `fecha_registro`) VALUES
(1, 'LOTE-20250501-001', 1, 1, '2025-05-01', '2025-11-01', 5000, 'Aprobado', 'Carlos Mendoza', NULL, '2026-06-05 19:09:53'),
(2, 'LOTE-20250505-002', 2, 2, '2025-05-05', '2025-11-05', 4200, 'Aprobado', 'Ruth Jiménez', NULL, '2026-06-05 19:09:53'),
(3, 'LOTE-20250510-003', 3, 3, '2025-05-10', '2025-10-10', 3800, 'Aprobado', 'Diego Alarcón', NULL, '2026-06-05 19:09:53'),
(4, 'LOTE-20250515-004', 4, 1, '2025-05-15', '2025-12-15', 2800, 'Aprobado', 'Carlos Mendoza', NULL, '2026-06-05 19:09:53'),
(5, 'LOTE-20250520-005', 5, 2, '2025-05-20', '2025-12-20', 3100, 'Aprobado', 'Ruth Jiménez', NULL, '2026-06-05 19:09:53'),
(6, 'LOTE-20250525-006', 6, 3, '2025-05-25', '2025-11-25', 4500, 'Aprobado', 'Diego Alarcón', NULL, '2026-06-05 19:09:53'),
(7, 'LOTE-20250601-007', 7, 1, '2025-06-01', '2026-01-01', 2200, 'Aprobado', 'Carlos Mendoza', NULL, '2026-06-05 19:09:53'),
(8, 'LOTE-20250602-008', 8, 2, '2025-06-02', '2025-12-02', 1900, 'Aprobado', 'Ruth Jiménez', NULL, '2026-06-05 19:09:53');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `movimiento_inventario`
--

CREATE TABLE `movimiento_inventario` (
  `id_movimiento` int(11) NOT NULL,
  `id_lote` int(11) NOT NULL,
  `id_bodega` int(11) NOT NULL,
  `tipo_movimiento` enum('ENTRADA','SALIDA','TRASLADO','AJUSTE') NOT NULL,
  `cantidad` int(11) NOT NULL,
  `fecha_movimiento` timestamp NOT NULL DEFAULT current_timestamp(),
  `usuario_responsable` varchar(50) DEFAULT NULL,
  `observacion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `movimiento_inventario`
--

INSERT INTO `movimiento_inventario` (`id_movimiento`, `id_lote`, `id_bodega`, `tipo_movimiento`, `cantidad`, `fecha_movimiento`, `usuario_responsable`, `observacion`) VALUES
(1, 1, 1, 'ENTRADA', 5000, '2026-06-05 19:09:53', 'admin', 'Producción inicial LOTE-20250501-001'),
(2, 2, 3, 'ENTRADA', 4200, '2026-06-05 19:09:53', 'admin', 'Producción Cochabamba'),
(3, 3, 5, 'ENTRADA', 3800, '2026-06-05 19:09:53', 'admin', 'Producción Santa Cruz'),
(4, 1, 1, 'SALIDA', 1200, '2026-06-05 19:09:53', 'vendedor', 'Despacho a distribuidor La Paz');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `pedido`
--

CREATE TABLE `pedido` (
  `id_pedido` int(11) NOT NULL,
  `id_distribuidor` int(11) NOT NULL,
  `fecha_pedido` date NOT NULL,
  `fecha_entrega_requerida` date NOT NULL,
  `estado` enum('Pendiente','Despachado','Entregado','Cancelado') DEFAULT 'Pendiente',
  `observaciones` text DEFAULT NULL,
  `monto_total` decimal(14,2) DEFAULT 0.00
) ;

--
-- Volcado de datos para la tabla `pedido`
--

INSERT INTO `pedido` (`id_pedido`, `id_distribuidor`, `fecha_pedido`, `fecha_entrega_requerida`, `estado`, `observaciones`, `monto_total`) VALUES
(1, 1, '2025-06-01', '2025-06-05', 'Pendiente', NULL, 11400.00),
(2, 2, '2025-06-02', '2025-06-07', 'Pendiente', NULL, 4200.00),
(3, 3, '2025-06-03', '2025-06-10', 'Despachado', NULL, 8350.00),
(4, 1, '2026-06-05', '2026-06-06', 'Pendiente', 'adsdas', 1039.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `planta`
--

CREATE TABLE `planta` (
  `id_planta` int(11) NOT NULL,
  `nombre` varchar(50) NOT NULL COMMENT 'La Paz, Cochabamba, Santa Cruz',
  `ubicacion` varchar(200) NOT NULL COMMENT 'Dirección específica',
  `ciudad` varchar(50) NOT NULL,
  `responsable_nombre` varchar(100) NOT NULL,
  `responsable_contacto` varchar(50) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `planta`
--

INSERT INTO `planta` (`id_planta`, `nombre`, `ubicacion`, `ciudad`, `responsable_nombre`, `responsable_contacto`, `activo`) VALUES
(1, 'La Paz', 'Mecapaca - Km 12', 'La Paz', 'Luis Fernández', '71522334', 1),
(2, 'Cochabamba', 'Sacaba - Av. Bolívia', 'Cochabamba', 'Marcos Villarroel', '78234567', 1),
(3, 'Santa Cruz', 'Palmasola - Calle 3', 'Santa Cruz', 'Ana María Suárez', '79876543', 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `producto`
--

CREATE TABLE `producto` (
  `id_producto` int(11) NOT NULL,
  `codigo_unico` varchar(20) NOT NULL COMMENT 'Código interno del producto',
  `nombre_comercial` varchar(100) NOT NULL COMMENT 'Paceña, Taquiña, Huari, etc.',
  `tipo` varchar(30) NOT NULL CHECK (`tipo` in ('Lager','Pilsener','Malta','Negra','Ale','Sin Alcohol')),
  `presentacion` varchar(20) NOT NULL COMMENT '355ml, 620ml, 1L, etc.',
  `graduacion_alcoholica` decimal(4,2) NOT NULL CHECK (`graduacion_alcoholica` >= 0),
  `precio_actual` decimal(12,2) NOT NULL CHECK (`precio_actual` >= 0),
  `stock_minimo` int(11) NOT NULL DEFAULT 100 CHECK (`stock_minimo` >= 0),
  `stock_maximo` int(11) NOT NULL DEFAULT 5000 CHECK (`stock_maximo` > `stock_minimo`),
  `activo` tinyint(1) DEFAULT 1,
  `fecha_creacion` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Catálogo de productos cerveceros';

--
-- Volcado de datos para la tabla `producto`
--

INSERT INTO `producto` (`id_producto`, `codigo_unico`, `nombre_comercial`, `tipo`, `presentacion`, `graduacion_alcoholica`, `precio_actual`, `stock_minimo`, `stock_maximo`, `activo`, `fecha_creacion`) VALUES
(1, 'CER-PAC-355', 'Paceña', 'Lager', '355ml', 4.50, 12.50, 200, 5000, 1, '2026-06-05 19:09:52'),
(2, 'CER-TAQ-620', 'Taquiña', 'Pilsener', '620ml', 5.00, 18.90, 150, 4000, 1, '2026-06-05 19:09:52'),
(3, 'CER-HUA-355', 'Huari', 'Malta', '355ml', 0.00, 11.00, 100, 3000, 1, '2026-06-05 19:09:52'),
(4, 'CER-BOC-620', 'Bock', 'Negra', '620ml', 5.50, 22.00, 80, 2500, 1, '2026-06-05 19:09:52'),
(5, 'CER-REAL-1L', 'Real', 'Lager', '1L', 4.80, 28.50, 120, 3500, 1, '2026-06-05 19:09:52'),
(6, 'CER-IMP-355', 'Imperial', 'Pilsener', '355ml', 4.90, 14.30, 180, 4500, 1, '2026-06-05 19:09:52'),
(7, 'CER-POT-620', 'Potosina', 'Lager', '620ml', 4.70, 16.20, 100, 3000, 1, '2026-06-05 19:09:52'),
(8, 'CER-COP-355', 'Copacabana', 'Sin Alcohol', '355ml', 0.40, 10.50, 90, 2500, 1, '2026-06-05 19:09:52');

--
-- Disparadores `producto`
--
DELIMITER $$
CREATE TRIGGER `trg_audit_producto_update` AFTER UPDATE ON `producto` FOR EACH ROW BEGIN
    IF OLD.precio_actual != NEW.precio_actual OR OLD.activo != NEW.activo THEN
        INSERT INTO auditoria_cambios(tabla_afectada, accion, registro_id, datos_previos, datos_nuevos, usuario)
        VALUES('producto', 'UPDATE', NEW.id_producto, 
               CONCAT('precio=', OLD.precio_actual, ' activo=', OLD.activo),
               CONCAT('precio=', NEW.precio_actual, ' activo=', NEW.activo),
               COALESCE(@current_user, 'SISTEMA'));
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usuario_sistema`
--

CREATE TABLE `usuario_sistema` (
  `id_usuario` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `email` varchar(100) NOT NULL,
  `rol` enum('Administrador','Gerente','Distribuidor') NOT NULL,
  `id_empleado_relacionado` int(11) DEFAULT NULL COMMENT 'CI o ID de persona física',
  `ultimo_login` timestamp NULL DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1,
  `intentos_fallidos` int(11) DEFAULT 0,
  `bloqueado_hasta` timestamp NULL DEFAULT NULL,
  `fecha_creacion` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `usuario_sistema`
--

INSERT INTO `usuario_sistema` (`id_usuario`, `username`, `password_hash`, `email`, `rol`, `id_empleado_relacionado`, `ultimo_login`, `activo`, `intentos_fallidos`, `bloqueado_hasta`, `fecha_creacion`) VALUES
(1, 'admin_pil', '1d431e4e0e03d2b8f4ac11da3d09551a8acea7ffea3478ffeeb5ad33042d19c7', 'admin@pilandina.bo', 'Administrador', NULL, '2026-06-05 21:43:22', 1, 0, NULL, '2026-06-05 20:50:37'),
(2, 'gerente_lp', 'ac909385d0414717dc294cd245b0954fc0d5ad30422c2fa6e16e97c38904fac0', 'gerente@pilandina.bo', 'Gerente', NULL, '2026-06-05 21:44:34', 1, 0, NULL, '2026-06-05 20:50:37'),
(3, 'dist_la_paz', '8334f4b02aee44802c2c456a3c1b5588e5cd53f93037cae5ba2b246c912133aa', 'distribuidor@pilandina.bo', 'Distribuidor', NULL, '2026-06-05 21:46:40', 1, 0, NULL, '2026-06-05 20:50:37');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_proximos_vencer`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_proximos_vencer` (
`id_lote` int(11)
,`numero_lote` varchar(30)
,`nombre_comercial` varchar(100)
,`presentacion` varchar(20)
,`fecha_vencimiento` date
,`dias_restantes` int(7)
,`unidades_disponibles` decimal(32,0)
,`planta_actual` varchar(50)
,`prioridad` varchar(7)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_rotacion_inventario`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_rotacion_inventario` (
`id_producto` int(11)
,`nombre_comercial` varchar(100)
,`presentacion` varchar(20)
,`salidas_30dias` decimal(32,0)
,`entradas_30dias` decimal(32,0)
,`stock_actual` decimal(32,0)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_stock_consolidado`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_stock_consolidado` (
`id_producto` int(11)
,`codigo_unico` varchar(20)
,`nombre_comercial` varchar(100)
,`tipo` varchar(30)
,`presentacion` varchar(20)
,`planta` varchar(50)
,`stock_total` decimal(32,0)
,`stock_minimo` int(11)
,`stock_maximo` int(11)
,`estado_stock` varchar(7)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_proximos_vencer`
--
DROP TABLE IF EXISTS `vista_proximos_vencer`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_proximos_vencer`  AS SELECT `l`.`id_lote` AS `id_lote`, `l`.`numero_lote` AS `numero_lote`, `p`.`nombre_comercial` AS `nombre_comercial`, `p`.`presentacion` AS `presentacion`, `l`.`fecha_vencimiento` AS `fecha_vencimiento`, to_days(`l`.`fecha_vencimiento`) - to_days(curdate()) AS `dias_restantes`, sum(`ib`.`cantidad_actual`) AS `unidades_disponibles`, `pl`.`nombre` AS `planta_actual`, CASE WHEN to_days(`l`.`fecha_vencimiento`) - to_days(curdate()) <= 7 THEN 'URGENTE' WHEN to_days(`l`.`fecha_vencimiento`) - to_days(curdate()) <= 15 THEN 'PRÓXIMO' ELSE 'VIGENTE' END AS `prioridad` FROM ((((`lote_produccion` `l` join `producto` `p` on(`l`.`id_producto` = `p`.`id_producto`)) join `inventario_bodega` `ib` on(`l`.`id_lote` = `ib`.`id_lote`)) join `bodega` `b` on(`ib`.`id_bodega` = `b`.`id_bodega`)) join `planta` `pl` on(`b`.`id_planta` = `pl`.`id_planta`)) WHERE `l`.`control_calidad` = 'Aprobado' AND `l`.`fecha_vencimiento` between curdate() and curdate() + interval 30 day AND `ib`.`cantidad_actual` > 0 ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_rotacion_inventario`
--
DROP TABLE IF EXISTS `vista_rotacion_inventario`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_rotacion_inventario`  AS SELECT `p`.`id_producto` AS `id_producto`, `p`.`nombre_comercial` AS `nombre_comercial`, `p`.`presentacion` AS `presentacion`, coalesce(sum(case when `m`.`tipo_movimiento` = 'SALIDA' and `m`.`fecha_movimiento` >= curdate() - interval 30 day then `m`.`cantidad` else 0 end),0) AS `salidas_30dias`, coalesce(sum(case when `m`.`tipo_movimiento` = 'ENTRADA' and `m`.`fecha_movimiento` >= curdate() - interval 30 day then `m`.`cantidad` else 0 end),0) AS `entradas_30dias`, coalesce(sum(`ib`.`cantidad_actual`),0) AS `stock_actual` FROM (((`producto` `p` left join `lote_produccion` `l` on(`p`.`id_producto` = `l`.`id_producto`)) left join `inventario_bodega` `ib` on(`l`.`id_lote` = `ib`.`id_lote`)) left join `movimiento_inventario` `m` on(`l`.`id_lote` = `m`.`id_lote`)) GROUP BY `p`.`id_producto` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_stock_consolidado`
--
DROP TABLE IF EXISTS `vista_stock_consolidado`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_stock_consolidado`  AS SELECT `p`.`id_producto` AS `id_producto`, `p`.`codigo_unico` AS `codigo_unico`, `p`.`nombre_comercial` AS `nombre_comercial`, `p`.`tipo` AS `tipo`, `p`.`presentacion` AS `presentacion`, `pl`.`nombre` AS `planta`, sum(`ib`.`cantidad_actual`) AS `stock_total`, `p`.`stock_minimo` AS `stock_minimo`, `p`.`stock_maximo` AS `stock_maximo`, CASE WHEN sum(`ib`.`cantidad_actual`) <= `p`.`stock_minimo` THEN 'CRÍTICO' WHEN sum(`ib`.`cantidad_actual`) >= `p`.`stock_maximo` THEN 'EXCESO' ELSE 'NORMAL' END AS `estado_stock` FROM ((((`producto` `p` join `lote_produccion` `l` on(`p`.`id_producto` = `l`.`id_producto`)) join `inventario_bodega` `ib` on(`l`.`id_lote` = `ib`.`id_lote`)) join `bodega` `b` on(`ib`.`id_bodega` = `b`.`id_bodega`)) join `planta` `pl` on(`b`.`id_planta` = `pl`.`id_planta`)) WHERE `l`.`control_calidad` = 'Aprobado' GROUP BY `p`.`id_producto`, `pl`.`id_planta` ;

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `auditoria_cambios`
--
ALTER TABLE `auditoria_cambios`
  ADD PRIMARY KEY (`id_audit`),
  ADD KEY `idx_audit_tabla` (`tabla_afectada`),
  ADD KEY `idx_audit_fecha` (`fecha_hora`);

--
-- Indices de la tabla `bodega`
--
ALTER TABLE `bodega`
  ADD PRIMARY KEY (`id_bodega`),
  ADD KEY `idx_bodega_planta` (`id_planta`);

--
-- Indices de la tabla `detalle_pedido`
--
ALTER TABLE `detalle_pedido`
  ADD PRIMARY KEY (`id_detalle`),
  ADD UNIQUE KEY `uk_pedido_producto` (`id_pedido`,`id_producto`),
  ADD KEY `id_producto` (`id_producto`);

--
-- Indices de la tabla `distribuidor`
--
ALTER TABLE `distribuidor`
  ADD PRIMARY KEY (`id_distribuidor`),
  ADD UNIQUE KEY `nit` (`nit`),
  ADD UNIQUE KEY `correo` (`correo`),
  ADD KEY `idx_distribuidor_ciudad` (`ciudad`);

--
-- Indices de la tabla `factura`
--
ALTER TABLE `factura`
  ADD PRIMARY KEY (`id_factura`),
  ADD UNIQUE KEY `id_pedido` (`id_pedido`),
  ADD UNIQUE KEY `numero_factura` (`numero_factura`),
  ADD KEY `idx_factura_estado` (`estado_pago`);

--
-- Indices de la tabla `inventario_bodega`
--
ALTER TABLE `inventario_bodega`
  ADD PRIMARY KEY (`id_inventario`),
  ADD UNIQUE KEY `uk_lote_bodega` (`id_lote`,`id_bodega`),
  ADD KEY `idx_inventario_bodega` (`id_bodega`);

--
-- Indices de la tabla `log_accesos`
--
ALTER TABLE `log_accesos`
  ADD PRIMARY KEY (`id_log`),
  ADD KEY `idx_log_username` (`username`),
  ADD KEY `idx_log_fecha` (`fecha_hora`);

--
-- Indices de la tabla `lote_produccion`
--
ALTER TABLE `lote_produccion`
  ADD PRIMARY KEY (`id_lote`),
  ADD UNIQUE KEY `numero_lote` (`numero_lote`),
  ADD KEY `id_planta` (`id_planta`),
  ADD KEY `idx_lote_producto` (`id_producto`),
  ADD KEY `idx_lote_vencimiento` (`fecha_vencimiento`),
  ADD KEY `idx_lote_calidad` (`control_calidad`),
  ADD KEY `idx_lote_vencimiento_calidad` (`fecha_vencimiento`,`control_calidad`);

--
-- Indices de la tabla `movimiento_inventario`
--
ALTER TABLE `movimiento_inventario`
  ADD PRIMARY KEY (`id_movimiento`),
  ADD KEY `id_lote` (`id_lote`),
  ADD KEY `id_bodega` (`id_bodega`),
  ADD KEY `idx_movimiento_fecha` (`fecha_movimiento`),
  ADD KEY `idx_movimiento_tipo` (`tipo_movimiento`),
  ADD KEY `idx_movimiento_fecha_tipo` (`fecha_movimiento`,`tipo_movimiento`);

--
-- Indices de la tabla `pedido`
--
ALTER TABLE `pedido`
  ADD PRIMARY KEY (`id_pedido`),
  ADD KEY `idx_pedido_estado` (`estado`),
  ADD KEY `idx_pedido_fecha` (`fecha_pedido`),
  ADD KEY `idx_pedido_distribuidor_estado` (`id_distribuidor`,`estado`);

--
-- Indices de la tabla `planta`
--
ALTER TABLE `planta`
  ADD PRIMARY KEY (`id_planta`),
  ADD UNIQUE KEY `nombre` (`nombre`);

--
-- Indices de la tabla `producto`
--
ALTER TABLE `producto`
  ADD PRIMARY KEY (`id_producto`),
  ADD UNIQUE KEY `codigo_unico` (`codigo_unico`),
  ADD KEY `idx_producto_nombre` (`nombre_comercial`),
  ADD KEY `idx_producto_tipo` (`tipo`);

--
-- Indices de la tabla `usuario_sistema`
--
ALTER TABLE `usuario_sistema`
  ADD PRIMARY KEY (`id_usuario`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `idx_usuario_rol` (`rol`),
  ADD KEY `idx_usuario_activo` (`activo`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `auditoria_cambios`
--
ALTER TABLE `auditoria_cambios`
  MODIFY `id_audit` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `bodega`
--
ALTER TABLE `bodega`
  MODIFY `id_bodega` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `detalle_pedido`
--
ALTER TABLE `detalle_pedido`
  MODIFY `id_detalle` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT de la tabla `distribuidor`
--
ALTER TABLE `distribuidor`
  MODIFY `id_distribuidor` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `factura`
--
ALTER TABLE `factura`
  MODIFY `id_factura` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `inventario_bodega`
--
ALTER TABLE `inventario_bodega`
  MODIFY `id_inventario` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `log_accesos`
--
ALTER TABLE `log_accesos`
  MODIFY `id_log` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `lote_produccion`
--
ALTER TABLE `lote_produccion`
  MODIFY `id_lote` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimiento_inventario`
--
ALTER TABLE `movimiento_inventario`
  MODIFY `id_movimiento` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `pedido`
--
ALTER TABLE `pedido`
  MODIFY `id_pedido` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `planta`
--
ALTER TABLE `planta`
  MODIFY `id_planta` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `producto`
--
ALTER TABLE `producto`
  MODIFY `id_producto` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `usuario_sistema`
--
ALTER TABLE `usuario_sistema`
  MODIFY `id_usuario` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `bodega`
--
ALTER TABLE `bodega`
  ADD CONSTRAINT `bodega_ibfk_1` FOREIGN KEY (`id_planta`) REFERENCES `planta` (`id_planta`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `detalle_pedido`
--
ALTER TABLE `detalle_pedido`
  ADD CONSTRAINT `detalle_pedido_ibfk_1` FOREIGN KEY (`id_pedido`) REFERENCES `pedido` (`id_pedido`) ON DELETE CASCADE,
  ADD CONSTRAINT `detalle_pedido_ibfk_2` FOREIGN KEY (`id_producto`) REFERENCES `producto` (`id_producto`);

--
-- Filtros para la tabla `factura`
--
ALTER TABLE `factura`
  ADD CONSTRAINT `factura_ibfk_1` FOREIGN KEY (`id_pedido`) REFERENCES `pedido` (`id_pedido`);

--
-- Filtros para la tabla `inventario_bodega`
--
ALTER TABLE `inventario_bodega`
  ADD CONSTRAINT `inventario_bodega_ibfk_1` FOREIGN KEY (`id_lote`) REFERENCES `lote_produccion` (`id_lote`),
  ADD CONSTRAINT `inventario_bodega_ibfk_2` FOREIGN KEY (`id_bodega`) REFERENCES `bodega` (`id_bodega`);

--
-- Filtros para la tabla `lote_produccion`
--
ALTER TABLE `lote_produccion`
  ADD CONSTRAINT `lote_produccion_ibfk_1` FOREIGN KEY (`id_producto`) REFERENCES `producto` (`id_producto`),
  ADD CONSTRAINT `lote_produccion_ibfk_2` FOREIGN KEY (`id_planta`) REFERENCES `planta` (`id_planta`);

--
-- Filtros para la tabla `movimiento_inventario`
--
ALTER TABLE `movimiento_inventario`
  ADD CONSTRAINT `movimiento_inventario_ibfk_1` FOREIGN KEY (`id_lote`) REFERENCES `lote_produccion` (`id_lote`),
  ADD CONSTRAINT `movimiento_inventario_ibfk_2` FOREIGN KEY (`id_bodega`) REFERENCES `bodega` (`id_bodega`);

--
-- Filtros para la tabla `pedido`
--
ALTER TABLE `pedido`
  ADD CONSTRAINT `pedido_ibfk_1` FOREIGN KEY (`id_distribuidor`) REFERENCES `distribuidor` (`id_distribuidor`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
