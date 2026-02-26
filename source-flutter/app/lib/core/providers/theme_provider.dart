// Re-exports de providers de tema y configuración de apariencia.
// Centraliza el acceso para main.dart y otros puntos de entrada.
export '../theme/pilar_theme.dart'
    show
        themeBrightnessProvider,
        empresaColorProvider,
        PilarTheme;

export '../services/config_service.dart' show appConfigProvider, ConfigService, ConfigKeys;
